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
import '../../rides/domain/catalog.dart';
import '../../rides/presentation/ride_providers.dart';
import '../domain/driver_models.dart';
import 'driver_providers.dart';

/// Driver registration: CNIC, city, vehicle model (the ride type follows from it), AC, documents.
class DriverOnboardingScreen extends ConsumerStatefulWidget {
  const DriverOnboardingScreen({super.key});

  @override
  ConsumerState<DriverOnboardingScreen> createState() => _DriverOnboardingScreenState();
}

class _DriverOnboardingScreenState extends ConsumerState<DriverOnboardingScreen> {
  final _cnic = TextEditingController();
  final _color = TextEditingController();
  final _plate = TextEditingController();
  final _year = TextEditingController();
  VehicleModel? _model;
  bool _ac = false;
  int _seats = 4;
  String? _cityId;
  final Set<DriverDocType> _uploaded = {};
  DriverDocType? _uploading;
  bool _saving = false;
  bool _prefilled = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_cnic, _color, _plate, _year]) {
      c.dispose();
    }
    super.dispose();
  }

  void _prefill(DriverDashboard d, Catalog? catalog) {
    if (_prefilled) return;
    _prefilled = true;
    _cnic.text = d.cnic ?? '';
    _color.text = d.vehicleColor ?? '';
    _plate.text = d.vehiclePlate ?? '';
    _year.text = d.vehicleYear?.toString() ?? '';
    _seats = d.vehicleSeats ?? 4;
    _cityId = d.cityId;
    _ac = d.vehicleAc;
    for (final m in catalog?.vehicleModels ?? const <VehicleModel>[]) {
      if (m.matches(d.vehicleMake, d.vehicleModel)) _model = m;
    }
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
    final catalog = ref.read(catalogProvider).valueOrNull;
    if (_cityId == null) return setState(() => _error = 'Choose your city.');
    if (_model == null) return setState(() => _error = 'Choose your vehicle model from the list.');
    final missing = DriverDocType.values.where((t) => !_uploaded.contains(t)).map((t) => t.label);
    if (missing.isNotEmpty) return setState(() => _error = 'Please upload: ${missing.join(', ')}.');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(driverRepositoryProvider).saveApplication(DriverApplication(
            cnic: _cnic.text,
            cityId: _cityId!,
            make: _model!.make,
            model: _model!.model,
            color: _color.text,
            plate: _plate.text,
            seats: _seats,
            year: int.tryParse(_year.text),
            acAvailable: _ac && (catalog?.category(_model!.category)?.isCar ?? false),
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
    if (dash != null) _prefill(dash, catalog);
    final locked = dash != null && dash.status != DriverStatus.pending && dash.status != DriverStatus.rejected;

    InputDecoration dec(String hint) => InputDecoration(hintText: hint);

    // All active models, grouped by ride type in the admin's display order.
    final models = [...?catalog?.vehicleModels];
    int order(String code) => catalog?.category(code)?.sortOrder ?? 99;
    models.sort((a, b) {
      final c = order(a.category).compareTo(order(b.category));
      return c != 0 ? c : a.title.compareTo(b.title);
    });
    final category = _model == null ? null : catalog?.category(_model!.category);

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
            const FieldLabel('Your city (you get requests from this city)'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in catalog?.cities ?? const <City>[])
                  _Chip(
                    label: c.name,
                    selected: _cityId == c.id,
                    onTap: locked ? null : () => setState(() => _cityId = c.id),
                  ),
              ],
            ),
            const _Section('2. Your vehicle'),
            const FieldLabel('Vehicle model'),
            DropdownButtonFormField<VehicleModel>(
              initialValue: _model,
              isExpanded: true,
              decoration: dec('Choose your vehicle'),
              items: [
                for (final m in models)
                  DropdownMenuItem(
                    value: m,
                    child: Text('${m.title}  ·  ${catalog?.category(m.category)?.name ?? m.category}',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: locked
                  ? null
                  : (m) => setState(() {
                        _model = m;
                        final c = m == null ? null : catalog?.category(m.category);
                        if (c != null) _seats = c.maxPassengers;
                        if (c != null && !c.isCar) _ac = false;
                      }),
            ),
            if (category != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.green),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('You will get ${category.name} rides (set automatically from your model).',
                      style: AppText.body(13.5, weight: FontWeight.w600, color: AppColors.green)),
                ),
              ]),
            ],
            if (category?.isCar == true)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('AC available', style: AppText.body(15, weight: FontWeight.w600)),
                value: _ac,
                activeThumbColor: AppColors.green,
                onChanged: locked ? null : (v) => setState(() => _ac = v),
              ),
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
            ]),            if (!locked) ...[
              const _Section('3. Documents'),
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
