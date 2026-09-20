# Architecture

Puter Cloud Storage — Android client, Flutter, token-authenticated.

---

## 1. Design drivers

Five constraints from `docs/puter-api-research.md` drive every decision below.

| Driver | Architectural response |
|---|---|
| Auth is a **long-lived, account-wide token** with no refresh flow | A single token vault; onboarding is paste-and-validate; no auth state machine beyond valid/invalid |
| There is **no Dart SDK**, and the wire protocol is only partly documented | A **transport interface** with three swappable implementations; nothing above the data layer knows how bytes move |
| **Rate limits are tight and per-app**, with a shared 8,000/min account ceiling | A **central rate limiter and request scheduler** — no component issues HTTP on its own |
| **No server-side search**, and listing is the only enumeration primitive | A **local index** in SQLite is a first-class component, not a cache |
| **Transfers are large and failures are non-atomic** | A **persistent transfer queue** with per-file state, resume, and reconciliation |

The organising principle: **the app is a file manager first and a Puter client second.** Puter specifics are confined to one layer.

---

## 2. Layering

```
┌──────────────────────────────────────────────────────────────┐
│  PRESENTATION                                                │
│  Screens · Widgets · Riverpod providers                      │
│  Knows: domain entities. Never knows: HTTP, WebDAV, tokens.   │
├──────────────────────────────────────────────────────────────┤
│  DOMAIN                                                      │
│  Entities (RemoteNode, TransferTask, StorageUsage)           │
│  Repository interfaces · Use cases                           │
│  Pure Dart. Zero dependencies on Flutter or Puter.           │
├──────────────────────────────────────────────────────────────┤
│  DATA                                                        │
│  Repository implementations                                  │
│    ├── FileRepository      (browse, mutate, search)          │
│    ├── TransferRepository  (upload, download, queue)         │
│    ├── AccountRepository   (identity, quota, usage)          │
│    └── IndexRepository     (local metadata index)            │
│  Local: Drift database, DAOs, file staging                   │
├──────────────────────────────────────────────────────────────┤
│  TRANSPORT                          ← the swap point          │
│  abstract PuterTransport                                      │
│    ├── WebDavTransport    primary, pure Dart                  │
│    ├── WebViewTransport   fallback, Puter.js bridge           │
│    └── RestTransport      last resort, undocumented           │
├──────────────────────────────────────────────────────────────┤
│  CORE                                                        │
│  TokenVault · RateLimiter · RequestScheduler · RetryPolicy    │
│  HttpClient · ErrorMapper · Logger · Result types             │
└──────────────────────────────────────────────────────────────┘
```

**Dependency rule:** arrows point downward only. The transport layer is the *only* place that knows Puter exists as a protocol; the domain layer does not import it. Swapping WebDAV for the WebView bridge must require **zero changes** above the data layer.

---

## 3. Authentication and token handling

### 3.1 The flow

OAuth is explicitly out of scope. The user mints a token themselves:

```
First launch
  │
  ├─ Welcome screen: explains what a Puter token is, and that it grants
  │  full account access. Links to puter.com/dashboard#account
  │
  ├─ User pastes token
  │
  ├─ Validation  ── ONE attempt, never a retry loop
  │     │            (10 failed WebDAV sign-ins locks the account for 15 min)
  │     │
  │     ├─ ok    → store in Keystore, load quota, open app root
  │     └─ fail  → clear the field, explain, let the user retry manually
  │
  └─ App ready
```

### 3.2 Validation

Two probes, cheapest first:

1. **WebDAV `PROPFIND /` depth 0** — proves the token authenticates *and* that the WebDAV path works. One request.
2. **`fs.space()` via the WebView transport** — returns `{ capacity, used }`, which the app needs anyway and which settles the quota question.

If WebDAV is unavailable on the account, fall back to the WebView transport for validation and log the degraded mode prominently.

### 3.3 Storage

```dart
abstract class TokenVault {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
  Future<bool> get isUnlocked;
}
```

- Implementation: `flutter_secure_storage` with `AndroidOptions(encryptedSharedPreferences: true)`
- The token is **never** held in a Riverpod provider that could be logged, serialised, or dumped. Providers expose `isAuthenticated` and `PuterIdentity`, never the raw token
- All HTTP goes through a client whose interceptor **redacts** `Authorization` before any log line or error payload
- `401`/`403` → clear the vault, emit an `AuthRevoked` event, route to onboarding. No silent retry

### 3.4 User-facing controls

| Control | Behaviour |
|---|---|
| Reveal token | Requires biometric confirmation (`local_auth`) |
| Replace token | Validates the new one, then swaps atomically |
| Revoke | Clears locally and deep-links to the Puter dashboard to revoke server-side |
| App lock | Optional biometric gate on resume; independent of token validity |

The onboarding copy must state plainly: **this token grants full access to the Puter account; anyone holding it can read and delete your files.** That is the honest framing of an account-scoped, non-refreshable credential.

---

## 4. Transport layer

### 4.1 The interface

Deliberately narrow — it models filesystem operations, not Puter's entire surface:

```dart
abstract class PuterTransport {
  Future<void> authenticate(TokenCredential credential);
  Future<PuterIdentity> identity();

  Future<List<RemoteNode>> list(ListRequest request);
  Future<RemoteNode> stat(String path);
  Future<void> createDirectory(String path);
  Future<void> delete(String path, {bool recursive});
  Future<void> move(String from, String to);
  Future<void> copy(String from, String to);
  Future<void> rename(String path, String newName);

  Future<void> upload(UploadRequest request);
  Future<StreamedFile> download(DownloadRequest request);

  Future<StorageUsage> usage();
  Future<Uri> signedReadUrl(String path, {Duration ttl});

  Future<void> dispose();
}
```

Every method throws `PuterException` with a normalised `PuterErrorKind` — transport-specific errors never leak upward.

### 4.2 `WebDavTransport` — primary

Chosen because it is the **only documented path that yields pure-Dart streaming, Range resume, background transfers and standard HTTP tooling**. See `docs/adr/0002-webdav-primary-transport.md`.

- Auth: HTTP Basic with username `-token` and the API token as password
- Operations map to standard verbs:

| Operation | Verb |
|---|---|
| `list` | `PROPFIND` with `Depth: 1`, parsed from the XML multistatus body |
| `stat` | `PROPFIND` with `Depth: 0` |
| `createDirectory` | `MKCOL` |
| `delete` | `DELETE` |
| `move` / `rename` | `MOVE` with a `Destination` header |
| `copy` | `COPY` with a `Destination` header |
| `download` | `GET` with `Range` for resume |
| `upload` | `PUT` with a streamed body |
| `usage` | `PROPFIND` quota properties, or delegated to the WebView transport |

- XML parsing with `xml`; date parsing must tolerate the WebDAV `getlastmodified` format
- 207 multistatus responses can report **per-entry errors** — the parser must surface partial failures rather than treating 207 as blanket success

**Known ceiling:** 600 requests/min and 10 concurrent, shared per network. This makes batching and caching mandatory, and is the reason the request scheduler exists.

### 4.3 `WebViewTransport` — fallback

Wraps the official SDK. Needed for what WebDAV cannot express: `fs.space()`, `fs.getReadURL()`, sharing, and later AI features.

- `flutter_inappwebview`, loading a bridge page from **local assets over an in-app HTTP origin** (Puter.js requires an HTTP origin, not `file://`)
- The bridge exposes a small RPC surface: `{ id, method, params }` in, `{ id, result | error }` out, correlated by id
- **Binary data does not cross the bridge in bulk.** The bridge returns *metadata and signed URLs*; actual bytes move through Dart's HTTP client. This avoids base64-inflating every file by ~33% and blowing the JS bridge's message limits
- Requires a headless WebView to be alive; must be lazily created and torn down, and must not be relied on for background work

### 4.4 `RestTransport` — last resort

Puter.js internally posts `{ interface, method, args }` to a driver-call endpoint on `api.puter.com` with a bearer token. **This contract is unpublished and may change without notice.** It exists only as an escape hatch, is disabled by default behind a feature flag, and must be deletable without touching any other layer.

### 4.5 Selection and fallback

```
authenticate()
  ├─ try WebDAV PROPFIND ── ok ──→ WebDavTransport (normal mode)
  └─ fail ──→ WebViewTransport (degraded mode)
                │
                └─ surface a persistent banner: "Limited mode"
```

The selected transport is recorded in settings. A **Connectivity & Diagnostics** screen lets the user re-probe on demand — never automatically, because failed probes consume the WebDAV lockout budget.

---

## 5. Rate limiting and request scheduling

### 5.1 Why central

Limits are per user, per app, with a global 8,000 calls/min ceiling on top. A file manager naturally fans out — a grid view of 300 photos could trigger 300 `stat` calls. Without central control the app will rate-limit itself.

### 5.2 The limiter

```dart
class RateLimiter {
  Future<T> schedule<T>(
    RequestClass klass,
    Future<T> Function() operation, {
    Duration? timeout,
  });
}
```

- **Token-bucket per operation class** (`stat`, `readdir`, `read`, `write`, `mutation`, `search`, `signedUrl`), seeded conservatively at the **free-tier** numbers and raised when a paid plan is detected
- A **global concurrency cap** (default 6, safely under every documented ceiling) enforced across all classes
- **Priority queue**: user-initiated actions outrank background work (index refresh, thumbnail warming, auto-backup)
- **Cooperative cancellation** — a queued request whose view has been disposed is dropped rather than sent
- On `429`: honour `Retry-After` when present, otherwise exponential backoff with full jitter, capped at 60s. Distinguish the 60s rolling window from the 1h sustained-budget window by tracking which class tripped
- A circuit breaker opens after repeated `429`s in one class so the app degrades to cached data instead of hammering the API

### 5.3 Request coalescing and caching

- **Deduplicate in-flight requests** by cache key — three widgets asking for the same directory produce one `PROPFIND`
- **Short-TTL response cache** (~5s) for `stat` and `readdir`, invalidated on any mutation in the affected subtree
- **Persistent listing cache** in SQLite for offline browse and instant cold start
- **Prefer one recursive listing over N per-file stats** — the single biggest saving against the WebDAV ceiling

---

## 6. Local data layer

### 6.1 Why it is not optional

No server-side search plus tight rate limits means the client owns enumeration and query. The local database is the mechanism that makes the app feel fast while staying inside the budget.

### 6.2 Schema (Drift / SQLite)

| Table | Purpose |
|---|---|
| `nodes` | Cached metadata: `path` (PK), `parentPath`, `name`, `isDir`, `size`, `modifiedAt`, `mimeType`, `etag`, `indexedAt` |
| `transfer_tasks` | Persistent queue: `id`, `path`, `localPath`, `direction`, `state`, `bytesDone`, `bytesTotal`, `attempts`, `lastError`, `createdAt` |
| `transfer_chunks` | Completed chunk offsets for resumable transfers |
| `sync_roots` | Folders marked for auto-backup with their rules |
| `settings` | Non-secret preferences (sort order, view mode, transport mode) |

Indexes on `parentPath`, `name`, and an FTS5 virtual table over `name` for search.

### 6.3 Indexing strategy

- **Lazy and incremental** — index a directory the first time it is opened, never eagerly crawl the whole account
- **Depth-limited background refresh** for starred or recently-used folders only
- `etag`/`modifiedAt` comparison avoids re-writing unchanged rows
- **Reconcile on mutation** rather than re-listing: after a rename, update the subtree locally and refresh in the background

---

## 7. Transfer engine

### 7.1 Requirements

Large files, unreliable networks, non-atomic server-side operations, hard concurrency caps.

### 7.2 Design

- **Per-file tasks**, never batches — Puter's batch semantics are non-atomic and a partial failure leaves files written
- **Persistent queue** in `transfer_tasks`, so an app kill does not lose the queue
- **Chunked transfers** with recorded offsets (`transfer_chunks`) enabling resume
- **Downloads** stream directly to a staging file via `dart:io`, using `Range` requests to resume. Verified by size before being moved into the final location
- **Uploads** stream from disk; progress is derived from bytes written, not from polling
- **Integrity**: compare size, and content hash where a server-side hash is available
- **Concurrency** governed by the scheduler — never by the queue itself
- **Background execution** via WorkManager (`workmanager` / `flutter_background_service`), with a foreground notification for long transfers. Android will kill unmanaged work; transfers must be declared and resumable
- **Failure policy** per `PuterErrorKind`: transient → backoff and retry; `402`/`413` → block the task and prompt; `401` → halt the queue and re-onboard
- **Storage pre-flight**: before a large upload, compare the file size against `usage().capacity - used` and refuse early with a clear message rather than failing at 99%

### 7.3 The outbox

Transfers started offline are queued, not failed. The outbox is the same `transfer_tasks` table filtered to `state = queued`, surfaced as a first-class screen so the user can see and manage what is pending.

---

## 8. Feature map

### MVP — a credible file manager

| Feature | Notes |
|---|---|
| Token onboarding | Paste, validate once, secure store |
| Browse | `PROPFIND` listing, breadcrumbs, cursor paging |
| Grid / list view | Thumbnails for images, type icons otherwise |
| Sort and filter | Name, modified, size, type — server-side where supported, client-side otherwise |
| Upload | Multi-select, progress, cancel, retry |
| Download | Progress, cancel, resume, open-with |
| Folder operations | Create, rename, delete, move, copy |
| Search | Local FTS over the index |
| Storage meter | `capacity` / `used`, with the quota warning surfaced |
| Pull to refresh, caching, offline browse of cached folders |

### v1 — a good one

| Feature | Notes |
|---|---|
| Offline mode | Full browse and search from cache; queued mutations |
| Photo auto-backup | Camera roll → chosen folder, incremental, background |
| File preview | Images, PDF, text, audio, video |
| Share links | `getReadURL` signed URLs with TTL. **Note: `{ anyone: true }` sharing is paid-plan only** |
| Background transfers | WorkManager, foreground notification, resumable |
| Biometric app lock | Independent of token validity |
| Multi-account | Multiple tokens, per-account index partitions |
| Diagnostics screen | Transport probe, limit status, throughput test |

### v2 — differentiating

| Feature | Notes |
|---|---|
| Media streaming | Progressive playback without full download |
| Archive support | Zip extract and create client-side |
| Responsive layout | Tablet and foldable |
| AI assist | `puter.ai` over selected files — summarise, OCR, describe. Genuinely cheap to add and a real differentiator given the platform provides it |
| Trash and restore | Soft delete with retention |
| Selective sync | Folder-level bidirectional sync with conflict resolution |

---

## 9. Cross-cutting concerns

**Error handling.** One `PuterException` type with a `PuterErrorKind` enum, produced by an `ErrorMapper` at the transport boundary. UI maps kinds to messages; it never parses status codes.

**Observability.** Structured logging with a redaction filter applied to headers and bodies. Transports emit metrics: request counts per class, `429` rate, backoff depth, bytes moved, transfer success rate. These make the rate-limit budget visible instead of mysterious.

**Testing.**

| Level | Scope |
|---|---|
| Unit | `RateLimiter` (virtual clock), `RetryPolicy`, `ErrorMapper`, WebDAV XML parser, path resolution, transfer state machine |
| Contract | One suite run against **every** transport implementation, so the fallbacks cannot silently diverge |
| Widget | Browse, transfer list, onboarding, quota warning |
| Integration | Against a real token, tagged and excluded from CI; run manually before releases |

The **contract test suite is the load-bearing piece** — it is what makes a three-transport design safe rather than aspirational.

**Configuration.** Transport mode, concurrency cap, chunk size, and cache TTLs live in a single `AppConfig`, overridable at runtime for diagnostics. No magic numbers in the code.

---

## 10. Android specifics

- **Permissions**: `INTERNET`, `READ_MEDIA_IMAGES`/`READ_MEDIA_VIDEO` for auto-backup (Android 13+), `POST_NOTIFICATIONS` for transfer progress, `USE_BIOMETRIC` for the app lock
- **Cleartext**: HTTPS only; no cleartext exemption needed
- **Scoped storage**: use SAF (`file_picker`) for user-chosen locations; app-private staging under `getApplicationSupportDirectory()`
- **Network security config**: pin nothing initially — Puter's infrastructure may rotate; revisit once the host set is stable
- **Backup rules**: **exclude the secure-storage entries from Android auto-backup**, or the token may be restored onto another device
- **Min SDK**: 24 for `local_auth` and modern `flutter_secure_storage` behaviour

---

## 11. Risks and mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Quota is 100 MiB, not 310 GB | **Critical** | Verify first, in Phase 0. Everything else is contingent |
| WebDAV is not enabled for the account | High | WebView transport is the designed fallback; Phase 0 proves which works |
| WebDAV's 600/min shared ceiling throttles real use | High | Central limiter, recursive listing, aggressive caching, local index |
| Undocumented API changes | Medium | Transport abstraction; only one layer to fix |
| Token leak via logs or backup | High | Redacting interceptor, Keystore storage, backup exclusion, biometric gate |
| Android kills background transfers | Medium | WorkManager plus resumable chunks; never rely on an in-memory queue |
| Rate-limit lockout from failed probes | Medium | Validate once, never retry automatically, user-initiated re-probe only |
