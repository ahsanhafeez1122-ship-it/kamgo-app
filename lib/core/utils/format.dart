import 'package:intl/intl.dart';

final _rupees = NumberFormat.decimalPattern('en_PK');

final _rupeesPaisa = NumberFormat('#,##0.##', 'en_PK');

/// A place as the person wrote or chose it; the town name only when nothing was written.
String placeName(String? label, String town) =>
    label == null || label.trim().isEmpty ? town : label.trim();

/// `Kamalia`, `Pir Mahal` → `Kamalia → Pir Mahal`; inside one town
/// `Kamalia · local trip`.
String tripTitle(String origin, String destination) =>
    origin == destination ? '$origin · local trip' : '$origin → $destination';

/// `1200` → `Rs. 1,200`; `115.5` → `Rs. 115.5` (paisa only when present).
String formatFare(num value) {
  final cents = (value * 100).round();
  return cents % 100 == 0
      ? 'Rs. ${_rupees.format(cents ~/ 100)}'
      : 'Rs. ${_rupeesPaisa.format(cents / 100)}';
}

/// `Ali Raza` → `AR`
String initialsOf(String? name) {
  final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return 'KG';
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

String greetingFor(DateTime now) {
  final h = now.hour;
  if (h < 12) return 'Good Morning';
  if (h < 17) return 'Good Afternoon';
  return 'Good Evening';
}
