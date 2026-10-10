import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:guide/app/app.dart';
import 'package:guide/app/router.dart';
import 'package:guide/application/settings.dart';
import 'package:guide/data/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The app's GoRouter is a global that survives between tests — a test
  // that navigates (e.g. to Settings) would leave the next one there.
  setUp(() => goRouter.go('/'));

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

  testWidgets('place field focus shrinks the sheet and unfocus restores it',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await PrefsLocalStore.open();

    // A phone-sized window — the small screen where the suggestions list
    // used to hide behind the half-expanded sheet.
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [localStoreProvider.overrideWithValue(store)],
        child: const GuideApp(),
      ),
    );
    await tester.pumpAndSettle();

    double sheetSize() {
      final sheet = tester.widget<DraggableScrollableSheet>(
        find.byType(DraggableScrollableSheet),
      );
      return sheet.controller!.size;
    }

    expect(sheetSize(), closeTo(0.42, 0.02));

    // Focusing the "To" field collapses the sheet so its suggestions list
    // has room to render even on a small screen with the keyboard open.
    await tester.tap(find.byType(TextField).at(1));
    await tester.pumpAndSettle();
    expect(sheetSize(), lessThan(0.2));

    // Losing focus (e.g. after picking a suggestion) restores the
    // user's previous sheet position.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(sheetSize(), greaterThan(0.4));
  });
}
