import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/widgets/app_card.dart';
import '../admin_widgets.dart';

class AdminSettingsPage extends ConsumerStatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  ConsumerState<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends ConsumerState<AdminSettingsPage> {
  int _v = 0;

  Future<void> _edit(Map<String, dynamic> s) async {
    final key = s['key'] as String;
    final value = s['value'];
    Object? next;
    if (value is bool) {
      next = !value;
    } else {
      final text = await askText(context, key.replaceAll('_', ' '),
          initial: value is String ? value : jsonEncode(value), number: value is num);
      if (text == null) return;
      next = value is num ? num.tryParse(text) : text;
      if (next == null) return;
    }
    if (!mounted) return;
    final ok = await adminAction(context, () => ref.read(adminRepositoryProvider).saveSetting(key, next),
        success: 'Saved $key');
    if (ok) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(adminRepositoryProvider);
    return AdminPage(
      title: 'Settings',
      child: AdminLoader<List<Map<String, dynamic>>>(
        key: ValueKey(_v),
        load: repo.settings,
        builder: (context, rows, _) => AppCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              for (final s in rows)
                ListTile(
                  title: Text((s['key'] as String).replaceAll('_', ' '), style: AppText.body(15, weight: FontWeight.w600)),
                  subtitle: Text(s['description'] as String? ?? '', style: AppText.body(13, color: AppColors.muted)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      s['value'] is bool
                          ? Switch(value: s['value'] as bool, onChanged: (_) => _edit(s))
                          : Text('${s['value']}', style: AppText.display(16)),
                      if (s['value'] is! bool)
                        IconButton(onPressed: () => _edit(s), icon: const Icon(Icons.edit_rounded)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
