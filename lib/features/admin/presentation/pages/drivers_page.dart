import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/utils/format.dart';
import '../admin_widgets.dart';

class AdminDriversPage extends ConsumerStatefulWidget {
  const AdminDriversPage({super.key});

  @override
  ConsumerState<AdminDriversPage> createState() => _AdminDriversPageState();
}

class _AdminDriversPageState extends ConsumerState<AdminDriversPage> {
  String? _status = 'PENDING';
  int _version = 0;

  void _reload() => setState(() => _version++);

  Future<void> _setStatus(Map<String, dynamic> d, String status) async {
    String? reason;
    if (status == 'REJECTED' || status == 'SUSPENDED') {
      reason = await askText(context, status == 'REJECTED' ? 'Reason for rejection' : 'Reason for suspension',
          hint: 'Shown to the driver');
      if (reason == null || reason.isEmpty) return;
    }
    if (!mounted) return;
    final ok = await adminAction(
      context,
      () => ref.read(adminRepositoryProvider).setDriverStatus(d['driver_id'] as String, status, reason: reason),
      success: '${d['full_name']} → ${status.toLowerCase()}',
    );
    if (ok) _reload();
  }

  Future<void> _changeCity(Map<String, dynamic> d) async {
    final repo = ref.read(adminRepositoryProvider);
    final cities = [for (final c in await repo.cities()) if (c['is_active'] == true) c];
    if (!mounted) return;
    final id = await _choose(context, 'City for ${d['full_name']}', {for (final c in cities) c['id'] as String: c['name'] as String}, d['city_id'] as String?);
    if (id == null || !mounted) return;
    final ok = await adminAction(context, () => repo.setDriverCity(d['driver_id'] as String, id), success: 'City changed');
    if (ok) _reload();
  }

  Future<void> _changeCategory(Map<String, dynamic> d) async {
    final repo = ref.read(adminRepositoryProvider);
    final cats = [for (final c in await repo.categories()) if (c['is_active'] == true) c];
    if (!mounted) return;
    final code = await _choose(context, 'Ride type for ${d['full_name']}', {for (final c in cats) c['code'] as String: c['name'] as String}, d['category'] as String?);
    if (code == null || !mounted) return;
    final ok = await adminAction(context, () => repo.setDriverCategory(d['driver_id'] as String, code), success: 'Ride type changed');
    if (ok) _reload();
  }

  Future<void> _payment(Map<String, dynamic> d) async {
    final v = await askText(context, 'Cash collected from ${d['full_name']}',
        hint: 'Amount in Rs.', number: true, initial: '${(d['commission_due'] as num).round()}');
    final amount = double.tryParse(v ?? '');
    if (amount == null || !mounted) return;
    final ok = await adminAction(context, () => ref.read(adminRepositoryProvider).recordPayment(d['driver_id'] as String, amount),
        success: 'Payment recorded');
    if (ok) _reload();
  }

  Future<void> _documents(Map<String, dynamic> d) async {
    final repo = ref.read(adminRepositoryProvider);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Documents — ${d['full_name']}'),
        content: SizedBox(
          width: 720,
          child: AdminLoader<List<Map<String, dynamic>>>(
            load: () => repo.documents(d['driver_id'] as String),
            builder: (context, docs, _) => docs.isEmpty
                ? const Text('No documents uploaded yet.')
                : SingleChildScrollView(
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final doc in docs)
                          SizedBox(
                            width: 220,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(
                                    child: Text((doc['doc_type'] as String).replaceAll('_', ' '),
                                        style: AppText.body(13, weight: FontWeight.w600)),
                                  ),
                                  StatusPill(doc['status'] as String),
                                ]),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: doc['url'] == null
                                      ? Container(height: 140, color: AppColors.background)
                                      : Image.network(doc['url'] as String, height: 140, width: 220, fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              Container(height: 140, color: AppColors.background)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(adminRepositoryProvider);
    return AdminPage(
      title: 'Drivers',
      actions: [
        for (final s in const [null, 'PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED'])
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: ChoiceChip(
              label: Text(s == null ? 'All' : s[0] + s.substring(1).toLowerCase()),
              selected: _status == s,
              onSelected: (_) => setState(() => _status = s),
            ),
          ),
      ],
      child: AdminLoader<List<Map<String, dynamic>>>(
        key: ValueKey('$_status/$_version'),
        load: () => repo.drivers(status: _status),
        builder: (context, rows, _) => AdminTable(
          columns: const ['Driver', 'Phone', 'Status', 'City', 'Ride type', 'Vehicle', 'CNIC', 'Rating', 'Rides', 'Commission due', 'Docs', 'Actions'],
          rows: [
            for (final d in rows)
              DataRow(cells: [
                DataCell(Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d['full_name'] as String? ?? '—', style: AppText.body(14, weight: FontWeight.w600)),
                    if (d['account_status'] == 'SUSPENDED') const StatusPill('SUSPENDED'),
                  ],
                )),
                DataCell(Text(d['phone'] as String? ?? '')),
                DataCell(Row(children: [
                  StatusPill(d['status'] as String),
                  if (d['is_online'] == true) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.circle, size: 10, color: AppColors.green),
                  ],
                ])),
                DataCell(Text(d['city_name'] as String? ?? '—')),
                DataCell(Text('${d['category_name'] ?? '—'}${d['ac_available'] == true ? ' · AC' : ''}')),
                DataCell(Text('${d['vehicle'] ?? '—'}${d['plate'] == null ? '' : '\n${d['plate']}'}')),
                DataCell(Text(d['cnic'] as String? ?? '—')),
                DataCell(Text((d['rating'] as num?)?.toStringAsFixed(1) ?? '—')),
                DataCell(Text('${d['total_rides']}')),
                DataCell(Text(formatFare(d['commission_due'] as num))),
                DataCell(TextButton(onPressed: () => _documents(d), child: Text('${d['document_count']} view'))),
                DataCell(Wrap(spacing: 4, children: [
                  TextButton(onPressed: () => _changeCity(d), child: const Text('City')),
                  TextButton(onPressed: () => _changeCategory(d), child: const Text('Type')),
                  if (d['status'] != 'APPROVED')
                    TextButton(onPressed: () => _setStatus(d, 'APPROVED'), child: const Text('Approve')),
                  if (d['status'] == 'PENDING')
                    TextButton(onPressed: () => _setStatus(d, 'REJECTED'), child: const Text('Reject')),
                  if (d['status'] == 'APPROVED')
                    TextButton(
                      onPressed: () => _setStatus(d, 'SUSPENDED'),
                      child: const Text('Suspend', style: TextStyle(color: AppColors.danger)),
                    ),
                  if ((d['commission_due'] as num) > 0)
                    TextButton(onPressed: () => _payment(d), child: const Text('Record payment')),
                ])),
              ]),
          ],
        ),
      ),
    );
  }
}

Future<String?> _choose(BuildContext context, String title, Map<String, String> options, String? current) =>
    showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          for (final e in options.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, e.key),
              child: Text(e.value + (e.key == current ? '   (current)' : '')),
            ),
        ],
      ),
    );