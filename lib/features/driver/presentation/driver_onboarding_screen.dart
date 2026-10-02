import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/buttons.dart';
import '../../auth/presentation/auth_layout.dart';
import '../../profile/domain/profile.dart';
import '../../rides/presentation/ride_providers.dart';
import '../domain/driver_models.dart';
import 'driver_providers.dart';

/// Driver registration: CNIC, city, vehicle, preferred routes, documents.
class DriverOnboardingScreen extends ConsumerStatefulWidget {
  const DriverOnboardingScreen({super.key});

  @override
  ConsumerState<DriverOnboardingScreen> createState() => _DriverOnboardingScreenState();
}

class _DriverOnboardingScreenState extends ConsumerState<DriverOnboardingScreen> {
  final _cnic = TextEditingController();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _color = TextEditingController();
  final _plate = TextEditingController();
  final _year = TextEditingController();
  String _type = 'CAR';
  int _seats = 4;
  String? _cityId;
  final Set<String> _routes = {};
  final Set<DriverDocType> _uploaded = {};
  DriverDocType? _uploading;
  bool _saving = false;
  bool _prefilled = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_cnic, _make, _model, _color, _plate, _year]) {
      c.dispose();
    }
    super.dispose();
  }

  void _prefill(DriverDashboard d) {
    if (_prefilled) return;
    _prefilled = true;
    _cnic.text = d.cnic ?? '';
    _make.text = d.vehicleMake ?? '';
    _model.text = d.vehicleModel ?? '';
    _color.text = d.vehicleColor ?? '';
    _plate.text = d.vehiclePlate ?? '';
    _year.text = d.vehicleYear?.toString() ?? '';
    _type = d.vehicleType ?? 'CAR';
    _seats = d.vehicleSeats ?? 4;
    _cityId = d.cityId;
    _routes.addAll(d.routeIds);
    for (final t in DriverDocType.values) {
      if (d.documentTypes.contains(t.code)) _uploaded.add(t);
    }
  }

  Future<void> _upload(DriverDocType t) async {
    final camera = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
    if (camera == null) return;
    setState(() => _uploading = t);
    try {
      final bytes = await pickCompressedPhoto(camera: camera);
      if (bytes == null) return;
      await ref.read(driverRepositoryProvider).uploadDocument(t, bytes);
      setState(() => _uploaded.add(t));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  Future<void> _submit() async {
    final missing = DriverDocType.values.where((t) => !_uploaded.contains(t)).map((t) => t.label);
    if (_cityId == null) return setState(() => _error = 'Choose your city.');
    if (_routes.isEmpty) return setState(() => _error = 'Choose at least one route you drive.');
    if (missing.isNotEmpty) return setState(() => _error = 'Please upload: ${missing.join(', ')}.');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(driverRepositoryProvider).saveApplication(DriverApplication(
            cnic: _cnic.text,
            cityId: _cityId!,
            vehicleType: _type,
            make: _make.text,
            model: _model.text,
            color: _color.text,
            plate: _plate.text,
            seats: _seats,
            year: int.tryParse(_year.text),
            routeIds: _routes.toList(),
          ));
      ref.invalidate(driverDashboardProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Submitted! KAM GO will review your application.')),
        );
        context.go(AppRoutes.driver);
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dash = ref.watch(driverDashboardProvider).valueOrNull;
    final catalog = ref.watch(catalogProvider).valueOrNull;
    if (dash != null) _prefill(dash);
    final locked = dash != null && dash.status != DriverStatus.pending && dash.status != DriverStatus.rejected;

    InputDecoration dec(String hint) => InputDecoration(hintText: hint);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        appBar: AppBar(title: const Text('Driver registration')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            const _Section('1. About you'),
            const FieldLabel('CNIC number'),
            TextField(
              controller: _cnic,
              enabled: !locked,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')), LengthLimitingTextInputFormatter(15)],
              decoration: dec('33100-1234567-1'),
            ),
            const SizedBox(height: 14),
            const FieldLabel('Your city (adda)'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in catalog?.cities ?? const [])
                  _Chip(label: c.name, selected: _cityId == c.id, onTap: locked ? null : () => setState(() => _cityId = c.id)),
              ],
            ),
            const _Section('2. Your vehicle'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in const ['CAR', 'RICKSHAW', 'VAN', 'MOTORCYCLE'])
                  _Chip(
                    label: t[0] + t.substring(1).toLowerCase(),
                    selected: _type == t,
                    onTap: locked ? null : () => setState(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _make, enabled: !locked, decoration: dec('Make (Suzuki)'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _model, enabled: !locked, decoration: dec('Model (Alto)'))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: _color, enabled: !locked, decoration: dec('Colour'))),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _year,
                  enabled: !locked,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                  decoration: dec('Year'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _plate,
                  enabled: !locked,
                  textCapitalization: TextCapitalization.characters,
                  decoration: dec('Number plate'),
                ),
              ),
              const SizedBox(width: 10),
              Text('Seats', style: AppText.body(14, color: AppColors.mutedDark)),
              IconButton(onPressed: locked || _seats <= 1 ? null : () => setState(() => _seats--), icon: const Icon(Icons.remove_rounded)),
              Text('$_seats', style: AppText.display(17)),
              IconButton(onPressed: locked || _seats >= 20 ? null : () => setState(() => _seats++), icon: const Icon(Icons.add_rounded)),
            ]),
            const _Section('3. Routes you drive'),
            if (catalog != null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in catalog.routes)
                    _Chip(
                      label: catalog.routeName(r),
                      selected: _routes.contains(r.id),
                      onTap: () => setState(() => _routes.contains(r.id) ? _routes.remove(r.id) : _routes.add(r.id)),
                    ),
                ],
              ),
            if (locked) ...[
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'Save routes',
                onPressed: () async {
                  try {
                    await ref.read(driverRepositoryProvider).setRoutes(_routes.toList());
                    ref.invalidate(driverDashboardProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Routes saved')));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
                    }
                  }
                },
              ),
            ],
            if (!locked) ...[
              const _Section('4. Documents'),
              Text('Clear photos, compressed automatically before upload. Only KAM GO can see them.',
                  style: AppText.body(13, color: AppColors.mutedDark)),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.3,
                children: [
                  for (final t in DriverDocType.values)
                    AppCard(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      radius: 16,
                      border: Border.all(color: _uploaded.contains(t) ? AppColors.green : AppColors.borderSoft),
                      onTap: _uploading == null ? () => _upload(t) : null,
                      child: Row(
                        children: [
                          _uploading == t
                              ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                              : Icon(
                                  _uploaded.contains(t) ? Icons.check_circle_rounded : Icons.add_a_photo_rounded,
                                  color: _uploaded.contains(t) ? AppColors.green : AppColors.navy,
                                ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(t.label, style: AppText.body(13.5, weight: FontWeight.w600))),
                        ],
                      ),
                    ),
                ],
              ),
              ErrorText(_error),
              const SizedBox(height: 22),
              PrimaryButton(label: 'Submit for review', loading: _saving, onPressed: _submit),
            ],
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 12),
        child: Text(title, style: AppText.display(17)),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: onTap == null ? null : (_) => onTap!(),
        showCheckmark: false,
        selectedColor: AppColors.green,
        backgroundColor: AppColors.white,
        side: const BorderSide(color: AppColors.border),
        shape: const StadiumBorder(),
        labelStyle: AppText.body(14, weight: FontWeight.w600, color: selected ? AppColors.white : AppColors.navy),
      );
}
