import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guide/application/settings.dart';
import 'package:guide/data/mock_repositories.dart';
import 'package:guide/domain/models.dart';
import 'package:guide/domain/repositories.dart';
import 'package:guide/l10n/generated/app_localizations.dart';
import 'package:guide/presentation/widgets/place_field.dart';

/// Fake geocode backend with per-query control (delay, failure, resolution).
class FakeGeocodeRepository implements GeocodeRepository {
  List<PlaceSuggestion> suggestions;
  final List<String> suggestedQueries = [];
  final Map<String, Completer<List<PlaceSuggestion>>> pending = {};
  bool failNextSuggest = false;
  int resolveCalls = 0;
  GeoPoint? resolvedPoint;

  FakeGeocodeRepository({this.suggestions = const []});

  @override
  Future<List<PlaceSuggestion>> suggest(
    String query, {
    String? sessionToken,
    GeoPoint? bias,
  }) {
    suggestedQueries.add(query);
    if (failNextSuggest) {
      failNextSuggest = false;
      throw Failure('suggestion service down', kind: FailureKind.network);
    }
    final completer = pending[query];
    if (completer != null) return completer.future;
    return Future.value(suggestions);
  }

  @override
  Future<GeoPoint> resolveSuggestion(
    PlaceSuggestion suggestion, {
    String? sessionToken,
  }) async {
    resolveCalls++;
    final point = resolvedPoint ?? suggestion.point;
    if (point == null) {
      throw Failure('no coordinates', kind: FailureKind.validation);
    }
    return point;
  }

  @override
  Future<List<GeoPoint>> geocode(String query) async => [];
}

Widget _harness(GeocodeRepository repo, Widget Function() field) =>
    ProviderScope(
      overrides: [
        repositoriesProvider.overrideWithValue(Repositories(
          geocode: repo,
          prayer: MockPrayerRepository(),
          route: MockRouteRepository(),
          trip: MockTripRepository(),
          fixtureMode: false,
        )),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(child: field()),
        ),
      ),
    );

void main() {
  testWidgets('typing shows debounced suggestions from the proxy',
      (tester) async {
    final repo = FakeGeocodeRepository(suggestions: const [
      PlaceSuggestion(label: 'Paris, France',
          point: GeoPoint(lat: 48.8566, lon: 2.3522, tz: 'Europe/Paris')),
      PlaceSuggestion(label: 'Paris 18e, France',
          point: GeoPoint(lat: 48.8924, lon: 2.3494, tz: 'Europe/Paris')),
    ]);
    GeoPoint? selected;
    await tester.pumpWidget(_harness(repo, () => PlaceField(
          label: 'From',
          icon: Icons.trip_origin_outlined,
          onSelected: (p) => selected = p,
        )));

    await tester.enterText(find.byType(TextField), 'Par');
    expect(find.text('Paris, France'), findsNothing); // not yet: debounced
    await tester.pump(const Duration(milliseconds: 400));

    expect(repo.suggestedQueries, ['Par']);
    expect(find.text('Paris, France'), findsOneWidget);
    expect(find.text('Paris 18e, France'), findsOneWidget);

    await tester.tap(find.text('Paris, France'));
    await tester.pump();
    expect(selected, isNotNull);
    expect(selected!.lat, 48.8566);
    expect(selected!.lon, 2.3522);
    expect(repo.resolveCalls, 1);
  });

  testWidgets('a suggestion without coordinates is resolved before use',
      (tester) async {
    final repo = FakeGeocodeRepository(suggestions: const [
      PlaceSuggestion(label: 'Eiffel Tower', id: 'ChIJabc'),
    ]);
    repo.resolvedPoint =
        const GeoPoint(lat: 48.8584, lon: 2.2945, name: 'Eiffel Tower, Paris');
    GeoPoint? selected;
    await tester.pumpWidget(_harness(repo, () => PlaceField(
          label: 'To',
          icon: Icons.place_outlined,
          onSelected: (p) => selected = p,
        )));

    await tester.enterText(find.byType(TextField), 'Eiffel');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Eiffel Tower'));
    await tester.pump();

    expect(repo.resolveCalls, 1);
    expect(selected!.lat, 48.8584);
    expect(selected!.name, 'Eiffel Tower, Paris');
  });

  testWidgets('an older in-flight response never overwrites a newer query',
      (tester) async {
    final repo = FakeGeocodeRepository();
    final slow = Completer<List<PlaceSuggestion>>();
    repo.pending['aaa'] = slow;
    await tester.pumpWidget(_harness(repo, () => PlaceField(
          label: 'From',
          icon: Icons.trip_origin_outlined,
          onSelected: (_) {},
        )));

    await tester.enterText(find.byType(TextField), 'aaa');
    await tester.pump(const Duration(milliseconds: 400)); // slow request out

    await tester.enterText(find.byType(TextField), 'aab');
    repo.suggestions = const [
      PlaceSuggestion(label: 'AAB result', point: GeoPoint(lat: 1, lon: 2)),
    ];
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('AAB result'), findsOneWidget);

    // The stale response arrives late — it must be dropped.
    slow.complete(const [
      PlaceSuggestion(label: 'AAA stale', point: GeoPoint(lat: 3, lon: 4)),
    ]);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('AAA stale'), findsNothing);
    expect(find.text('AAB result'), findsOneWidget);
  });

  testWidgets('failures are visible with a working retry', (tester) async {
    final repo = FakeGeocodeRepository(suggestions: const [
      PlaceSuggestion(label: 'Recovered', point: GeoPoint(lat: 5, lon: 6)),
    ]);
    await tester.pumpWidget(_harness(repo, () => PlaceField(
          label: 'From',
          icon: Icons.trip_origin_outlined,
          onSelected: (_) {},
        )));

    repo.failNextSuggest = true;
    await tester.enterText(find.byType(TextField), 'Cairo');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('suggestion service down'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('suggestion service down'), findsNothing);
    expect(find.text('Recovered'), findsOneWidget);
  });

  testWidgets('empty results show an explicit no-results state',
      (tester) async {
    final repo = FakeGeocodeRepository(suggestions: const []);
    await tester.pumpWidget(_harness(repo, () => PlaceField(
          label: 'From',
          icon: Icons.trip_origin_outlined,
          onSelected: (_) {},
        )));

    await tester.enterText(find.byType(TextField), 'zzz-nowhere');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No results'), findsOneWidget);
  });

  testWidgets('clearing resets the field and invalidates the selection',
      (tester) async {
    final repo = FakeGeocodeRepository(suggestions: const [
      PlaceSuggestion(label: 'Rome, Italy',
          point: GeoPoint(lat: 41.9, lon: 12.5, tz: 'Europe/Rome')),
    ]);
    var cleared = 0;
    await tester.pumpWidget(_harness(repo, () => PlaceField(
          label: 'From',
          icon: Icons.trip_origin_outlined,
          onSelected: (_) {},
          onCleared: () => cleared++,
        )));

    await tester.enterText(find.byType(TextField), 'Rom');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Rome, Italy'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Rome, Italy'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();
    expect(find.widgetWithText(TextField, ''), findsOneWidget);
    expect(cleared, 1);
  });

  testWidgets('typing coordinates directly selects that exact point',
      (tester) async {
    final repo = FakeGeocodeRepository();
    GeoPoint? selected;
    await tester.pumpWidget(_harness(repo, () => PlaceField(
          label: 'From',
          icon: Icons.trip_origin_outlined,
          onSelected: (p) => selected = p,
        )));

    await tester.enterText(find.byType(TextField), '36.8065, 10.1815');
    await tester.pump();

    expect(selected, isNotNull);
    expect(selected!.lat, closeTo(36.8065, 1e-9));
    expect(selected!.lon, closeTo(10.1815, 1e-9));
    expect(repo.suggestedQueries, isEmpty); // no network involved
  });

  testWidgets('editing text away from a selection invalidates it',
      (tester) async {
    final repo = FakeGeocodeRepository(suggestions: const [
      PlaceSuggestion(label: 'Rome, Italy',
          point: GeoPoint(lat: 41.9, lon: 12.5, tz: 'Europe/Rome')),
    ]);
    var cleared = 0;
    GeoPoint? selected;
    await tester.pumpWidget(_harness(repo, () => PlaceField(
          label: 'From',
          icon: Icons.trip_origin_outlined,
          onSelected: (p) => selected = p,
          onCleared: () => cleared++,
        )));

    await tester.enterText(find.byType(TextField), 'Rom');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Rome, Italy'));
    await tester.pump();
    expect(selected, isNotNull);

    // User keeps typing after selecting: the stored point must not survive
    // as if it still matched the text.
    await tester.enterText(find.byType(TextField), 'Rome, and more');
    await tester.pump();
    expect(cleared, 1);
    await tester.pump(const Duration(milliseconds: 400)); // flush debounce
  });

  testWidgets('a selection echoed back through initial keeps its label',
      (tester) async {
    // The planner feeds the selected point back into the field. That echo
    // must never replace the place name with raw coordinates or drop the
    // selection state (which would silently stop invalidating the point
    // when the user edits the text).
    final repo = FakeGeocodeRepository(suggestions: const [
      PlaceSuggestion(label: 'Rome, Italy',
          point: GeoPoint(lat: 41.9, lon: 12.5, tz: 'Europe/Rome')),
    ]);
    GeoPoint? chosen;
    var cleared = 0;
    await tester.pumpWidget(_harness(repo, () {
      return StatefulBuilder(
        builder: (context, setModalState) => PlaceField(
          label: 'From',
          icon: Icons.trip_origin_outlined,
          initial: chosen,
          onSelected: (p) => setModalState(() => chosen = p),
          onCleared: () {
            cleared++;
            setModalState(() => chosen = null);
          },
        ),
      );
    }));

    await tester.enterText(find.byType(TextField), 'Rom');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Rome, Italy'));
    await tester.pump();

    expect(find.widgetWithText(TextField, 'Rome, Italy'), findsOneWidget);
    expect(find.text('No results'), findsNothing);

    // Editing afterwards still invalidates the (now stale) selection.
    await tester.enterText(find.byType(TextField), 'Rome, and more');
    await tester.pump();
    expect(cleared, 1);
    await tester.pump(const Duration(milliseconds: 400)); // flush debounce
  });

  testWidgets('a coordinate-backed value shows no phantom no-results',
      (tester) async {
    // A field initialized with a nameless point shows its coordinates.
    // Nothing was searched, so "No results" must not appear.
    final repo = FakeGeocodeRepository();
    await tester.pumpWidget(_harness(repo, () => PlaceField(
          label: 'From',
          icon: Icons.trip_origin_outlined,
          initial: const GeoPoint(lat: 36.8, lon: 10.18),
          onSelected: (_) {},
        )));

    expect(find.widgetWithText(TextField, '36.8, 10.18'), findsOneWidget);
    expect(find.text('No results'), findsNothing);
    expect(repo.suggestedQueries, isEmpty);
  });
}
