import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/errors.dart';
import '../../../core/widgets/app_card.dart';
import '../data/admin_repository.dart';

final adminRepositoryProvider = Provider((ref) => AdminRepository(ref.watch(supabaseClientProvider)));

/// Page scaffold: title, optional actions, scrollable body.
class AdminPage extends StatelessWidget {
  const AdminPage({super.key, required this.title, required this.child, this.actions = const []});
  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: AppText.display(24))),
              ...actions,
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      );
}

/// Loads [load] once and renders [builder]; shows spinner / error with retry.
/// Give it a key that changes with its filters to reload.
class AdminLoader<T> extends StatefulWidget {
  const AdminLoader({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, VoidCallback reload) builder;

  @override
  State<AdminLoader<T>> createState() => _AdminLoaderState<T>();
}

class _AdminLoaderState<T> extends State<AdminLoader<T>> {
  late Future<T> _f = widget.load();

  void _reload() => setState(() => _f = widget.load());

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _f,
        builder: (context, s) {
          if (s.hasError) {
            return AppCard(
              child: Column(
                children: [
                  Text(friendlyError(s.error!), style: AppText.body(14, color: AppColors.danger)),
                  TextButton(onPressed: _reload, child: const Text('Retry')),
                ],
              ),
            );
          }
          if (!s.hasData) {
            return const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: AppColors.green)),
            );
          }
          return widget.builder(context, s.data as T, _reload);
        },
      );
}

/// Runs an admin action with a snackbar for errors / success.
Future<bool> adminAction(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (context.mounted && success != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
    }
    return true;
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    return false;
  }
}

Future<String?> askText(BuildContext context, String title, {String hint = '', String initial = '', bool number = false}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: c,
          autofocus: true,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(hintText: hint),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.green),
          onPressed: () => Navigator.pop(context, c.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = text.toUpperCase();
    final (bg, fg) = switch (t) {
      'APPROVED' || 'ACTIVE' || 'COMPLETED' || 'RESOLVED' => (AppColors.greenSoft, AppColors.green),
      'PENDING' || 'OPEN' || 'IN_REVIEW' || 'CONFIRMED' || 'RIDE_STARTED' || 'DRIVER_ARRIVING' =>
        (AppColors.amberSoft, AppColors.amber),
      'REJECTED' || 'SUSPENDED' || 'CANCELLED' || 'NO_SHOW' || 'DISMISSED' =>
        (const Color(0xFFFEE2E2), AppColors.danger),
      _ => (AppColors.background, AppColors.mutedDark),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(t.replaceAll('_', ' ').toLowerCase(), style: AppText.body(12, weight: FontWeight.w600, color: fg)),
    );
  }
}

/// Horizontally scrollable DataTable inside a card.
class AdminTable extends StatelessWidget {
  const AdminTable({super.key, required this.columns, required this.rows});
  final List<String> columns;
  final List<DataRow> rows;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: rows.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text('Nothing here yet', style: AppText.body(14, color: AppColors.muted))),
              )
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingTextStyle: AppText.body(13, weight: FontWeight.w600, color: AppColors.mutedDark),
                  dataTextStyle: AppText.body(13.5),
                  columns: [for (final c in columns) DataColumn(label: Text(c))],
                  rows: rows,
                ),
              ),
      );
}
