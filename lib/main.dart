/// Puter Cloud Storage — Android client.
///
/// Entry point. Wires the composition root and hands off to [PuterCloudApp].
///
/// Note on scope: this repository currently contains the **foundation** —
/// transport layer, rate limiting, token vault, domain model and error
/// taxonomy — which is what Phase 1 of `docs/roadmap.md` calls for. Feature
/// screens arrive in Phases 2 to 4.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/config/app_config.dart';
import 'core/network/request_scheduler.dart';
import 'core/security/token_vault.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configuration is created once here rather than being read from globals
  // scattered through the codebase.
  const config = AppConfig();

  runApp(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(config),
        tokenVaultProvider.overrideWithValue(SecureTokenVault()),
        requestSchedulerProvider.overrideWithValue(
          RequestScheduler(config: config),
        ),
      ],
      child: const PuterCloudApp(),
    ),
  );
}
