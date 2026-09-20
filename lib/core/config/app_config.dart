/// Runtime configuration.
///
/// Every tunable lives here so that no magic numbers are scattered through the
/// codebase, and so the diagnostics screen can override values at runtime
/// without a rebuild.
///
/// Pure Dart on purpose: `lib/core/` must be testable with `dart test`, with no
/// Flutter dependency. Every field is `final`, so instances are immutable
/// without needing an annotation to say so.
library;

/// Which wire protocol is used to reach Puter.
///
/// Only [webdav] is implemented. The other modes are declared because ADR 0002
/// designed them and the settings screen records the intention, but selecting
/// one changes nothing at runtime — [WebViewTransport] cannot be built against
/// the current toolchain (docs/build-assessment.md §4.4) and `RestTransport` was
/// never enabled. See `PuterTransport` for what actually sits behind the
/// interface today.
enum TransportMode {
  /// WebDAV, pure Dart. The primary path — see ADR 0002. The only implemented
  /// transport.
  webdav,

  /// Puter.js inside a WebView. Fallback for what WebDAV cannot express.
  /// Declared, not built.
  webview,

  /// Direct driver calls. Undocumented; never enabled.
  rest,

  /// Probe at startup and pick the best available. Default.
  auto,
}

/// Puter account plan tier. Determines which rate-limit column applies.
///
/// Detection is best-effort: the client starts at [free] and promotes itself
/// when the account reports a larger allowance. Starting conservative is the
/// safe direction — over-eager limits cost speed, under-eager ones cost a
/// rate-limit lockout.
enum PlanTier { free, paid }

/// Immutable application configuration.
class AppConfig {
  const AppConfig({
    this.transportMode = TransportMode.auto,
    this.planTier = PlanTier.free,
    this.maxConcurrentRequests = 5,
    this.maxConcurrentTransfers = 4,
    this.chunkSizeBytes = 8 * 1024 * 1024,
    this.listingPageSize = 200,
    this.listingCacheTtl = const Duration(seconds: 5),
    this.requestTimeout = const Duration(seconds: 30),
    this.transferTimeout = const Duration(minutes: 30),
    this.maxRetryBackoff = const Duration(seconds: 60),
    this.maxRetryAttempts = 5,
    this.quotaWarningThreshold = 0.9,
    this.enableBackgroundHealthCheck = false,
    this.verboseHttpLogging = false,
  });

  final TransportMode transportMode;
  final PlanTier planTier;

  /// Global ceiling across every request class.
  ///
  /// Defaults to **5**, because that is the binding constraint: the free tier
  /// allows 5 concurrent reads (6 writes, 10 reads/writes paid), and WebDAV
  /// allows 10 for the whole network. A higher global cap would let the
  /// scheduler admit more reads than the read bucket permits.
  ///
  /// Raised only when Phase 0 measurement justifies it.
  final int maxConcurrentRequests;

  /// Parallel file transfers. Must not exceed [maxConcurrentRequests].
  final int maxConcurrentTransfers;

  /// Upload chunk size for resumable transfers.
  ///
  /// 8 MiB balances resume granularity against request count: smaller chunks
  /// mean more requests against a tight per-minute budget, larger ones mean
  /// more work replayed after an interruption.
  final int chunkSizeBytes;

  /// Entries per `readdir` / PROPFIND page. Matches Puter's documented paging
  /// sweet spot and keeps the local index write batch reasonable.
  final int listingPageSize;

  /// How long a directory listing is served from memory before refetching.
  final Duration listingCacheTtl;

  final Duration requestTimeout;
  final Duration transferTimeout;

  /// Ceiling for exponential backoff. Puter's rolling window is at most 60s,
  /// so backing off past that gains nothing.
  final Duration maxRetryBackoff;

  final int maxRetryAttempts;

  /// Fraction of quota at which the UI warns the user.
  final double quotaWarningThreshold;

  /// Periodic token validation.
  ///
  /// **Disabled by default and deliberately so.** Failed sign-ins trip a
  /// lockout after 10 attempts in 15 minutes, returning 429 even for a correct
  /// token. A background poller that retries on failure can lock the user out
  /// of their own storage. See `docs/security.md` §4.
  final bool enableBackgroundHealthCheck;

  /// Log full HTTP headers. Debug only; asserts in release.
  final bool verboseHttpLogging;

  AppConfig copyWith({
    TransportMode? transportMode,
    PlanTier? planTier,
    int? maxConcurrentRequests,
    int? maxConcurrentTransfers,
    int? chunkSizeBytes,
    int? listingPageSize,
    Duration? listingCacheTtl,
    Duration? requestTimeout,
    Duration? transferTimeout,
    Duration? maxRetryBackoff,
    int? maxRetryAttempts,
    double? quotaWarningThreshold,
    bool? enableBackgroundHealthCheck,
    bool? verboseHttpLogging,
  }) {
    return AppConfig(
      transportMode: transportMode ?? this.transportMode,
      planTier: planTier ?? this.planTier,
      maxConcurrentRequests: maxConcurrentRequests ?? this.maxConcurrentRequests,
      maxConcurrentTransfers:
          maxConcurrentTransfers ?? this.maxConcurrentTransfers,
      chunkSizeBytes: chunkSizeBytes ?? this.chunkSizeBytes,
      listingPageSize: listingPageSize ?? this.listingPageSize,
      listingCacheTtl: listingCacheTtl ?? this.listingCacheTtl,
      requestTimeout: requestTimeout ?? this.requestTimeout,
      transferTimeout: transferTimeout ?? this.transferTimeout,
      maxRetryBackoff: maxRetryBackoff ?? this.maxRetryBackoff,
      maxRetryAttempts: maxRetryAttempts ?? this.maxRetryAttempts,
      quotaWarningThreshold:
          quotaWarningThreshold ?? this.quotaWarningThreshold,
      enableBackgroundHealthCheck:
          enableBackgroundHealthCheck ?? this.enableBackgroundHealthCheck,
      verboseHttpLogging: verboseHttpLogging ?? this.verboseHttpLogging,
    );
  }
}

/// Endpoint constants.
///
/// The WebDAV host is **unverified** — Phase 0 confirms it against the live
/// account. Candidates are tried in order, and the first that answers a
/// `PROPFIND` is cached for the session.
abstract final class PuterEndpoints {
  /// Candidate WebDAV hosts, probed in order during Phase 0.
  static const List<String> webdavHostCandidates = <String>[
    'https://dav.puter.com',
    'https://webdav.puter.com',
    'https://api.puter.com/dav',
  ];

  /// Driver-call endpoint used by the REST fallback. Undocumented.
  static const String driverCall = 'https://api.puter.com/drivers/call';

  /// Puter.js CDN, used only by the WebView bridge transport.
  static const String puterJsCdn = 'https://js.puter.com/v2/';

  /// Dashboard deep link for token creation and revocation.
  static const String dashboardAccount = 'https://puter.com/dashboard#account';

  /// Attribution target, required when building on Puter.js.
  static const String attributionUrl = 'https://developer.puter.com';
}
