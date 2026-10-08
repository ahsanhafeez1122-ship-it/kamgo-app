import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/services/map_provider.dart';
import '../../../core/services/place_search_service.dart';
import '../../../core/services/routing_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/buttons.dart';
import '../../rides/domain/catalog.dart';
import '../../rides/domain/map_pick.dart';
import '../../rides/domain/ride_models.dart';
import '../../rides/presentation/ride_flow_providers.dart';

/// Full-screen map: drag it so the pin sits on the place, then confirm.
/// Returns the chosen [MapPick], or null if the passenger backs out.
Future<MapPick?> pickOnMap(
  BuildContext context, {
  required String title,
  required Catalog catalog,
  MapPick? initial,
  MapPick? other,
  bool requireService = false,
  bool startAtMyLocation = false,
}) {
  return Navigator.of(context).push<MapPick>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => MapPickScreen(
        title: title,
        catalog: catalog,
        initial: initial,
        other: other,
        requireService: requireService,
        startAtMyLocation: startAtMyLocation,
      ),
    ),
  );
}

class MapPickScreen extends ConsumerStatefulWidget {
  const MapPickScreen({
    super.key,
    required this.title,
    required this.catalog,
    this.initial,
    this.other,
    this.requireService = false,
    this.startAtMyLocation = false,
  });

  final String title;
  final Catalog catalog;
  final MapPick? initial;

  /// The other end of the trip: the pin may not be put on top of it.
  final MapPick? other;

  /// Pickup: the pin must be inside the service radius of a city. A destination can be anywhere
  /// (city-to-city rides).
  final bool requireService;

  /// Open on the passenger's current position (inDrive style pickup) when there is no earlier pick.
  final bool startAtMyLocation;

  @override
  ConsumerState<MapPickScreen> createState() => _MapPickScreenState();
}

class _MapPickScreenState extends ConsumerState<MapPickScreen> {
  final _controller = MapController();
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  late LatLng _center = _startCenter();
  bool _locating = false;
  bool _searching = false;
  /// The address text the passenger typed or picked; sent to the driver with the pin.
  String? _label;

  /// The name of the spot under the pin, looked up from the map after the pin stops moving.
  String? _pinName;
  bool _nameLoading = false;
  Timer? _nameTimer;

  void _scheduleNameLookup() {
    _nameTimer?.cancel();
    setState(() {
      _pinName = null;
      _nameLoading = true;
    });
    // Wait for the pin to rest (the free service allows about one request per second).
    _nameTimer = Timer(const Duration(milliseconds: 900), _lookUpName);
  }

  Future<void> _lookUpName() async {
    final at = _center;
    if (!_inArea) {
      if (mounted) setState(() => _nameLoading = false);
      return;
    }
    // KAM GO's own saved / learned places come first: they know the mohallas the maps do not.
    String? saved;
    var best = 0.15; // km
    for (final p in ref.read(placesProvider).valueOrNull ?? const <PlaceSuggestion>[]) {
      final d = haversineKm(at, LatLng(p.lat, p.lng));
      if (d < best) {
        best = d;
        saved = p.title;
      }
    }
    final name = saved ?? await ref.read(placeSearchProvider).reverse(at.latitude, at.longitude);
    if (!mounted || at != _center) return; // the pin moved again meanwhile
    setState(() {
      _pinName = name;
      _nameLoading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    ref.read(placesProvider.future).ignore(); // warm the local places list
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleNameLookup();
      if (widget.initial == null && widget.startAtMyLocation) _useMyLocation();
    });
  }
  List<PlaceSuggestion> _suggestions = const [];

  @override
  void dispose() {
    _nameTimer?.cancel();
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// The service area (all towns, with a margin) biases the search.
  ({double minLat, double minLng, double maxLat, double maxLng}) get _box {
    final cs = widget.catalog.cities.where((c) => c.lat != null && c.lng != null).toList();
    if (cs.isEmpty) return (minLat: 30.2, minLng: 72.0, maxLat: 31.3, maxLng: 73.0);
    var minLat = cs.first.lat!, maxLat = minLat, minLng = cs.first.lng!, maxLng = minLng;
    for (final c in cs) {
      minLat = c.lat! < minLat ? c.lat! : minLat;
      maxLat = c.lat! > maxLat ? c.lat! : maxLat;
      minLng = c.lng! < minLng ? c.lng! : minLng;
      maxLng = c.lng! > maxLng ? c.lng! : maxLng;
    }
    const pad = 0.4; // about 40 km
    return (minLat: minLat - pad, minLng: minLng - pad, maxLat: maxLat + pad, maxLng: maxLng + pad);
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.length < 2) {
      setState(() {
        _suggestions = const [];
        _searching = false;
      });
      return;
    }
    // Our own places answer instantly; the online search follows after a pause
    // in typing (the free geocoder allows about one request per second).
    setState(() {
      _suggestions = _localMatches(q);
      _searching = true;
    });
    _debounce = Timer(const Duration(milliseconds: 600), () => _runSearch(q));
  }

  /// KAM GO's villages, stops and landmarks that match, best matches first.
  List<PlaceSuggestion> _localMatches(String q) {
    final needle = q.toLowerCase();
    final all = ref.read(placesProvider).valueOrNull ?? const <PlaceSuggestion>[];
    final hits = [
      for (final p in all)
        if (p.title.toLowerCase().contains(needle)) p,
    ]..sort((a, b) {
        final sa = a.title.toLowerCase().startsWith(needle) ? 0 : 1;
        final sb = b.title.toLowerCase().startsWith(needle) ? 0 : 1;
        return sa != sb ? sa - sb : a.title.compareTo(b.title);
      });
    return [
      for (final p in hits.take(6))
        PlaceSuggestion(
          title: p.title,
          subtitle: [
            p.subtitle,
            if (widget.catalog.nearestCity(p.lat, p.lng) case final n?) 'near ${n.city.name}',
          ].join(' · '),
          lat: p.lat,
          lng: p.lng,
          saved: true,
        ),
    ];
  }

  Future<void> _runSearch(String q) async {
    List<PlaceSuggestion> found = const [];
    try {
      final b = _box;
      final raw = await ref
          .read(placeSearchProvider)
          .search(q, minLat: b.minLat, minLng: b.minLng, maxLat: b.maxLat, maxLng: b.maxLng);
      // Only places we can actually serve.
      found = raw.where((s) {
        final n = widget.catalog.nearestCity(s.lat, s.lng);
        return n != null && (!widget.requireService || n.km <= n.city.serviceRadiusKm);
      }).toList();
    } catch (_) {
      // Offline or the search service is busy: the map still works by hand.
    }
    if (!mounted || _searchCtrl.text.trim() != q) return;
    final local = _localMatches(q);
    final taken = {for (final p in local) p.title.toLowerCase()};
    setState(() {
      _suggestions = [...local, ...found.where((s) => !taken.contains(s.title.toLowerCase()))];
      _searching = false;
    });
  }

  void _pickSuggestion(PlaceSuggestion s) {
    _searchFocus.unfocus();
    _searchCtrl.text = s.title;
    setState(() {
      _suggestions = const [];
      _label = s.title;
    });
    _goTo(LatLng(s.lat, s.lng), zoom: 16);
  }

  LatLng _startCenter() {
    final i = widget.initial;
    if (i != null) return LatLng(i.point.lat, i.point.lng);
    final c = widget.catalog.cities.where((c) => c.lat != null && c.lng != null).firstOrNull;
    return c == null ? const LatLng(30.75, 72.5) : LatLng(c.lat!, c.lng!);
  }

  ({City city, double km})? get _nearest => widget.catalog.nearestCity(_center.latitude, _center.longitude);

  bool get _inArea {
    if (!widget.requireService) return _nearest != null;
    final n = _nearest;
    return n != null && n.km <= n.city.serviceRadiusKm;
  }

  /// The pin is on top of the other end of the trip (the map opens on it, so this is easy to do by accident).
  bool get _onOtherEnd =>
      widget.other != null && pinsOverlap(GeoPoint(_center.latitude, _center.longitude), widget.other!.point);

  void _goTo(LatLng p, {double zoom = 14}) {
    _controller.move(p, zoom);
    setState(() => _center = p);
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    final here = await ref.read(locationServiceProvider).current();
    if (!mounted) return;
    setState(() => _locating = false);
    if (here == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not get your location. Allow location access, or move the map by hand.'),
      ));
      return;
    }
    _goTo(LatLng(here.lat, here.lng), zoom: 16);
  }

  /// Not on the map? Keep what the passenger typed as the address. The pin goes to a
  /// saved place or a town named in it (so "ravi town Kamalia" opens Kamalia); the
  /// passenger then drags it onto the exact spot.
  void _useTypedAddress() {
    final text = _searchCtrl.text.trim();
    if (text.isEmpty) return;
    _searchFocus.unfocus();

    LatLng? target;
    String? where;
    final saved = _localMatches(text);
    if (saved.isNotEmpty) {
      target = LatLng(saved.first.lat, saved.first.lng);
      where = saved.first.title;
    } else if (_townNamedIn(text) case final c?) {
      target = LatLng(c.lat!, c.lng!);
      where = c.name;
    }

    setState(() {
      _label = text;
      _suggestions = const [];
    });
    if (target != null) _goTo(target, zoom: 15);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(where != null
          ? 'Pin moved to $where. Drag the map so the green pin is on your exact spot, then confirm.'
          : 'Address saved. Move the map so the green pin is on the spot, then confirm.'),
    ));
  }

  /// A town whose name appears in the text, ignoring spaces, case and typos in the tail
  /// ("tobatekh singh" still finds Toba Tek Singh through "toba").
  City? _townNamedIn(String text) {
    String squash(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    final t = squash(text);
    for (final c in widget.catalog.cities) {
      if (c.lat == null || c.lng == null) continue;
      final first = squash(c.name.split(' ').first);
      if (t.contains(squash(c.name)) || (first.length >= 4 && t.contains(first))) return c;
    }
    return null;
  }
  void _confirm() {
    final n = _nearest;
    if (n == null || !_inArea || _onOtherEnd) return;
    Navigator.of(context).pop(MapPick(
      point: GeoPoint(_center.latitude, _center.longitude),
      nearestName: n.city.name,
      // What they typed or chose; else the name OpenStreetMap gives this spot.
      label: _label ?? _pinName,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final nearest = _nearest;
    final towns = widget.catalog.cities.where((c) => c.lat != null && c.lng != null).toList();

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: widget.initial == null ? 14 : 16,
                minZoom: 8,
                maxZoom: 18,
                interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                onPositionChanged: (camera, _) {
                  final c = camera.center;
                  if (c.latitude != _center.latitude || c.longitude != _center.longitude) {
                    setState(() => _center = c);
                    _scheduleNameLookup();
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: const OsmMapProvider().tileUrl,
                  userAgentPackageName: 'pk.kamgo.kamgo_app',
                  maxNativeZoom: 18,
                ),
                const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
              ],
            ),
          ),
          // The pin: its tip sits exactly on the map centre.
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 44),
                child: Icon(Icons.location_on_rounded, size: 48, color: AppColors.green),
              ),
            ),
          ),
          Positioned(
            top: 10,
            left: 12,
            right: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  elevation: 3,
                  borderRadius: BorderRadius.circular(14),
                  color: AppColors.white,
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    textInputAction: TextInputAction.search,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search a place, e.g. Bus Stand Kamalia',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : _searchCtrl.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    _onSearchChanged('');
                                  },
                                ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_searchCtrl.text.trim().length >= 2)
                  Material(
                    elevation: 3,
                    borderRadius: BorderRadius.circular(14),
                    color: AppColors.white,
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          for (final s in _suggestions) ...[
                            ListTile(
                              dense: true,
                              leading: Icon(s.saved ? Icons.push_pin_rounded : Icons.place_outlined, color: AppColors.green),
                              title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: AppText.body(14.5, weight: FontWeight.w600)),
                              subtitle: s.subtitle.isEmpty
                                  ? null
                                  : Text(s.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: AppText.body(12.5, color: AppColors.muted)),
                              onTap: () => _pickSuggestion(s),
                            ),
                            const Divider(height: 1, color: AppColors.borderSoft),
                          ],
                          // Always there: if the place is not on the map, the passenger writes it.
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.edit_location_alt_rounded, color: AppColors.navy),
                            title: Text('Use "${_searchCtrl.text.trim()}" as my address',
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: AppText.body(14.5, weight: FontWeight.w600)),
                            subtitle: Text(
                              _searching
                                  ? 'Searching…'
                                  : 'Not on the map? Keep this address for the driver, then place the pin by hand.',
                              style: AppText.body(12.5, color: AppColors.muted),
                            ),
                            onTap: _useTypedAddress,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: towns.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final t = towns[i];
                        return ActionChip(
                          backgroundColor: AppColors.white,
                          side: const BorderSide(color: AppColors.border),
                          label: Text(t.name, style: AppText.body(13.5, weight: FontWeight.w600)),
                          onPressed: () => _goTo(LatLng(t.lat!, t.lng!), zoom: 13),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            right: 16,
            bottom: 170,
            child: FloatingActionButton.small(
              heroTag: 'my-location',
              backgroundColor: AppColors.white,
              foregroundColor: AppColors.navy,
              onPressed: _locating ? null : _useMyLocation,
              child: _locating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location_rounded),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.paddingOf(context).bottom),
              decoration: const BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                boxShadow: [BoxShadow(color: Color(0x1F000000), blurRadius: 16)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    // Exactly what will be saved: what you typed or chose, else the name of this spot.
                    nearest == null
                        ? 'Move the map to choose a place'
                        : _label ?? _pinName ?? (_nameLoading ? 'Finding the name of this spot…' : 'Selected location'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.display(16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    !_inArea
                        ? 'Service is not available here yet. Move the pin closer to one of our cities.'
                        : _onOtherEnd
                            ? 'This is the same place as the other end of your trip. Drag the map to a different spot.'
                            : 'Drag the map so the green pin is exactly on the spot.',
                    style: AppText.body(13, color: _inArea && !_onOtherEnd ? AppColors.muted : AppColors.danger),
                  ),
                  if (_label != null) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Icons.edit_location_alt_rounded, size: 18, color: AppColors.green),
                      const SizedBox(width: 6),
                      Expanded(child: Text('Address: $_label', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(13.5, weight: FontWeight.w600))),
                      IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => setState(() => _label = null)),
                    ]),
                  ],
                  const SizedBox(height: 14),
                  PrimaryButton(label: 'Confirm location', onPressed: _inArea && !_onOtherEnd ? _confirm : null),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
