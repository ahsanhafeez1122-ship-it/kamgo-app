import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../admin_widgets.dart';

class AdminCitiesPage extends ConsumerStatefulWidget {
  const AdminCitiesPage({super.key});

  @override
  ConsumerState<AdminCitiesPage> createState() => _AdminCitiesPageState();
}

class _AdminCitiesPageState extends ConsumerState<AdminCitiesPage> {
  int _v = 0;

  Future<void> _edit([Map<String, dynamic>? city]) async {
    final name = TextEditingController(text: city?['name'] as String?);
    final nameUr = TextEditingController(text: city?['name_ur'] as String?);
    final lat = TextEditingController(text: city?['lat']?.toString());
    final lng = TextEditingController(text: city?['lng']?.toString());
    final order = TextEditingController(text: '${city?['sort_order'] ?? 0}');
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(city == null ? 'Add city' : 'Edit ${city['name']}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 10),
              TextField(controller: nameUr, decoration: const InputDecoration(labelText: 'Name (Urdu)')),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: lat, decoration: const InputDecoration(labelText: 'Latitude'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: lng, decoration: const InputDecoration(labelText: 'Longitude'))),
              ]),
              const SizedBox(height: 10),
              TextField(controller: order, decoration: const InputDecoration(labelText: 'Sort order')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (save != true || !mounted) return;
    final ok = await adminAction(
      context,
      () => ref.read(adminRepositoryProvider).saveCity({
        'name': name.text.trim(),
        'name_ur': nameUr.text.trim().isEmpty ? null : nameUr.text.trim(),
        'lat': double.tryParse(lat.text),
        'lng': double.tryParse(lng.text),
        'sort_order': int.tryParse(order.text) ?? 0,
      }, id: city?['id'] as String?),
      success: 'City saved',
    );
    if (ok) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(adminRepositoryProvider);
    return AdminPage(
      title: 'Cities',
      actions: [FilledButton.icon(onPressed: _edit, icon: const Icon(Icons.add), label: const Text('Add city'))],
      child: AdminLoader<List<Map<String, dynamic>>>(
        key: ValueKey(_v),
        load: repo.cities,
        builder: (context, rows, _) => AdminTable(
          columns: const ['City', 'Urdu', 'Coordinates', 'Order', 'Active', ''],
          rows: [
            for (final c in rows)
              DataRow(cells: [
                DataCell(Text(c['name'] as String, style: AppText.body(14, weight: FontWeight.w600))),
                DataCell(Text(c['name_ur'] as String? ?? '')),
                DataCell(Text('${c['lat'] ?? '—'}, ${c['lng'] ?? '—'}')),
                DataCell(Text('${c['sort_order']}')),
                DataCell(Switch(
                  value: c['is_active'] as bool,
                  onChanged: (v) async {
                    final ok = await adminAction(context, () => repo.saveCity({'is_active': v}, id: c['id'] as String));
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

class AdminRoutesPage extends ConsumerStatefulWidget {
  const AdminRoutesPage({super.key});

  @override
  ConsumerState<AdminRoutesPage> createState() => _AdminRoutesPageState();
}

class _AdminRoutesPageState extends ConsumerState<AdminRoutesPage> {
  int _v = 0;

  Future<void> _edit(List<Map<String, dynamic>> cities, [Map<String, dynamic>? route]) async {
    String? origin = route?['origin_city_id'] as String?;
    String? dest = route?['destination_city_id'] as String?;
    final km = TextEditingController(text: route?['distance_km']?.toString());
    final min = TextEditingController(text: route?['est_duration_min']?.toString());
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(route == null ? 'Add route' : 'Edit route'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: origin,
                  decoration: const InputDecoration(labelText: 'From'),
                  items: [for (final c in cities) DropdownMenuItem(value: c['id'] as String, child: Text(c['name'] as String))],
                  onChanged: route == null ? (v) => set(() => origin = v) : null,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: dest,
                  decoration: const InputDecoration(labelText: 'To'),
                  items: [for (final c in cities) DropdownMenuItem(value: c['id'] as String, child: Text(c['name'] as String))],
                  onChanged: route == null ? (v) => set(() => dest = v) : null,
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: km, decoration: const InputDecoration(labelText: 'Distance (km)'))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: min, decoration: const InputDecoration(labelText: 'Duration (min)'))),
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
    final ok = await adminAction(
      context,
      () => ref.read(adminRepositoryProvider).saveRoute({
        if (route == null) 'origin_city_id': origin,
        if (route == null) 'destination_city_id': dest,
        'distance_km': double.tryParse(km.text),
        'est_duration_min': int.tryParse(min.text),
      }, id: route?['id'] as String?),
      success: 'Route saved',
    );
    if (ok) setState(() => _v++);
  }

  Future<void> _stops(Map<String, dynamic> route) async {
    final repo = ref.read(adminRepositoryProvider);
    await showDialog<void>(
      context: context,
      builder: (context) {
        var version = 0;
        return StatefulBuilder(
          builder: (context, set) => AlertDialog(
            title: Text('Stops — ${route['origin']['name']} → ${route['destination']['name']}'),
            content: SizedBox(
              width: 440,
              child: AdminLoader<List<Map<String, dynamic>>>(
                key: ValueKey(version),
                load: () => repo.stops(route['id'] as String),
                builder: (context, stops, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (stops.isEmpty) const Text('No stops — direct route.'),
                    for (final s in stops)
                      ListTile(
                        leading: CircleAvatar(radius: 14, child: Text('${s['stop_order']}')),
                        title: Text(s['name'] as String),
                        subtitle: Text('${s['lat'] ?? ''} ${s['lng'] ?? ''}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                          onPressed: () async {
                            await adminAction(context, () => repo.deleteStop(s['id'] as String));
                            set(() => version++);
                          },
                        ),
                      ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add stop'),
                      onPressed: () async {
                        final name = await askText(context, 'Stop name');
                        if (name == null || name.isEmpty || !context.mounted) return;
                        final coords = await askText(context, 'Coordinates (optional)', hint: '30.75, 72.50');
                        final parts = (coords ?? '').split(',').map((p) => double.tryParse(p.trim())).toList();
                        if (!context.mounted) return;
                        await adminAction(
                          context,
                          () => repo.addStop(route['id'] as String, name, stops.length + 1,
                              lat: parts.isNotEmpty ? parts[0] : null, lng: parts.length > 1 ? parts[1] : null),
                        );
                        set(() => version++);
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(adminRepositoryProvider);
    return AdminLoader<List<List<Map<String, dynamic>>>>(
      key: ValueKey(_v),
      load: () => Future.wait([repo.routes(), repo.cities()]),
      builder: (context, data, _) => AdminPage(
        title: 'Routes',
        actions: [
          FilledButton.icon(onPressed: () => _edit(data[1]), icon: const Icon(Icons.add), label: const Text('Add route')),
        ],
        child: AdminTable(
          columns: const ['Route', 'Distance', 'Duration', 'Active', ''],
          rows: [
            for (final r in data[0])
              DataRow(cells: [
                DataCell(Text('${r['origin']['name']} → ${r['destination']['name']}',
                    style: AppText.body(14, weight: FontWeight.w600))),
                DataCell(Text('${r['distance_km']} km')),
                DataCell(Text('${r['est_duration_min'] ?? '—'} min')),
                DataCell(Switch(
                  value: r['is_active'] as bool,
                  onChanged: (v) async {
                    final ok = await adminAction(context, () => repo.saveRoute({'is_active': v}, id: r['id'] as String));
                    if (ok) setState(() => _v++);
                  },
                )),
                DataCell(Row(children: [
                  TextButton(onPressed: () => _edit(data[1], r), child: const Text('Edit')),
                  TextButton(onPressed: () => _stops(r), child: const Text('Stops')),
                ])),
              ]),
          ],
        ),
      ),
    );
  }
}
