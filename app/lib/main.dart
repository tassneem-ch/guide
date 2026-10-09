import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'data/local_store.dart';
import 'application/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await PrefsLocalStore.open();
  runApp(
    ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: const GuideApp(),
    ),
  );
}
