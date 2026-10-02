import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../admin_widgets.dart';

class AdminComplaintsPage extends ConsumerStatefulWidget {
  const AdminComplaintsPage({super.key});

  @override
  ConsumerState<AdminComplaintsPage> createState() => _AdminComplaintsPageState();
}

class _AdminComplaintsPageState extends ConsumerState<AdminComplaintsPage> {
  int _v = 0;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(adminRepositoryProvider);
    return AdminPage(
      title: 'Complaints',
      child: AdminLoader<List<Map<String, dynamic>>>(
        key: ValueKey(_v),
        load: repo.complaints,
        builder: (context, rows, _) => AdminTable(
          columns: const ['Date', 'From', 'Type', 'Description', 'Status', 'Note'],
          rows: [
            for (final c in rows)
              DataRow(cells: [
                DataCell(Text(DateFormat('d MMM, h:mm a').format(DateTime.parse(c['created_at'] as String).toLocal()))),
                DataCell(Text('${c['reporter']?['full_name'] ?? ''}\n+${c['reporter']?['phone'] ?? ''}')),
                DataCell(Text((c['complaint_type'] as String).toLowerCase())),
                DataCell(SizedBox(width: 280, child: Text(c['description'] as String, maxLines: 3, overflow: TextOverflow.ellipsis))),
                DataCell(DropdownButton<String>(
                  value: c['status'] as String,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final s in const ['OPEN', 'IN_REVIEW', 'RESOLVED', 'DISMISSED'])
                      DropdownMenuItem(value: s, child: StatusPill(s)),
                  ],
                  onChanged: (s) async {
                    if (s == null) return;
                    final ok = await adminAction(context,
                        () => repo.updateComplaint(c['id'] as String, s, note: c['admin_note'] as String?));
                    if (ok) setState(() => _v++);
                  },
                )),
                DataCell(TextButton(
                  onPressed: () async {
                    final note = await askText(context, 'Admin note', initial: c['admin_note'] as String? ?? '');
                    if (note == null || !context.mounted) return;
                    final ok = await adminAction(context,
                        () => repo.updateComplaint(c['id'] as String, c['status'] as String, note: note));
                    if (ok) setState(() => _v++);
                  },
                  child: Text((c['admin_note'] as String?)?.isNotEmpty == true ? c['admin_note'] as String : 'Add note'),
                )),
              ]),
          ],
        ),
      ),
    );
  }
}
