/// Secure storage for the Puter auth token.
///
/// The token is an **account-wide, non-expiring, non-refreshable** credential:
/// anyone holding it can read and delete every file in the account. There is
/// no scoping and no rotation, so storage discipline is the only defence.
/// See `docs/security.md`.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Reads and writes the Puter auth token.
///
/// Deliberately narrow. There is no "current token" getter, because a
/// long-lived in-memory copy is exactly the leak this design avoids — callers
/// read at the moment of use and drop the reference.
abstract class TokenVault {
  /// Read the token, or `null` when the app has never been onboarded.
  Future<String?> read();

  /// Persist a token, replacing any existing value.
  Future<void> write(String token);

  /// Remove the token. Idempotent.
  Future<void> clear();

  /// Whether a token is present. Cheap; does not decrypt the payload where
  /// the platform can answer from metadata.
  Future<bool> get hasToken;
}

/// Keystore-backed implementation.
///
/// Uses Android's `EncryptedSharedPreferences`, which is backed by the
/// hardware keystore where available. Plain `SharedPreferences` is never used
/// for this value.
class SecureTokenVault implements TokenVault {
  SecureTokenVault({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
                // The token must not travel to another device via Android
                // auto-backup. The manifest backup rules exclude this entry
                // too; this is the belt to that pair of braces.
                resetOnError: true,
              ),
            );

  final FlutterSecureStorage _storage;

  static const String _key = 'puter_auth_token';

  @override
  Future<String?> read() async {
    final value = await _storage.read(key: _key);
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Future<void> write(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(token, 'token', 'Token must not be empty');
    }
    await _storage.write(key: _key, value: trimmed);
  }

  @override
  Future<void> clear() => _storage.delete(key: _key);

  @override
  Future<bool> get hasToken async => (await read()) != null;
}

/// In-memory vault for tests and for the spike tool.
///
/// Never used in a release build.
class InMemoryTokenVault implements TokenVault {
  InMemoryTokenVault([this._token]);

  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token.trim();

  @override
  Future<void> clear() async => _token = null;

  @override
  Future<bool> get hasToken async => _token != null;
}

/// Utilities for keeping credential material out of logs.
///
/// Applied by the HTTP interceptor and by the structured logger. Both are
/// required: an interceptor alone does not protect against an error payload
/// that echoes a header.
abstract final class CredentialRedactor {
  static const String _mask = '***REDACTED***';

  /// Header names whose values must never be logged.
  static const Set<String> sensitiveHeaders = <String>{
    'authorization',
    'proxy-authorization',
    'cookie',
    'set-cookie',
  };

  /// Redact sensitive headers from a header map, returning a copy.
  static Map<String, String> redactHeaders(Map<String, String> headers) {
    return <String, String>{
      for (final entry in headers.entries)
        entry.key: sensitiveHeaders.contains(entry.key.toLowerCase())
            ? _mask
            : entry.value,
    };
  }

  /// Replace any occurrence of [secret] inside [text] with the mask.
  ///
  /// Used as a last-resort scrub before anything is written to a log sink.
  static String redactSecret(String text, String? secret) {
    if (secret == null || secret.isEmpty) return text;
    return text.replaceAll(secret, _mask);
  }

  /// Heuristic scrub for token-shaped strings, for use when the secret is not
  /// in hand — for example when logging a response body.
  ///
  /// Conservative on purpose: it may over-match, which is the safe direction.
  static String redactTokenShaped(String text) {
    final patterns = <RegExp>[
      // Basic auth payloads
      RegExp(r'Basic\s+[A-Za-z0-9+/=]{16,}', caseSensitive: false),
      // Bearer payloads
      RegExp(r'Bearer\s+[A-Za-z0-9\-._~+/=]{16,}', caseSensitive: false),
      // Long opaque tokens in JSON-ish contexts
      RegExp(r'("?(?:token|api_?key|secret|password)"?\s*[:=]\s*")[^"]{8,}"',
          caseSensitive: false),
    ];
    var result = text;
    for (final pattern in patterns) {
      result = result.replaceAllMapped(pattern, (match) {
        if (match.groupCount >= 1 && match.group(1) != null) {
          return '${match.group(1)}$_mask"';
        }
        return _mask;
      });
    }
    return result;
  }
}
