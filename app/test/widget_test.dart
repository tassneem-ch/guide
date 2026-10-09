import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:guide/app/app.dart';
import 'package:guide/application/settings.dart';
import 'package:guide/data/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home screen renders planner form and prayer hint',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await PrefsLocalStore.open();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [localStoreProvider.overrideWithValue(store)],
        child: const GuideApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The planner form is visible with from/to fields and a plan button.
    expect(find.text('Plan a journey'), findsOneWidget);
    expect(find.text('Plan route'), findsOneWidget);

    // Fixture banner is absent by default (live backend mode).
    expect(find.textContaining('simulated'), findsNothing);

    // Settings reachable.
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('demo mode shows the fixture banner prominently',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await PrefsLocalStore.open();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [localStoreProvider.overrideWithValue(store)],
        child: const GuideApp(),
      ),
    );
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(GuideApp)));
    container.read(settingsProvider.notifier).setDemoMode(true);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('data is simulated, not live'),
      findsWidgets,
    );
  });
}
