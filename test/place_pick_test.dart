import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamgo_app/core/services/place_search_service.dart';
import 'package:kamgo_app/core/theme/app_theme.dart';
import 'package:kamgo_app/features/passenger/presentation/place_pick_screen.dart';
import 'package:kamgo_app/features/rides/domain/catalog.dart';
import 'package:kamgo_app/features/rides/domain/map_pick.dart';
import 'package:kamgo_app/features/rides/presentation/ride_flow_providers.dart';

import 'goldens/golden_fonts.dart';

class _FakeSearch implements PlaceSearch {
  @override
  Future<List<PlaceSuggestion>> search(String q, {double? minLat, double? minLng, double? maxLat, double? maxLng}) async => const [
        PlaceSuggestion(title: 'Lahore Fort', subtitle: 'Lahore', lat: 31.5889, lng: 74.3149),
        PlaceSuggestion(title: 'Islamabad Club', subtitle: 'Islamabad', lat: 33.7294, lng: 73.0931),
        PlaceSuggestion(title: 'Kamalia Bus Stand', subtitle: 'Kamalia', lat: 30.7262, lng: 72.6450),
      ];
  @override
  Future<String?> reverse(double lat, double lng) async => null;
}

class _NoSearch implements PlaceSearch {
  @override
  Future<List<PlaceSuggestion>> search(String q, {double? minLat, double? minLng, double? maxLat, double? maxLng}) async => const [];
  @override
  Future<String?> reverse(double lat, double lng) async => null;
}

const _kamalia = City(id: 'k', name: 'Kamalia', lat: 30.7258, lng: 72.6447, serviceRadiusKm: 25);
const _toba = City(id: 't', name: 'Toba Tek Singh', lat: 30.9709, lng: 72.4826, serviceRadiusKm: 25);

/// Saved places (KAM GO's own list): one landmark in each town.
const _saved = [
  PlaceSuggestion(title: 'Kamalia Bus Stand', subtitle: 'stop', lat: 30.7300, lng: 72.6500, saved: true),
  PlaceSuggestion(title: 'Toba Tek Singh Bus Station', subtitle: 'stop', lat: 30.9750, lng: 72.4900, saved: true),
];

/// Opens the place picker from a button and returns a getter for its result.
Future<MapPick? Function()> _open(WidgetTester tester, {List<City> cities = const [_kamalia], PlaceSearch? search}) async {
  final catalog = Catalog(cities: cities, routes: const [], settings: const AppSettings());
  MapPick? result;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      placeSearchProvider.overrideWithValue(search ?? _NoSearch()),
      placesProvider.overrideWith((_) async => _saved),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await pickPlace(context, title: 'Pickup', catalog: catalog),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => result;
}

Future<void> _typeAndUse(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('as my address'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('an address with its town, near a known place: the spot of that place, the words as written', (tester) async {
    final result = await _open(tester);
    await _typeAndUse(tester, 'ravi town kamalia');
    expect(find.textContaining('is near which place?'), findsOneWidget);
    await tester.tap(find.text('Kamalia Bus Stand').last);
    await tester.pumpAndSettle();
    expect(result()?.label, 'ravi town kamalia');
    expect(result()?.point.lat, 30.7300);
  });

  testWidgets('no town in the words: asks the town, then the nearby place (or the centre)', (tester) async {
    final result = await _open(tester);
    await _typeAndUse(tester, 'bilal town');
    expect(find.text('Which town is this in?'), findsOneWidget);
    await tester.tap(find.text('Kamalia'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining("I don't know"));
    await tester.pumpAndSettle();
    expect(result()?.label, 'bilal town');
    expect(result()?.nearestName, 'Kamalia');
    expect(result()?.point.lat, _kamalia.lat);
  });

  testWidgets('"tts" is understood as Toba Tek Singh (no need to ask the town)', (tester) async {
    final result = await _open(tester, cities: const [_kamalia, _toba]);
    await _typeAndUse(tester, 'model town tts');
    expect(find.text('Which town is this in?'), findsNothing);
    expect(find.textContaining('Pick the nearest known place in Toba Tek Singh'), findsOneWidget);
    // Only Toba's places are offered.
    expect(find.text('Kamalia Bus Stand'), findsNothing);
    await tester.tap(find.text('Toba Tek Singh Bus Station').last);
    await tester.pumpAndSettle();
    expect(result()?.label, 'model town tts');
    expect(result()?.nearestName, 'Toba Tek Singh');
  });

  testWidgets('only places in the cities we serve are offered (no Lahore, no Islamabad)', (tester) async {
    final catalog = Catalog(cities: const [_kamalia], routes: const [], settings: const AppSettings());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        placeSearchProvider.overrideWithValue(_FakeSearch()),
        placesProvider.overrideWith((_) async => const []),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: PlacePickScreen(title: 'Destination', catalog: catalog)),
    ));
    await tester.enterText(find.byType(TextField), 'stand');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Kamalia Bus Stand'), findsOneWidget);
    expect(find.text('Lahore Fort'), findsNothing);
    expect(find.text('Islamabad Club'), findsNothing);
  });
}
