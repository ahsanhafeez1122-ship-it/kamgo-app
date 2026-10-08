import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../passenger/presentation/map_pick_screen.dart';
import '../../../rides/domain/catalog.dart';
import '../../../rides/domain/map_pick.dart';
import '../../../rides/domain/ride_models.dart';
import '../admin_widgets.dart';

const _kinds = ['town', 'village', 'hamlet', 'stop', 'landmark', 'place'];

/// Villages, addas, stops and landmarks. They show first in the passenger's map search.
class AdminPlacesPage extends ConsumerStatefulWidget {
  const AdminPlacesPage({super.key});

  @override
  ConsumerState<AdminPlacesPage> createState() => _AdminPlacesPageState();
}

class _AdminPlacesPageState extends ConsumerState<AdminPlacesPage> {
  int _v = 0;
  String _filter = '';

  Future<Catalog> _catalog() async {
    final rows = await ref.read(adminRepositoryProvider).cities();
    return Catalog(
      cities: [for (final c in rows) if (c['is_active'] == true) City.fromJson(c)],
      routes: const [],
      settings: const AppSettings(),
    );
  }

  Future<void> _edit([Map<String, dynamic>? place]) async {
    final name = TextEditingController(text: place?['name'] as String?);
    final coords = TextEditingController(
      text: place == null ? '' : '${place['lat']}, ${place['lng']}',
    );
    var kind = place?['kind'] as String? ?? 'village';
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(place == null ? 'Add place' : 'Edit ${place['name']}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Name, e.g. Chak 360 GB or Bus Stand Kamalia')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [for (final k in _kinds) DropdownMenuItem(value: k, child: Text(k))],
                  onChanged: (v) => set(() => kind = v ?? kind),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: coords,
                      decoration: const InputDecoration(labelText: 'Coordinates (lat, lng)', hintText: '30.75, 72.50'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Pick on map'),
                    onPressed: () async {
                      final parts = coords.text.split(',').map((p) => double.tryParse(p.trim())).toList();
                      final catalog = await _catalog();
                      if (!context.mounted) return;
                      final pick = await pickOnMap(
                        context,
                        title: 'Place location',
                        catalog: catalog,
                        initial: parts.length == 2 && parts[0] != null && parts[1] != null
                            ? MapPick(point: GeoPoint(parts[0]!, parts[1]!), nearestName: '')
                            : null,
                      );
                      if (pick != null) {
                        set(() => coords.text = '${pick.point.lat.toStringAsFixed(5)}, ${pick.point.lng.toStringAsFixed(5)}');
                      }
                    },
                  ),
                ]),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (save != true || !mounted) return;
    final parts = coords.text.split(',').map((p) => double.tryParse(p.trim())).toList();
    if (parts.length != 2 || parts[0] == null || parts[1] == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter coordinates like 30.75, 72.50')));
      return;
    }
    final ok = await adminAction(
      context,
      () => ref.read(adminRepositoryProvider).savePlace({
        'name': name.text.trim(),
        'kind': kind,
        'lat': parts[0],
        'lng': parts[1],
      }, id: place?['id'] as String?),
      success: 'Place saved',
    );
    if (ok) setState(() => _v++);
    name.dispose();
    coords.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(adminRepositoryProvider);
    return AdminPage(
      title: 'Places',
      actions: [
        SizedBox(
          width: 220,
          child: TextField(
            decoration: const InputDecoration(hintText: 'Search places', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
          ),
        ),
        FilledButton.icon(onPressed: _edit, icon: const Icon(Icons.add), label: const Text('Add place')),
      ],
      child: AdminLoader<List<Map<String, dynamic>>>(
        key: ValueKey(_v),
        load: repo.places,
        builder: (context, rows, _) {
          final shown = [
            for (final p in rows)
              if (_filter.isEmpty || (p['name'] as String).toLowerCase().contains(_filter)) p,
          ];
          return AdminTable(
            columns: const ['Place', 'Type', 'Coordinates', 'Active', ''],
            rows: [
              for (final p in shown)
                DataRow(cells: [
                  DataCell(Text(p['name'] as String, style: AppText.body(14, weight: FontWeight.w600))),
                  DataCell(Text(p['source'] == 'learned'
                      ? 'learned from rides ×${p['confirmations']}'
                      : p['kind'] as String)),
                  DataCell(Text('${(p['lat'] as num).toStringAsFixed(4)}, ${(p['lng'] as num).toStringAsFixed(4)}')),
                  DataCell(Switch(
                    value: p['is_active'] as bool,
                    onChanged: (v) async {
                      final ok = await adminAction(context, () => repo.savePlace({'is_active': v}, id: p['id'] as String));
                      if (ok) setState(() => _v++);
                    },
                  )),
                  DataCell(Row(children: [
                    TextButton(onPressed: () => _edit(p), child: const Text('Edit')),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                      onPressed: () async {
                        final ok = await adminAction(context, () => repo.deletePlace(p['id'] as String), success: 'Deleted');
                        if (ok) setState(() => _v++);
                      },
                    ),
                  ])),
                ]),
            ],
          );
        },
      ),
    );
  }
}

/// Ride types: display order, seats, and every number the fare engine uses.
/// Nothing about a price lives in the app; this page is where it is changed.
class AdminCategoriesPage extends ConsumerStatefulWidget {
  const AdminCategoriesPage({super.key});

  @override
  ConsumerState<AdminCategoriesPage> createState() => _AdminCategoriesPageState();
}

class _AdminCategoriesPageState extends ConsumerState<AdminCategoriesPage> {
  int _v = 0;

  // column -> label (all numeric)
  static const _numbers = <String, String>{
    'sort_order': 'Display order',
    'max_passengers': 'Seats',
    'city_mileage': 'City mileage (km/l)',
    'highway_mileage': 'Highway mileage (km/l)',
    'city_maint': 'City maintenance (Rs/km)',
    'highway_maint': 'Highway maintenance (Rs/km)',
    'min_fare': 'Minimum fare (Rs.)',
    'waiting_per_min': 'Waiting (Rs/min)',
    'max_km': 'Longest trip (km, empty = no limit)',
    'loading_charge': 'Loading charge (Rs.)',
    'round_trip_wait_per_hour': 'Round-trip waiting (Rs/hour)',
    'hour_profit': 'Hourly: profit per hour (Rs.)',
    'extra_km_rate': 'Hourly: extra km (Rs/km)',
    'extra_hour_rate': 'Hourly: extra hour (Rs/hour)',
  };

  Future<void> _edit(Map<String, dynamic> c) async {
    final ctrl = {for (final k in _numbers.keys) k: TextEditingController(text: c[k] == null ? '' : '${c[k]}')};
    final name = TextEditingController(text: c['name'] as String?);
    final profit = TextEditingController(text: jsonEncode(c['profit_points']));
    var isCar = c['is_car'] as bool? ?? false;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text('Edit ${c['name']}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Is a car (AC option, hourly and round trips)'),
                    value: isCar,
                    onChanged: (v) => set(() => isCar = v),
                  ),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    for (final e in _numbers.entries)
                      SizedBox(
                        width: 245,
                        child: TextField(controller: ctrl[e.key], decoration: InputDecoration(labelText: e.value)),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                    controller: profit,
                    decoration: const InputDecoration(
                      labelText: 'Profit points [[km, profit], ...]',
                      helperText: 'The fare adds the profit for the trip distance (in between points it is a straight line).',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    final points = save == true ? _parsePoints(profit.text) : null;
    if (save == true && points == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profit points must look like [[0,200],[5,500]]')));
    } else if (save == true && mounted) {
      final data = <String, dynamic>{
        'name': name.text.trim(),
        'is_car': isCar,
        'profit_points': points,
        for (final e in ctrl.entries) e.key: num.tryParse(e.value.text.trim()),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      final ok = await adminAction(
        context,
        () => ref.read(adminRepositoryProvider).saveCategory(c['code'] as String, data),
        success: 'Ride type saved',
      );
      if (ok) setState(() => _v++);
    }
    name.dispose();
    profit.dispose();
    for (final x in ctrl.values) {
      x.dispose();
    }
  }

  List<dynamic>? _parsePoints(String text) {
    try {
      final v = jsonDecode(text);
      if (v is List && v.isNotEmpty && v.every((p) => p is List && p.length == 2 && p.every((n) => n is num))) return v;
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(adminRepositoryProvider);
    return AdminPage(
      title: 'Ride types',
      child: AdminLoader<List<Map<String, dynamic>>>(
        key: ValueKey(_v),
        load: repo.categories,
        builder: (context, rows, _) => AdminTable(
          columns: const ['#', 'Type', 'Seats', 'Mileage city / hwy', 'Maint city / hwy', 'Min fare', 'Max km', 'Active', ''],
          rows: [
            for (final c in rows)
              DataRow(cells: [
                DataCell(Text('${c['sort_order']}')),
                DataCell(Text(c['name'] as String, style: AppText.body(14, weight: FontWeight.w600))),
                DataCell(Text('${c['max_passengers']}')),
                DataCell(Text('${c['city_mileage']} / ${c['highway_mileage']}')),
                DataCell(Text('${c['city_maint']} / ${c['highway_maint']}')),
                DataCell(Text('Rs. ${c['min_fare']}')),
                DataCell(Text(c['max_km'] == null ? '—' : '${c['max_km']} km')),
                DataCell(Switch(
                  value: c['is_active'] as bool,
                  onChanged: (v) async {
                    final ok = await adminAction(context, () => repo.saveCategory(c['code'] as String, {'is_active': v}));
                    if (ok) setState(() => _v++);
                  },
                )),
                DataCell(TextButton(onPressed: () => _edit(c), child: const Text('Edit'))),
              ]),
          ],
        ),
      ),
    );
  }
}