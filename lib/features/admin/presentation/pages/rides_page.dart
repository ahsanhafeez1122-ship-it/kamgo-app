import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_text.dart';
import '../../../../core/utils/format.dart';
import '../../../rides/presentation/ride_screen.dart';
import '../admin_widgets.dart';

class AdminRidesPage extends ConsumerStatefulWidget {
  const AdminRidesPage({super.key});

  @override
  ConsumerState<AdminRidesPage> createState() => _AdminRidesPageState();
}

class _AdminRidesPageState extends ConsumerState<AdminRidesPage> {
  String? _status;
  String? _cityId;
  String _search = '';
  int _v = 0;

  static const _statuses = ['CONFIRMED', 'DRIVER_ARRIVING', 'RIDE_STARTED', 'COMPLETED', 'CANCELLED', 'NO_SHOW'];

  Future<void> _open(Map<String, dynamic> r) async {
    final active = ['CONFIRMED', 'DRIVER_ARRIVING', 'RIDE_STARTED'].contains(r['status']);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(r['route'] as String),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Passenger: ${r['passenger_name']} (${r['passenger_phone']})', style: AppText.body(14)),
              Text('Driver: ${r['driver_name']} (${r['driver_phone']})', style: AppText.body(14)),
              const SizedBox(height: 6),
              StatusPill(r['status'] as String),
              const SizedBox(height: 14),
              CommissionBreakdownCard(
                fare: (r['final_fare'] as num).toDouble(),
                commission: (r['commission_amount'] as num?)?.toDouble() ?? 0,
                earning: (r['driver_earning'] as num?)?.toDouble() ?? (r['final_fare'] as num).toDouble(),
                note: r['commission_amount'] == null ? 'Commission is recorded when the ride is completed.' : null,
              ),
            ],
          ),
        ),
        actions: [
          if (active)
            TextButton(
              onPressed: () async {
                final note = await askText(context, 'Cancel ride — reason');
                if (note == null || note.isEmpty || !context.mounted) return;
                final ok = await adminAction(context,
                    () => ref.read(adminRepositoryProvider).cancelRide(r['ride_id'] as String, note),
                    success: 'Ride cancelled');
                if (ok && context.mounted) {
                  Navigator.pop(context);
                  setState(() => _v++);
                }
              },
              child: const Text('Cancel ride'),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(adminRepositoryProvider);
    return AdminLoader<List<Map<String, dynamic>>>(
      load: repo.cities,
      builder: (context, cities, _) => AdminPage(
        title: 'Rides',
        actions: [
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String?>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All')),
                for (final s in _statuses) DropdownMenuItem(value: s, child: Text(s.replaceAll('_', ' ').toLowerCase())),
              ],
              onChanged: (v) => setState(() => _status = v),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String?>(
              initialValue: _cityId,
              decoration: const InputDecoration(labelText: 'City'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All')),
                for (final c in cities) DropdownMenuItem(value: c['id'] as String, child: Text(c['name'] as String)),
              ],
              onChanged: (v) => setState(() => _cityId = v),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 220,
            child: TextField(
              decoration: const InputDecoration(labelText: 'Driver / passenger'),
              onSubmitted: (v) => setState(() => _search = v.trim()),
            ),
          ),
        ],
        child: AdminLoader<List<Map<String, dynamic>>>(
          key: ValueKey('$_status/$_cityId/$_search/$_v'),
          load: () => repo.rides(status: _status, cityId: _cityId, search: _search),
          builder: (context, rows, _) => AdminTable(
            columns: const ['Date', 'Route', 'Passenger', 'Driver', 'Status', 'Fare', 'KAM GO', 'Driver gets'],
            rows: [
              for (final r in rows)
                DataRow(
                  onSelectChanged: (_) => _open(r),
                  cells: [
                    DataCell(Text(DateFormat('d MMM, h:mm a').format(DateTime.parse(r['created_at'] as String).toLocal()))),
                    DataCell(Text(r['route'] as String)),
                    DataCell(Text(r['passenger_name'] as String? ?? '')),
                    DataCell(Text(r['driver_name'] as String? ?? '')),
                    DataCell(StatusPill(r['status'] as String)),
                    DataCell(Text(formatFare(r['final_fare'] as num))),
                    DataCell(Text(r['commission_amount'] == null ? '—' : formatFare(r['commission_amount'] as num))),
                    DataCell(Text(r['driver_earning'] == null ? '—' : formatFare(r['driver_earning'] as num))),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
