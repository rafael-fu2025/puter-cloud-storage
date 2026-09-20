/// Puter Cloud Storage — Android client.
///
/// Entry point. Builds the object graph once and hands off to [PuterCloudApp].
///
/// Everything that touches the device — the database, the platform channel — is
/// constructed here rather than looked up from a global, so the composition is
/// readable in one place and each piece can be substituted in a test.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/config/app_config.dart';
import 'core/network/request_scheduler.dart';
import 'core/security/token_vault.dart';
import 'data/database/app_database.dart';
import 'data/database/node_cache.dart';
import 'data/platform/device_files.dart';
import 'data/repositories/settings_repository.dart';
import 'data/transfer/transfer_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const config = AppConfig();

  // One database handle for the whole app. Opening is lazy — `LazyDatabase`
  // defers the file lookup to the first query — so this costs nothing at
  // startup and never blocks the first frame.
  final database = AppDatabase.open();

  runApp(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(config),
        tokenVaultProvider.overrideWithValue(SecureTokenVault()),
        requestSchedulerProvider.overrideWithValue(
          RequestScheduler(config: config),
        ),
        databaseProvider.overrideWithValue(database),
        nodeCacheProvider.overrideWithValue(DriftNodeCache(database)),
        transferStoreProvider.overrideWithValue(DriftTransferStore(database)),
        preferencesStoreProvider
            .overrideWithValue(DriftPreferencesStore(database)),
        deviceFilesProvider.overrideWithValue(PlatformDeviceFiles()),
      ],
      child: const PuterCloudApp(),
    ),
  );
}
