// KAM GO — push notifications.
//
// Triggered by a Supabase Database Webhook on INSERT into public.notifications.
// Looks up the user's device tokens and sends a small FCM (HTTP v1) message.
//
// Secrets (supabase secrets set …):
//   FIREBASE_SERVICE_ACCOUNT  the Firebase service-account JSON (one line)
//   PUSH_WEBHOOK_SECRET       shared secret; the webhook must send it in
//                             the "x-webhook-secret" header
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically.

import { createClient } from "jsr:@supabase/supabase-js@2";

type NotificationRow = {
  id: string;
  user_id: string;
  type: string;
  title: string;
  body: string | null;
  data: Record<string, unknown> | null;
};

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

let cachedToken: { value: string; expires: number } | null = null;

function b64url(input: ArrayBuffer | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : new Uint8Array(input);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function googleAccessToken(sa: { client_email: string; private_key: string }): Promise<string> {
  if (cachedToken && cachedToken.expires > Date.now() + 60_000) return cachedToken.value;

  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`));
  const jwt = `${header}.${claims}.${b64url(sig)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  if (!res.ok) throw new Error(`Google token error ${res.status}: ${await res.text()}`);
  const json = await res.json();
  cachedToken = { value: json.access_token, expires: Date.now() + json.expires_in * 1000 };
  return cachedToken.value;
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("PUSH_WEBHOOK_SECRET");
  if (!secret || req.headers.get("x-webhook-secret") !== secret) {
    return new Response("unauthorized", { status: 401 });
  }

  const payload = await req.json();
  const row = payload?.record as NotificationRow | undefined;
  if (payload?.type !== "INSERT" || !row?.user_id) return new Response("ignored");

  const { data: tokens, error } = await supabase
    .from("device_tokens").select("token").eq("user_id", row.user_id);
  if (error) return new Response(error.message, { status: 500 });
  if (!tokens?.length) return new Response("no devices");

  const sa = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!);
  const accessToken = await googleAccessToken(sa);

  // FCM data values must be strings; keep the payload small for weak networks.
  const data: Record<string, string> = { type: row.type, notification_id: row.id };
  for (const [k, v] of Object.entries(row.data ?? {})) data[k] = String(v);

  let sent = 0;
  for (const { token } of tokens) {
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: row.title, body: row.body ?? "" },
          data,
          android: { priority: "high", notification: { channel_id: "kamgo_rides" } },
        },
      }),
    });
    if (res.ok) {
      sent++;
    } else if (res.status === 404 || res.status === 400) {
      // Uninstalled app / stale token.
      await supabase.from("device_tokens").delete().eq("token", token);
    }
  }
  return new Response(JSON.stringify({ sent }), { headers: { "Content-Type": "application/json" } });
});
