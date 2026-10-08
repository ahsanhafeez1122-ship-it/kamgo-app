import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/place_search_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../rides/domain/catalog.dart';
import '../../rides/domain/map_pick.dart';
import '../../rides/domain/ride_models.dart';
import '../../rides/presentation/ride_flow_providers.dart';
import 'map_pick_screen.dart';

/// Choose a place by writing it: no map, no pin. Saved places and the online search give the
/// coordinates, and the trip distance is worked out from them. Returns the chosen [MapPick].
Future<MapPick?> pickPlace(
  BuildContext context, {
  required String title,
  required Catalog catalog,
  Set<String>? allowedCityIds,
  bool allowMyLocation = false,
}) {
  return Navigator.of(context).push<MapPick>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PlacePickScreen(
        title: title,
        catalog: catalog,
        allowedCityIds: allowedCityIds,
        allowMyLocation: allowMyLocation,
      ),
    ),
  );
}

class PlacePickScreen extends ConsumerStatefulWidget {
  const PlacePickScreen({
    super.key,
    required this.title,
    required this.catalog,
    this.allowedCityIds,
    this.allowMyLocation = false,
  });

  final String title;
  final Catalog catalog;

  /// Only places inside the service radius of these cities are accepted (null = any city we serve).
  final Set<String>? allowedCityIds;
  final bool allowMyLocation;

  @override
  ConsumerState<PlacePickScreen> createState() => _PlacePickScreenState();
}

class _PlacePickScreenState extends ConsumerState<PlacePickScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<PlaceSuggestion> _suggestions = const [];
  bool _searching = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    ref.read(placesProvider.future).ignore();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  /// The cities this screen accepts.
  List<City> get _cities => [
        for (final c in widget.catalog.cities)
          if (c.lat != null && c.lng != null && (widget.allowedCityIds?.contains(c.id) ?? true)) c,
      ];

  /// Is the spot inside the service radius of an allowed city?
  bool _inScope(double lat, double lng) {
    final n = widget.catalog.nearestCity(lat, lng);
    if (n == null || n.km > n.city.serviceRadiusKm) return false;
    return widget.allowedCityIds?.contains(n.city.id) ?? true;
  }

  ({double minLat, double minLng, double maxLat, double maxLng}) get _box {
    final cs = _cities;
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

  void _onChanged(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.length < 2) {
      setState(() {
        _suggestions = const [];
        _searching = false;
      });
      return;
    }
    setState(() {
      _suggestions = _localMatches(q);
      _searching = true;
    });
    _debounce = Timer(const Duration(milliseconds: 600), () => _runSearch(q));
  }

  /// KAM GO's saved villages, stops and landmarks, best matches first.
  List<PlaceSuggestion> _localMatches(String q) {
    final needle = q.toLowerCase();
    final all = ref.read(placesProvider).valueOrNull ?? const <PlaceSuggestion>[];
    final hits = [
      for (final p in all)
        if (p.title.toLowerCase().contains(needle) && _inScope(p.lat, p.lng)) p,
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
          .search(_expanded(q), minLat: b.minLat, minLng: b.minLng, maxLat: b.maxLat, maxLng: b.maxLng);
      found = raw.where((s) => _inScope(s.lat, s.lng)).toList();
    } catch (_) {
      // Offline or busy: saved places and typing the address still work.
    }
    if (!mounted || _ctrl.text.trim() != q) return;
    final local = _localMatches(q);
    final taken = {for (final p in local) p.title.toLowerCase()};
    setState(() {
      _suggestions = [...local, ...found.where((s) => !taken.contains(s.title.toLowerCase()))];
      _searching = false;
    });
  }

  /// Short forms people write for a town: its initials ("tts" = Toba Tek Singh) and its first word.
  static List<String> _aliases(City c) {
    final words = c.name.toLowerCase().split(RegExp(r'[^a-z]+')).where((w) => w.isNotEmpty).toList();
    return [
      if (words.length >= 2) words.map((w) => w[0]).join(),
      if (words.first.length >= 4) words.first,
    ];
  }

  /// A town named in the text: full name, initials or first word ("ravi town kamalia",
  /// "model town tts", "bilal colony toba").
  City? _townNamedIn(String text) {
    String squash(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    final t = squash(text);
    final words = text.toLowerCase().split(RegExp(r'[^a-z]+')).toSet();
    for (final c in _cities) {
      if (t.contains(squash(c.name))) return c;
      for (final a in _aliases(c)) {
        if (a.length <= 3 ? words.contains(a) : t.contains(a)) return c;
      }
    }
    return null;
  }

  /// The text with a town's short form written out, so the online search understands it.
  String _expanded(String text) {
    var out = text;
    for (final c in _cities) {
      for (final a in _aliases(c)) {
        if (a.length <= 3) out = out.replaceAll(RegExp('\\b$a\\b', caseSensitive: false), c.name);
      }
    }
    return out;
  }

  /// "Near which place?": KAM GO's saved places in that town, so a mohalla that is on no map still
  /// gets a spot close to the truth (and the km follow). The first rides then learn the exact spot.
  Future<({double lat, double lng})?> _askNearby(City town, String typed) async {
    final all = ref.read(placesProvider).valueOrNull ?? const <PlaceSuggestion>[];
    final inTown = [
      for (final p in all)
        if (widget.catalog.nearestCity(p.lat, p.lng)?.city.id == town.id) p,
    ]..sort((a, b) => a.title.compareTo(b.title));
    return showModalBottomSheet<({double lat, double lng})>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        var filter = '';
        return StatefulBuilder(
          builder: (context, set) {
            final shown = [
              for (final p in inTown)
                if (filter.isEmpty || p.title.toLowerCase().contains(filter)) p,
            ];
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.75,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('"$typed" is near which place?', style: AppText.display(17)),
                      const SizedBox(height: 4),
                      Text('Pick the nearest known place in ${town.name}. The fare and km are worked out from it.',
                          style: AppText.body(13, color: AppColors.muted)),
                      const SizedBox(height: 10),
                      TextField(
                        decoration: const InputDecoration(hintText: 'Search a nearby place', prefixIcon: Icon(Icons.search_rounded)),
                        onChanged: (v) => set(() => filter = v.trim().toLowerCase()),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: ListView(
                          children: [
                            for (final p in shown)
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.place_outlined, color: AppColors.green),
                                title: Text(p.title, style: AppText.body(14.5, weight: FontWeight.w600)),
                                subtitle: p.subtitle.isEmpty ? null : Text(p.subtitle, style: AppText.body(12, color: AppColors.muted)),
                                onTap: () => Navigator.pop(context, (lat: p.lat, lng: p.lng)),
                              ),
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.location_city_rounded, color: AppColors.navy),
                              title: Text("I don't know — ${town.name} centre", style: AppText.body(14.5, weight: FontWeight.w600)),
                              onTap: () => Navigator.pop(context, (lat: town.lat!, lng: town.lng!)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
  void _finish(double lat, double lng, String label) {
    final n = widget.catalog.nearestCity(lat, lng);
    if (n == null) return;
    if (!_inScope(lat, lng)) {
      final names = _cities.map((c) => c.name).join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('We only serve $names. Choose a place there.')),
      );
      return;
    }
    Navigator.of(context).pop(MapPick(point: GeoPoint(lat, lng), nearestName: n.city.name, label: label));
  }

  void _pick(PlaceSuggestion s) => _finish(s.lat, s.lng, s.title);

  /// The place is not on any map: keep the words as written, located by the town named in them.
  Future<void> _useTyped() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final saved = _localMatches(text);
    if (saved.isNotEmpty) {
      _finish(saved.first.lat, saved.first.lng, text);
      return;
    }
    // Try the online map first: if it knows the place, the distance is exact.
    try {
      final b = _box;
      final hits = await ref
          .read(placeSearchProvider)
          .search(_expanded(text), minLat: b.minLat, minLng: b.minLng, maxLat: b.maxLat, maxLng: b.maxLng);
      final ok = hits.where((s) => _inScope(s.lat, s.lng));
      if (ok.isNotEmpty && mounted) {
        _finish(ok.first.lat, ok.first.lng, text);
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    var town = _townNamedIn(text);
    // No town in the words: ask which town it is in (one tap), so the area and the distance are known.
    town ??= await showDialog<City>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Which town is this in?'),
        children: [
          for (final c in _cities)
            SimpleDialogOption(onPressed: () => Navigator.pop(context, c), child: Text(c.name)),
        ],
      ),
    );
    if (town == null || !mounted) return;
    final near = await _askNearby(town, text);
    if (near == null || !mounted) return;
    _finish(near.lat, near.lng, text);
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    final here = await ref.read(locationServiceProvider).current();
    if (!mounted) return;
    if (here == null) {
      setState(() => _locating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get your location. Allow location access, or write the address.')),
      );
      return;
    }
    final name = await ref.read(placeSearchProvider).reverse(here.lat, here.lng);
    if (!mounted) return;
    setState(() => _locating = false);
    _finish(here.lat, here.lng, name ?? 'My location');
  }

  @override
  Widget build(BuildContext context) {
    final q = _ctrl.text.trim();
    final towns = _cities;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (_) => _useTyped(),
              decoration: InputDecoration(
                hintText: 'Write the place, e.g. ravi town Kamalia',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : q.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _ctrl.clear();
                              _onChanged('');
                            },
                          ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  // inDrive style: put the pin on the map yourself.
                  ListTile(
                    leading: const Icon(Icons.map_rounded, color: AppColors.green),
                    title: Text('Choose on map', style: AppText.body(15, weight: FontWeight.w700)),
                    subtitle: Text('Move the map so the pin is on the place', style: AppText.body(12.5, color: AppColors.muted)),
                    onTap: () async {
                      final pick = await pickOnMap(context, title: widget.title, catalog: widget.catalog, requireService: true);
                      if (pick == null || !mounted) return;
                      if (!_inScope(pick.point.lat, pick.point.lng)) {
                        _finish(pick.point.lat, pick.point.lng, pick.serverLabel);
                        return;
                      }
                      Navigator.of(this.context).pop(pick);
                    },
                  ),
                  if (widget.allowMyLocation && q.isEmpty)
                    ListTile(
                      leading: _locating
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location_rounded, color: AppColors.green),
                      title: Text('Use my current location', style: AppText.body(15, weight: FontWeight.w600)),
                      onTap: _locating ? null : _useMyLocation,
                    ),
                  if (q.length < 2) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                      child: Text('Or start with a town', style: AppText.body(13, color: AppColors.muted)),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in towns)
                          ActionChip(
                            backgroundColor: AppColors.white,
                            side: const BorderSide(color: AppColors.border),
                            label: Text(t.name, style: AppText.body(13.5, weight: FontWeight.w600)),
                            onPressed: () => _finish(t.lat!, t.lng!, t.name),
                          ),
                      ],
                    ),
                  ] else ...[
                    for (final s in _suggestions)
                      ListTile(
                        leading: Icon(s.saved ? Icons.push_pin_rounded : Icons.place_outlined, color: AppColors.green),
                        title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: AppText.body(14.5, weight: FontWeight.w600)),
                        subtitle: s.subtitle.isEmpty
                            ? null
                            : Text(s.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: AppText.body(12.5, color: AppColors.muted)),
                        onTap: () => _pick(s),
                      ),
                    ListTile(
                      leading: const Icon(Icons.edit_location_alt_rounded, color: AppColors.navy),
                      title: Text('Use "$q" as my address',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(14.5, weight: FontWeight.w600)),
                      subtitle: Text(
                        _searching ? 'Searching…' : 'Not in the list? The driver sees exactly what you wrote.',
                        style: AppText.body(12.5, color: AppColors.muted),
                      ),
                      onTap: _useTyped,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
