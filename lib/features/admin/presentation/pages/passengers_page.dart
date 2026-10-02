import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../admin_widgets.dart';

class AdminPassengersPage extends ConsumerStatefulWidget {
  const AdminPassengersPage({super.key});

  @override
  ConsumerState<AdminPassengersPage> createState() => _AdminPassengersPageState();
}

class _AdminPassengersPageState extends ConsumerState<AdminPassengersPage> {
  String _search = '';
  int _version = 0;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(adminRepositoryProvider);
    return AdminPage(
      title: 'Passengers',
      actions: [
        SizedBox(
          width: 260,
          child: TextField(
            decoration: const InputDecoration(hintText: 'Search name or phone', prefixIcon: Icon(Icons.search_rounded)),
            onSubmitted: (v) => setState(() => _search = v.trim()),
          ),
        ),
      ],
      child: AdminLoader<List<Map<String, dynamic>>>(
        key: ValueKey('$_search/$_version'),
        load: () => repo.passengers(search: _search),
        builder: (context, rows, _) => AdminTable(
          columns: const ['Name', 'Phone', 'Status', 'Rides', 'Rating', 'Joined', ''],
          rows: [
            for (final p in rows)
              DataRow(cells: [
                DataCell(Text(p['full_name'] as String? ?? '—')),
                DataCell(Text(p['phone'] as String? ?? '')),
                DataCell(StatusPill(p['account_status'] as String)),
                DataCell(Text('${p['total_rides']}')),
                DataCell(Text((p['rating'] as num?)?.toStringAsFixed(1) ?? '—')),
                DataCell(Text(DateFormat('d MMM y').format(DateTime.parse(p['created_at'] as String)))),
                DataCell(TextButton(
                  onPressed: () async {
                    final suspend = p['account_status'] == 'ACTIVE';
                    final ok = await adminAction(
                      context,
                      () => repo.setAccountStatus(p['user_id'] as String, suspend ? 'SUSPENDED' : 'ACTIVE'),
                      success: suspend ? 'Suspended' : 'Reactivated',
                    );
                    if (ok) setState(() => _version++);
                  },
                  child: Text(p['account_status'] == 'ACTIVE' ? 'Suspend' : 'Reactivate',
                      style: TextStyle(color: p['account_status'] == 'ACTIVE' ? AppColors.danger : AppColors.green)),
                )),
              ]),
          ],
        ),
      ),
    );
  }
}
