-- Real KAM GO helpline: WhatsApp and SIM call both go to 0312 6865361.
-- (The first migration seeded a placeholder number; admins can still edit these in Settings.)
insert into public.settings (key, value, description) values
  ('support_whatsapp', '"923126865361"',  'WhatsApp number for Contact KAM GO (no +)'),
  ('support_phone',    '"+923126865361"', 'Phone number for Contact KAM GO')
on conflict (key) do update set value = excluded.value;
