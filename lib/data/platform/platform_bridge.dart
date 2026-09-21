/// The single bridge to `MainActivity.kt`.
///
/// One channel for every platform capability the app needs. Keeping the name in
/// one place means the Kotlin handler and the Dart callers cannot drift apart —
/// a mismatch there fails silently at runtime with `MissingPluginException`
/// rather than at compile time.
library;

import 'package:flutter/services.dart';

/// Name of the method channel implemented in `MainActivity.kt`.
abstract final class PlatformChannel {
  static const String name = 'com.putercloud.puter_cloud_storage/files';
}

/// Platform operations that no plugin is needed for.
///
/// Deliberately hand-written rather than delegated: the obvious plugins pin
/// `compileSdk 34` against this app's 36 (docs/build-assessment.md §4.4–4.5),
/// and each of these is a few lines over an API that has been stable for years.
abstract final class PlatformBridge {
  static const MethodChannel _channel = MethodChannel(PlatformChannel.name);

  /// Open an https URL in the user's browser.
  ///
  /// Returns `false` when nothing on the device can handle it, so the caller can
  /// offer the address as selectable text instead of leaving a dead tap.
  static Future<bool> openUrl(String url) async {
    try {
      final bool? opened = await _channel.invokeMethod<bool>(
        'openUrl',
        <String, dynamic>{'url': url},
      );
      return opened ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
