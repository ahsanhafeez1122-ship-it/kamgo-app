import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../admin_widgets.dart';

/// Vehicle models: which model belongs to which ride type. Drivers pick a model when they
/// register and the ride type follows from it.
class AdminVehicleModelsPage extends ConsumerStatefulWidget {
  const AdminVehicleModelsPage({super.key});

  @override
  ConsumerState<AdminVehicleModelsPage> createState() => _AdminVehicleModelsPageState();
}

class _AdminVehicleModelsPageState extends ConsumerState<AdminVehicleModelsPage> {
  int _v = 0;

  Future<void> _edit(List<Map<String, dynamic>> cats, [Map<String, dynamic>? m]) async {
    final make = TextEditingController(text: m?['make'] as String?);
    final model = TextEditingController(text: m?['model'] as String?);
    var category = m?['category'] as String? ?? cats.first['code'] as String;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(m == null ? 'Add vehicle model' : 'Edit model'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: make, decoration: const InputDecoration(labelText: 'Make, e.g. Suzuki')),
              const SizedBox(height: 10),
              TextField(controller: model, decoration: const InputDecoration(labelText: 'Model, e.g. Alto')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Ride type'),
                items: [for (final c in cats) DropdownMenuItem(value: c['code'] as String, child: Text(c['name'] as String))],
                onChanged: (v) => set(() => category = v ?? category),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (save == true && mounted) {
      final ok = await adminAction(
        context,
        () => ref.read(adminRepositoryProvider).saveVehicleModel(
            {'make': make.text.trim(), 'model': model.text.trim(), 'category': category},
            id: m?['id'] as String?),
        success: 'Model saved',
      );
      if (ok) setState(() => _v++);
    }
    make.dispose();
    model.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(adminRepositoryProvider);
    return AdminLoader<List<List<Map<String, dynamic>>>>(
      key: ValueKey(_v),
      load: () => Future.wait([repo.vehicleModels(), repo.categories()]),
      builder: (context, data, _) {
        final names = {for (final c in data[1]) c['code'] as String: c['name'] as String};
        return AdminPage(
          title: 'Vehicle models',
          actions: [
            FilledButton.icon(onPressed: () => _edit(data[1]), icon: const Icon(Icons.add), label: const Text('Add model')),
          ],
          child: AdminTable(
            columns: const ['Make', 'Model', 'Ride type', 'Active', ''],
            rows: [
              for (final m in data[0])
                DataRow(cells: [
                  DataCell(Text(m['make'] as String)),
                  DataCell(Text(m['model'] as String, style: AppText.body(14, weight: FontWeight.w600))),
                  DataCell(Text(names[m['category']] ?? '${m['category']}')),
                  DataCell(Switch(
                    value: m['is_active'] as bool? ?? true,
                    onChanged: (v) async {
                      final ok = await adminAction(context, () => repo.saveVehicleModel({'is_active': v}, id: m['id'] as String));
                      if (ok) setState(() => _v++);
                    },
                  )),
                  DataCell(Row(children: [
                    TextButton(onPressed: () => _edit(data[1], m), child: const Text('Edit')),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                      onPressed: () async {
                        final ok = await adminAction(context, () => repo.deleteVehicleModel(m['id'] as String), success: 'Deleted');
                        if (ok) setState(() => _v++);
                      },
                    ),
                  ])),
                ]),
            ],
          ),
        );
      },
    );
  }
}

/// Average accepted fare against the recommended fare, per city and ride type.
class AdminFareReportPage extends ConsumerStatefulWidget {
  const AdminFareReportPage({super.key});

  @override
  ConsumerState<AdminFareReportPage> createState() => _AdminFareReportPageState();
}

class _AdminFareReportPageState extends ConsumerState<AdminFareReportPage> {
  DateTimeRange? _range;
  String? _type;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(adminRepositoryProvider);
    String d(DateTime t) => t.toIso8601String().substring(0, 10);
    return AdminPage(
      title: 'Fare report',
      actions: [
        for (final t in const [(null, 'All types'), ('one_way', 'One way'), ('hourly', 'Hourly'), ('round_trip', 'Round trip')])
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(label: Text(t.$2), selected: _type == t.$1, onSelected: (_) => setState(() => _type = t.$1)),
          ),
        OutlinedButton.icon(
          icon: const Icon(Icons.date_range_rounded),
          label: Text(_range == null ? 'All dates' : '${d(_range!.start)} → ${d(_range!.end)}'),
          onPressed: () async {
            final r = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2024),
              lastDate: DateTime.now().add(const Duration(days: 1)),
              initialDateRange: _range,
            );
            if (r != null) setState(() => _range = r);
          },
        ),
        if (_range != null) TextButton(onPressed: () => setState(() => _range = null), child: const Text('Clear')),
      ],
      child: AdminLoader<List<Map<String, dynamic>>>(
        key: ValueKey('$_range/$_type'),
        load: () => repo.fareReport(from: _range?.start, to: _range?.end, bookingType: _type),
        builder: (context, rows, _) => rows.isEmpty
            ? const Padding(padding: EdgeInsets.all(24), child: Text('No completed rides in this period.'))
            : AdminTable(
                columns: const ['City', 'Ride type', 'Booking', 'Rides', 'Avg recommended', 'Avg accepted', 'Accepted vs recommended', 'Commission'],
                rows: [
                  for (final r in rows)
                    DataRow(cells: [
                      DataCell(Text('${r['city_name'] ?? '—'}')),
                      DataCell(Text('${r['category_name'] ?? r['category']}')),
                      DataCell(Text(switch (r['booking_type']) { 'hourly' => 'Hourly', 'round_trip' => 'Round trip', _ => 'One way' })),
                      DataCell(Text('${r['rides']}')),
                      DataCell(Text('Rs. ${r['avg_recommended'] ?? '—'}')),
                      DataCell(Text('Rs. ${r['avg_accepted'] ?? '—'}')),
                      DataCell(Text(r['accepted_vs_recommended_pct'] == null ? '—' : '${r['accepted_vs_recommended_pct']}%')),
                      DataCell(Text('Rs. ${r['total_commission']}')),
                    ]),
                ],
              ),
      ),
    );
  }
}
/// Hourly packages: hours, included km and the profit multiplier. Edited here, never in code.
class AdminPackagesPage extends ConsumerStatefulWidget {
  const AdminPackagesPage({super.key});

  @override
  ConsumerState<AdminPackagesPage> createState() => _AdminPackagesPageState();
}

class _AdminPackagesPageState extends ConsumerState<AdminPackagesPage> {
  int _v = 0;

  Future<void> _edit([Map<String, dynamic>? p]) async {
    final hours = TextEditingController(text: p == null ? '' : '${p['hours']}');
    final km = TextEditingController(text: p == null ? '' : '${p['included_km']}');
    final mult = TextEditingController(text: p == null ? '1.0' : '${p['profit_multiplier']}');
    final order = TextEditingController(text: '${p?['sort_order'] ?? 0}');
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(p == null ? 'Add package' : 'Edit package'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: hours, decoration: const InputDecoration(labelText: 'Hours')),
            const SizedBox(height: 10),
            TextField(controller: km, decoration: const InputDecoration(labelText: 'Included km')),
            const SizedBox(height: 10),
            TextField(controller: mult, decoration: const InputDecoration(labelText: 'Profit multiplier (e.g. 1.0)')),
            const SizedBox(height: 10),
            TextField(controller: order, decoration: const InputDecoration(labelText: 'Display order')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (save == true && mounted) {
      final ok = await adminAction(
        context,
        () => ref.read(adminRepositoryProvider).saveHourlyPackage({
          'hours': int.tryParse(hours.text.trim()),
          'included_km': num.tryParse(km.text.trim()),
          'profit_multiplier': num.tryParse(mult.text.trim()),
          'sort_order': int.tryParse(order.text.trim()) ?? 0,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, id: p?['id'] as String?),
        success: 'Package saved',
      );
      if (ok) setState(() => _v++);
    }
    for (final c in [hours, km, mult, order]) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(adminRepositoryProvider);
    return AdminPage(
      title: 'Hourly packages',
      actions: [FilledButton.icon(onPressed: _edit, icon: const Icon(Icons.add), label: const Text('Add package'))],
      child: AdminLoader<List<Map<String, dynamic>>>(
        key: ValueKey(_v),
        load: repo.hourlyPackages,
        builder: (context, rows, _) => AdminTable(
          columns: const ['Hours', 'Included km', 'Profit multiplier', 'Order', 'Active', ''],
          rows: [
            for (final p in rows)
              DataRow(cells: [
                DataCell(Text('${p['hours']} h', style: AppText.body(14, weight: FontWeight.w600))),
                DataCell(Text('${p['included_km']} km')),
                DataCell(Text('x ${p['profit_multiplier']}')),
                DataCell(Text('${p['sort_order']}')),
                DataCell(Switch(
                  value: p['is_active'] as bool,
                  onChanged: (v) async {
                    final ok = await adminAction(context, () => repo.saveHourlyPackage({'is_active': v}, id: p['id'] as String));
                    if (ok) setState(() => _v++);
                  },
                )),
                DataCell(Row(children: [
                  TextButton(onPressed: () => _edit(p), child: const Text('Edit')),
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                    onPressed: () async {
                      final ok = await adminAction(context, () => repo.deleteHourlyPackage(p['id'] as String), success: 'Deleted');
                      if (ok) setState(() => _v++);
                    },
                  ),
                ])),
              ]),
          ],
        ),
      ),
    );
  }
}