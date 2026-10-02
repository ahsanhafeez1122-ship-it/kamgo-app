/// Normalises Pakistani mobile numbers to E.164 (`+923XXXXXXXXX`).
/// Accepts `03001234567`, `3001234567`, `923001234567`, `+92 300 1234567`.
/// Returns null when the input is not a valid PK mobile number.
String? normalizePkPhone(String input) {
  var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('0092')) digits = digits.substring(4);
  if (digits.startsWith('92')) digits = digits.substring(2);
  if (digits.startsWith('0')) digits = digits.substring(1);
  if (!RegExp(r'^3\d{9}$').hasMatch(digits)) return null;
  return '+92$digits';
}

/// `+923001234567` → `0300 1234567` for display.
String formatPkPhone(String e164) {
  final d = e164.replaceAll(RegExp(r'[^0-9]'), '');
  final local = d.startsWith('92') ? '0${d.substring(2)}' : d;
  if (local.length != 11) return e164;
  return '${local.substring(0, 4)} ${local.substring(4)}';
}
