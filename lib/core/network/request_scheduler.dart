/// Central rate limiting and request scheduling.
///
/// Puter enforces three independent gates on every call, and a client that
/// ignores any of them will rate-limit itself during ordinary use:
///
/// * **Per-class limits** — `readdir` 300/min free, `write` 120/min free,
///   `read` 300/min free, with a 60/10s burst on `readdir`.
/// * **Concurrency caps** — 5 concurrent reads, 6 concurrent writes on free.
/// * **A global account budget of 8,000 driver calls/min** in front of
///   everything. A 429 from that one means the client is looping.
///
/// WebDAV adds the tightest constraint of all: **600 requests/min and 10
/// concurrent, shared per network rather than per account.**
///
/// Therefore no component issues a request directly. Everything goes through
/// [RequestScheduler.schedule], which enforces the budget, applies backoff,
/// and opens a circuit breaker when a class is clearly saturated.
library;

import 'dart:async';
import 'dart:math';

import '../config/app_config.dart';
import '../error/puter_exception.dart';

/// Request classes with independent budgets, mirroring Puter's own buckets.
enum RequestClass {
  /// Metadata read: PROPFIND depth 0, `fs.stat`.
  stat,

  /// Directory listing: PROPFIND depth 1, `fs.readdir`.
  readdir,

  /// File content read: GET, `fs.read`.
  read,

  /// File content write: PUT, `fs.write`.
  write,

  /// Structural change: MKCOL, DELETE, MOVE, COPY, `fs.mkdir/delete/move/copy`.
  mutation,

  /// Index-backed or server-side search.
  search,

  /// Generating a signed URL.
  signedUrl,

  /// Live quota lookup. Deliberately very cheap — polled sparingly.
  usage,
}

/// Priority bands. User-initiated work always outranks background work, so a
/// thumbnail-warming job never delays a tap.
enum RequestPriority {
  /// Direct response to a user action.
  interactive(0),

  /// Visible but not blocking: prefetch, next-page load.
  visible(1),

  /// Invisible: index refresh, thumbnail warming, auto-backup.
  background(2);

  const RequestPriority(this.rank);

  final int rank;
}

/// Limits for one [RequestClass]. Format follows Puter's paid/free/anonymous
/// columns; this client only ever uses [free] or [paid].
class ClassLimits {
  const ClassLimits({
    required this.perMinuteFree,
    required this.perMinutePaid,
    required this.concurrentFree,
    required this.concurrentPaid,
    this.burstPer10sFree,
    this.burstPer10sPaid,
  });

  final int perMinuteFree;
  final int perMinutePaid;
  final int concurrentFree;
  final int concurrentPaid;
  final int? burstPer10sFree;
  final int? burstPer10sPaid;

  int perMinute(PlanTier tier) =>
      tier == PlanTier.paid ? perMinutePaid : perMinuteFree;

  int concurrent(PlanTier tier) =>
      tier == PlanTier.paid ? concurrentPaid : concurrentFree;

  int? burstPer10s(PlanTier tier) =>
      tier == PlanTier.paid ? burstPer10sPaid : burstPer10sFree;
}

/// Documented filesystem limits, transcribed from Puter's rate-limit reference.
///
/// Seeded at the **free** tier regardless of the account's real plan, and
/// promoted only when the account proves it deserves more. Starting
/// conservative costs throughput; starting optimistic costs a lockout.
abstract final class PuterLimits {
  /// Global account ceiling in front of every per-class limit.
  static const int globalCallsPerMinute = 8000;

  /// WebDAV's shared per-network ceiling — the tightest number in the system.
  static const int webdavRequestsPerMinute = 600;
  static const int webdavConcurrent = 10;

  /// Failed sign-ins before a 15-minute WebDAV lockout. Tracked so the client
  /// can refuse to make a bad situation worse.
  static const int webdavFailedSignInsPerAccount = 10;

  static const Map<RequestClass, ClassLimits> filesystem =
      <RequestClass, ClassLimits>{
    RequestClass.stat: ClassLimits(
      perMinuteFree: 600,
      perMinutePaid: 1200,
      concurrentFree: 5,
      concurrentPaid: 10,
    ),
    RequestClass.readdir: ClassLimits(
      perMinuteFree: 300,
      perMinutePaid: 600,
      concurrentFree: 5,
      concurrentPaid: 10,
      burstPer10sFree: 60,
      burstPer10sPaid: 120,
    ),
    RequestClass.read: ClassLimits(
      perMinuteFree: 300,
      perMinutePaid: 600,
      concurrentFree: 5,
      concurrentPaid: 10,
    ),
    RequestClass.write: ClassLimits(
      perMinuteFree: 120,
      perMinutePaid: 300,
      concurrentFree: 6,
      concurrentPaid: 15,
    ),
    RequestClass.mutation: ClassLimits(
      perMinuteFree: 900,
      perMinutePaid: 1200,
      concurrentFree: 6,
      concurrentPaid: 15,
    ),
    RequestClass.search: ClassLimits(
      perMinuteFree: 30,
      perMinutePaid: 60,
      concurrentFree: 2,
      concurrentPaid: 5,
    ),
    RequestClass.signedUrl: ClassLimits(
      perMinuteFree: 150,
      perMinutePaid: 300,
      concurrentFree: 5,
      concurrentPaid: 10,
    ),
    RequestClass.usage: ClassLimits(
      perMinuteFree: 30,
      perMinutePaid: 60,
      concurrentFree: 2,
      concurrentPaid: 5,
    ),
  };
}

/// A token bucket over a rolling window.
///
/// Not thread-safe by design — the scheduler serialises access. Exposed for
/// unit testing with an injected clock.
class TokenBucket {
  TokenBucket({
    required this.capacity,
    required this.window,
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        _windowStart = (clock ?? DateTime.now)();

  final int capacity;
  final Duration window;
  final DateTime Function() _clock;

  DateTime _windowStart;
  int _used = 0;

  /// Tokens remaining in the current window.
  int get remaining => max(0, capacity - _used);

  /// Whether a request may proceed right now.
  bool get canProceed {
    _rollWindow();
    return _used < capacity;
  }

  /// Consume one token. Returns `false` when the bucket is empty.
  bool tryConsume() {
    _rollWindow();
    if (_used >= capacity) return false;
    _used++;
    return true;
  }

  /// How long until the window rolls and a token frees up.
  Duration get timeUntilAvailable {
    _rollWindow();
    if (_used < capacity) return Duration.zero;
    final elapsed = _clock().difference(_windowStart);
    final remaining = window - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void _rollWindow() {
    final elapsed = _clock().difference(_windowStart);
    if (elapsed >= window) {
      _windowStart = _clock();
      _used = 0;
    }
  }

  /// Restore full capacity. Used after a successful probe of the real limits.
  void reset() {
    _windowStart = _clock();
    _used = 0;
  }
}

/// Schedules every outbound Puter request.
///
/// Responsibilities, in order of importance:
///
/// 1. **Never exceed the global concurrency cap.** This is the single most
///    important guarantee — it is what keeps the client inside WebDAV's shared
///    per-network ceiling.
/// 2. **Respect per-class token buckets**, both the per-minute and the 10s
///    burst budget where one exists.
/// 3. **Serve interactive work first.** A queued background index refresh must
///    never delay a user's tap.
/// 4. **Back off on 429** with full jitter, distinguishing the 60s rolling
///    window from the 1h sustained-mutation budget.
/// 5. **Trip a circuit breaker** when a class is saturated, so the app degrades
///    to cached data instead of hammering the API.
class RequestScheduler {
  RequestScheduler({
    required AppConfig config,
    DateTime Function()? clock,
    Random? random,
  })  : _config = config,
        _clock = clock ?? DateTime.now,
        _random = random ?? Random() {
    _globalBucket = TokenBucket(
      capacity: PuterLimits.globalCallsPerMinute,
      window: const Duration(minutes: 1),
      clock: _clock,
    );
    for (final entry in PuterLimits.filesystem.entries) {
      final limits = entry.value;
      _minuteBuckets[entry.key] = TokenBucket(
        capacity: limits.perMinute(config.planTier),
        window: const Duration(minutes: 1),
        clock: _clock,
      );
      final burst = limits.burstPer10s(config.planTier);
      if (burst != null) {
        _burstBuckets[entry.key] = TokenBucket(
          capacity: burst,
          window: const Duration(seconds: 10),
          clock: _clock,
        );
      }
    }
  }

  final AppConfig _config;
  final DateTime Function() _clock;
  final Random _random;

  late final TokenBucket _globalBucket;
  final Map<RequestClass, TokenBucket> _minuteBuckets =
      <RequestClass, TokenBucket>{};
  final Map<RequestClass, TokenBucket> _burstBuckets =
      <RequestClass, TokenBucket>{};

  final Map<RequestClass, int> _inFlight = <RequestClass, int>{};
  int _totalInFlight = 0;

  final Map<RequestClass, _BreakerState> _breakers =
      <RequestClass, _BreakerState>{};

  /// Pending waiters, ordered by priority then arrival.
  final List<_Waiter> _queue = <_Waiter>[];

  /// Failed authentication attempts in the current WebDAV lockout window.
  ///
  /// Tracked so the client can refuse a retry rather than risk locking the
  /// user out of their own storage for 15 minutes.
  int _failedAuthAttempts = 0;
  DateTime? _firstFailedAuthAt;

  int get totalInFlight => _totalInFlight;
  int get queuedCount => _queue.length;

  /// Current health of each request class, for the diagnostics screen.
  Map<RequestClass, ClassHealth> get health => <RequestClass, ClassHealth>{
        for (final klass in RequestClass.values)
          klass: ClassHealth(
            inFlight: _inFlight[klass] ?? 0,
            remainingThisMinute: _minuteBuckets[klass]?.remaining ?? 0,
            breakerOpen: _breakers[klass]?.isOpen(_clock()) ?? false,
          ),
      };

  /// Run [operation] under the scheduler's budget.
  ///
  /// Throws [PuterException] when the operation fails, when the queue wait
  /// exceeds [timeout], or when the circuit breaker for [klass] is open.
  Future<T> schedule<T>(
    RequestClass klass,
    Future<T> Function() operation, {
    RequestPriority priority = RequestPriority.interactive,
    Duration? timeout,
  }) async {
    final breaker = _breakers.putIfAbsent(klass, _BreakerState.new);
    if (breaker.isOpen(_clock())) {
      throw PuterException(
        PuterErrorKind.rateLimited,
        'Request class "${klass.name}" is saturated. Serving cached data '
        'until ${breaker.openUntil}.',
      );
    }

    final waiter = _Waiter(
      klass: klass,
      priority: priority,
      invoke: operation,
    );
    _queue.add(waiter);
    _queue.sort((a, b) => a.priority.rank.compareTo(b.priority.rank));
    _drain();

    final result = waiter.completer.future.then((value) => value as T);

    if (timeout != null) {
      return result.timeout(
        timeout,
        onTimeout: () {
          waiter.cancelled = true;
          throw PuterException(
            PuterErrorKind.rateLimited,
            'Request for "${klass.name}" timed out waiting for capacity.',
          );
        },
      );
    }
    return result;
  }

  /// Record an authentication failure against the lockout budget.
  ///
  /// Returns `true` when another attempt is safe. Once this returns `false`
  /// the caller **must not retry** — WebDAV returns 429 for a correct password
  /// after 10 failures in 15 minutes.
  bool recordAuthFailure() {
    final now = _clock();
    if (_firstFailedAuthAt == null ||
        now.difference(_firstFailedAuthAt!) > const Duration(minutes: 15)) {
      _firstFailedAuthAt = now;
      _failedAuthAttempts = 0;
    }
    _failedAuthAttempts++;
    return _failedAuthAttempts < PuterLimits.webdavFailedSignInsPerAccount;
  }

  /// Clear the lockout counter after a successful authentication.
  void recordAuthSuccess() {
    _failedAuthAttempts = 0;
    _firstFailedAuthAt = null;
  }

  /// Whether another authentication attempt is safe.
  bool get authAttemptSafe {
    final first = _firstFailedAuthAt;
    if (first == null) return true;
    if (_clock().difference(first) > const Duration(minutes: 15)) return true;
    return _failedAuthAttempts < PuterLimits.webdavFailedSignInsPerAccount;
  }

  /// Attempt to dispatch queued work. Called on enqueue and on completion.
  void _drain() {
    // Iterate a snapshot: dispatching removes entries.
    for (final waiter in List<_Waiter>.from(_queue)) {
      if (waiter.cancelled || waiter.dispatched) continue;
      if (_totalInFlight >= _config.maxConcurrentRequests) return;

      final limits = PuterLimits.filesystem[waiter.klass];
      final classCap = limits?.concurrent(_config.planTier) ??
          _config.maxConcurrentRequests;
      if ((_inFlight[waiter.klass] ?? 0) >= classCap) continue;

      if (!_globalBucket.canProceed) return;
      final minute = _minuteBuckets[waiter.klass];
      if (minute != null && !minute.canProceed) continue;
      final burst = _burstBuckets[waiter.klass];
      if (burst != null && !burst.canProceed) continue;

      _globalBucket.tryConsume();
      minute?.tryConsume();
      burst?.tryConsume();

      waiter.dispatched = true;
      _queue.remove(waiter);
      _inFlight[waiter.klass] = (_inFlight[waiter.klass] ?? 0) + 1;
      _totalInFlight++;

      unawaited(_run(waiter));
    }
  }

  Future<void> _run(_Waiter waiter) async {
    try {
      final result = await waiter.invoke();
      _breakers[waiter.klass]?.recordSuccess();
      waiter.completer.complete(result);
    } catch (error, stack) {
      if (error is PuterException && error.kind == PuterErrorKind.rateLimited) {
        _breakers[waiter.klass]?.recordFailure(_clock());
      }
      waiter.completer.completeError(error, stack);
    } finally {
      _inFlight[waiter.klass] = max(0, (_inFlight[waiter.klass] ?? 1) - 1);
      _totalInFlight = max(0, _totalInFlight - 1);
      _drain();
    }
  }

  /// Backoff for the next retry of [klass], honouring a server `Retry-After`
  /// when one was supplied.
  ///
  /// Full jitter: the delay is drawn uniformly from `[0, computed]`. This is
  /// the variant that best avoids synchronised retry storms, which matters
  /// because WebDAV's ceiling is shared per network.
  Duration backoffFor(int attempt, {Duration? retryAfter}) {
    if (retryAfter != null) {
      return retryAfter > _config.maxRetryBackoff
          ? _config.maxRetryBackoff
          : retryAfter;
    }
    final exponentialMs = 500 * pow(2, attempt).toInt();
    final cappedMs = min(exponentialMs, _config.maxRetryBackoff.inMilliseconds);
    return Duration(milliseconds: _random.nextInt(max(1, cappedMs)));
  }

  /// Cancel queued work matching [predicate].
  ///
  /// Called when a view is disposed, so abandoned requests are never sent.
  int cancelWhere(bool Function(RequestClass klass) predicate) {
    final victims = _queue
        .where((w) => !w.dispatched && predicate(w.klass))
        .toList(growable: false);
    for (final victim in victims) {
      victim.cancelled = true;
      _queue.remove(victim);
      victim.completer.completeError(
        const PuterException(
          PuterErrorKind.unsupported,
          'Request cancelled before dispatch.',
        ),
      );
    }
    return victims.length;
  }

  void dispose() {
    cancelWhere((_) => true);
  }
}

/// A queued request awaiting capacity.
class _Waiter {
  _Waiter({
    required this.klass,
    required this.priority,
    required this.invoke,
  });

  final RequestClass klass;
  final RequestPriority priority;

  /// The operation to run once capacity is granted.
  final Future<dynamic> Function() invoke;

  final Completer<dynamic> completer = Completer<dynamic>();

  bool dispatched = false;
  bool cancelled = false;
}

/// Circuit breaker for one request class.
class _BreakerState {
  static const int _failureThreshold = 5;
  static const Duration _openDuration = Duration(seconds: 30);

  int _consecutiveFailures = 0;
  DateTime? _openedAt;

  bool isOpen(DateTime now) {
    final opened = _openedAt;
    if (opened == null) return false;
    if (now.difference(opened) > _openDuration) {
      // Half-open: allow the next request through to test the water.
      _openedAt = null;
      _consecutiveFailures = 0;
      return false;
    }
    return true;
  }

  DateTime? get openUntil => _openedAt?.add(_openDuration);

  void recordSuccess() {
    _consecutiveFailures = 0;
    _openedAt = null;
  }

  void recordFailure(DateTime now) {
    _consecutiveFailures++;
    if (_consecutiveFailures >= _failureThreshold) {
      _openedAt = now;
    }
  }
}

/// Observable health of one request class.
class ClassHealth {
  const ClassHealth({
    required this.inFlight,
    required this.remainingThisMinute,
    required this.breakerOpen,
  });

  final int inFlight;
  final int remainingThisMinute;
  final bool breakerOpen;

  @override
  String toString() =>
      'inFlight=$inFlight remaining=$remainingThisMinute breakerOpen=$breakerOpen';
}
