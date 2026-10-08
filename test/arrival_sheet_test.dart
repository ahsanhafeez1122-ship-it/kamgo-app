import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamgo_app/core/theme/app_theme.dart';
import 'package:kamgo_app/features/driver/presentation/arrival_sheet.dart';

import 'goldens/golden_fonts.dart';

Future<int?> _open(WidgetTester tester, {int initial = 10, bool accept = true, List<String> taps = const []}) async {
  tester.view.physicalSize = const Size(1080, 2000);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  int? result = -1;
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async => result = await showArrivalSheet(context, fare: 1200, accept: accept, initial: initial),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  for (final t in taps) {
    await tester.tap(find.text(t));
    await tester.pumpAndSettle();
  }
  return result;
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the driver picks the minutes and the button says them', (tester) async {
    await _open(tester, taps: ['15 min']);
    expect(find.text('Accept · arrive in 15 min'), findsOneWidget);
  });

  testWidgets('sending returns the chosen minutes', (tester) async {
    int? got = -1;
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async => got = await showArrivalSheet(context, fare: 1200, accept: false, initial: 10),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 min'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send offer · arrive in 5 min'));
    await tester.pumpAndSettle();
    expect(got, 5);
  });

  testWidgets('a suggested time that is not a choice snaps to the nearest one', (tester) async {
    await _open(tester, initial: 12);
    expect(find.text('Accept · arrive in 10 min'), findsOneWidget);
  });
}
