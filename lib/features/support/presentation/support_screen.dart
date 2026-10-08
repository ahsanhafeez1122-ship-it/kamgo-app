import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/services/supabase_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/errors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/buttons.dart';
import '../../rides/domain/catalog.dart';
import '../../rides/presentation/ride_providers.dart';
import '../data/support_repository.dart';

final supportRepositoryProvider = Provider((ref) => SupportRepository(ref.watch(supabaseClientProvider)));

const _faq = [
  ('How does KAM GO work?',
      'You choose where you are going and offer a fare. Drivers of the ride type you chose accept it or send a counter offer. You pick the driver you like.'),
  ('How do I pay?', 'Pay the driver in cash at the end of the ride. The fare is the one you agreed in the app.'),
  ('Why was my fare not accepted?',
      'Every route has a fair range so nobody is under- or over-charged. If no one accepts, try raising your offer a little.'),
  ('How much does KAM GO take?',
      'KAM GO keeps a small commission (10%) only on completed rides. Requests and offers are always free.'),
  ('Is my trip safe?',
      'Drivers are checked by KAM GO before they can go online. You can share your trip with family and report any problem from the ride screen.'),
  ('How do I become a driver?',
      'Sign up and choose "I drive", then add your CNIC, vehicle, routes and documents. KAM GO reviews them before approval.'),
];

class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key, this.rideId});
  final String? rideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(catalogProvider).valueOrNull?.settings;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('profile.help'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: _ContactCard(
                  icon: Icons.chat_rounded,
                  label: 'WhatsApp',
                  onTap: () => launchUrl(
                      Uri.parse('https://wa.me/${s?.supportWhatsapp ?? defaultSupportWhatsapp}'),
                      mode: LaunchMode.externalApplication),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ContactCard(
                  icon: Icons.call_rounded,
                  label: 'Call KAM GO',
                  onTap: () => launchUrl(Uri.parse('tel:${s?.supportPhone ?? defaultSupportPhone}')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text('Report a problem', style: AppText.display(16)),
          const SizedBox(height: 10),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final t in ComplaintType.values)
                  ListTile(
                    leading: Icon(
                      switch (t) {
                        ComplaintType.driver => Icons.directions_car_rounded,
                        ComplaintType.passenger => Icons.person_rounded,
                        ComplaintType.ride => Icons.route_rounded,
                        ComplaintType.other => Icons.help_outline_rounded,
                      },
                      color: AppColors.navy,
                    ),
                    title: Text(t.label, style: AppText.body(15, weight: FontWeight.w600)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                    onTap: () => _report(context, ref, t),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text('Questions', style: AppText.display(16)),
          const SizedBox(height: 10),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final (q, a) in _faq)
                  ExpansionTile(
                    shape: const Border(),
                    title: Text(q, style: AppText.body(15, weight: FontWeight.w600)),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    children: [Text(a, style: AppText.body(14, color: AppColors.mutedDark, height: 1.45))],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _report(BuildContext context, WidgetRef ref, ComplaintType type) async {
    final text = TextEditingController();
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: _ReportForm(type: type, rideId: rideId, controller: text, repo: ref.read(supportRepositoryProvider)),
      ),
    );
    text.dispose();
    if (sent == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thank you. KAM GO will look into it and contact you.')),
      );
    }
  }
}

class _ReportForm extends StatefulWidget {
  const _ReportForm({required this.type, required this.rideId, required this.controller, required this.repo});
  final ComplaintType type;
  final String? rideId;
  final TextEditingController controller;
  final SupportRepository repo;

  @override
  State<_ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends State<_ReportForm> {
  bool _sending = false;
  String? _error;

  Future<void> _send() async {
    if (widget.controller.text.trim().length < 5) {
      setState(() => _error = 'Please describe what happened.');
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.repo.submitComplaint(widget.type, widget.controller.text.trim(), rideId: widget.rideId);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = friendlyError(e);
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.type.label, style: AppText.display(18)),
          if (widget.rideId != null)
            Text('About your current ride', style: AppText.body(13, color: AppColors.muted)),
          const SizedBox(height: 14),
          TextField(
            controller: widget.controller,
            autofocus: true,
            maxLines: 5,
            maxLength: 2000,
            decoration: const InputDecoration(hintText: 'Tell us what happened'),
          ),
          if (_error != null) Text(_error!, style: AppText.body(13, color: AppColors.danger)),
          const SizedBox(height: 10),
          PrimaryButton(label: 'Send report', loading: _sending, onPressed: _send),
        ],
      );
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        child: Column(
          children: [
            Icon(icon, color: AppColors.green, size: 30),
            const SizedBox(height: 8),
            Text(label, style: AppText.body(14.5, weight: FontWeight.w600)),
          ],
        ),
      );
}
