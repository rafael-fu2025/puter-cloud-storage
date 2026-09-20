/// Normalised error taxonomy for every Puter interaction.
///
/// Nothing above the transport layer should ever inspect an HTTP status code,
/// a WebDAV fault element, or a Puter.js error object. Transports translate
/// into [PuterException], and the rest of the app switches on [PuterErrorKind].
///
/// The classification drives retry behaviour, so the mapping from wire errors
/// to kinds is load-bearing — see `docs/architecture.md` §6.1.
library;

/// What kind of failure occurred, independent of how it was detected.
enum PuterErrorKind {
  /// Credential missing, malformed, or rejected. Never retry — re-onboard.
  authInvalid,

  /// Authenticated but not permitted for this resource.
  permissionDenied,

  /// Path does not exist.
  notFound,

  /// Path already exists where one must not (mkdir, non-overwriting write).
  alreadyExists,

  /// Rate or concurrency limit tripped (HTTP 429, `too_many_requests`).
  /// Back off and retry; the window is at most 60s, or 1h for the sustained
  /// filesystem budget.
  rateLimited,

  /// Monthly usage credit exhausted (HTTP 402, `insufficient_funds`).
  /// Retrying changes nothing — the user must top up or upgrade.
  insufficientFunds,

  /// Endpoint is restricted to paid plans (HTTP 402, `subscription_required`).
  /// Retrying changes nothing. Notably includes `{ anyone: true }` link
  /// sharing and the OpenAI/Anthropic-compatible AI endpoints.
  subscriptionRequired,

  /// Storage quota reached (HTTP 413, `storage_limit_reached`).
  /// Retrying changes nothing; reads keep working. Keep the local file.
  storageLimitReached,

  /// Network unreachable, DNS failure, timeout, connection reset.
  network,

  /// Transport returned something we could not parse or interpret.
  protocol,

  /// Request rejected as malformed before reaching storage.
  badRequest,

  /// WebDAV returned 207 Multistatus carrying per-entry errors. Partial
  /// success is possible and must be surfaced rather than swallowed.
  partialFailure,

  /// The selected transport cannot express this operation. Not a user error.
  unsupported,

  /// Anything unclassified. Treated as transient but logged loudly.
  unknown,
}

/// A failure from any Puter transport, normalised for the application layer.
class PuterException implements Exception {
  const PuterException(
    this.kind,
    this.message, {
    this.statusCode,
    this.code,
    this.path,
    this.cause,
    this.failedItems = const [],
  });

  final PuterErrorKind kind;

  /// Human-readable, safe to log. Must never contain credential material.
  final String message;

  /// HTTP status when the failure came over HTTP.
  final int? statusCode;

  /// Server-supplied machine code, e.g. `storage_limit_reached`.
  final String? code;

  /// Remote path involved, when applicable.
  final String? path;

  /// Underlying error, retained for diagnostics only.
  final Object? cause;

  /// Per-entry failures for batch or multistatus operations.
  ///
  /// Puter's upload API is **not atomic**: a partial failure leaves earlier
  /// files written and is never rolled back. Each entry here names a specific
  /// file so the UI can attribute success and failure correctly.
  final List<FailedItem> failedItems;

  /// Whether retrying the identical request could plausibly succeed.
  ///
  /// Deliberately excludes [authInvalid]: a retry loop on authentication can
  /// trip WebDAV's failed-sign-in lockout and lock the user out of their own
  /// storage for 15 minutes. See `docs/security.md` §4.
  bool get isRetryable => switch (kind) {
        PuterErrorKind.rateLimited ||
        PuterErrorKind.network ||
        PuterErrorKind.unknown =>
          true,
        _ => false,
      };

  /// Whether the failure requires the user to act before progress is possible.
  bool get requiresUserAction => switch (kind) {
        PuterErrorKind.insufficientFunds ||
        PuterErrorKind.subscriptionRequired ||
        PuterErrorKind.storageLimitReached ||
        PuterErrorKind.authInvalid =>
          true,
        _ => false,
      };

  @override
  String toString() {
    final buffer = StringBuffer('PuterException(${kind.name})');
    if (statusCode != null) buffer.write(' [$statusCode]');
    if (code != null) buffer.write(' ($code)');
    if (path != null) buffer.write(' at $path');
    buffer.write(': $message');
    if (failedItems.isNotEmpty) {
      buffer.write(' — ${failedItems.length} item(s) failed');
    }
    return buffer.toString();
  }
}

/// A single failed entry within a batch or multistatus operation.
class FailedItem {
  const FailedItem({
    required this.path,
    required this.message,
    this.code,
    this.statusCode,
  });

  final String path;
  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => '$path: $message';
}

/// Maps wire-level failures onto [PuterErrorKind].
///
/// Kept separate from the transports so every transport classifies identically
/// and the rules can be unit-tested without a network.
abstract final class ErrorMapper {
  /// Classify an HTTP response.
  static PuterErrorKind fromHttpStatus(int status, {String? code}) {
    // Server-supplied codes are more specific than the status alone.
    switch (code) {
      case 'storage_limit_reached':
        return PuterErrorKind.storageLimitReached;
      case 'insufficient_funds':
        return PuterErrorKind.insufficientFunds;
      case 'subscription_required':
        return PuterErrorKind.subscriptionRequired;
      case 'too_many_requests':
        return PuterErrorKind.rateLimited;
    }

    return switch (status) {
      400 => PuterErrorKind.badRequest,
      401 => PuterErrorKind.authInvalid,
      403 => PuterErrorKind.permissionDenied,
      404 => PuterErrorKind.notFound,
      405 => PuterErrorKind.unsupported,
      409 => PuterErrorKind.alreadyExists,
      413 => PuterErrorKind.storageLimitReached,
      402 => PuterErrorKind.insufficientFunds,
      429 => PuterErrorKind.rateLimited,
      501 => PuterErrorKind.unsupported,
      >= 500 => PuterErrorKind.network,
      _ => PuterErrorKind.unknown,
    };
  }

  /// Build an exception from an HTTP response.
  static PuterException fromResponse({
    required int status,
    required String message,
    String? code,
    String? path,
    Object? cause,
  }) {
    return PuterException(
      fromHttpStatus(status, code: code),
      message,
      statusCode: status,
      code: code,
      path: path,
      cause: cause,
    );
  }

  /// Classify a transport-level exception (socket, TLS, timeout).
  static PuterException fromTransportError(Object error, {String? path}) {
    final kind = switch (error) {
      _ when error is PuterException => error.kind,
      _ => PuterErrorKind.network,
    };
    if (error is PuterException) return error;
    return PuterException(
      kind,
      'Network failure: $error',
      path: path,
      cause: error,
    );
  }
}
