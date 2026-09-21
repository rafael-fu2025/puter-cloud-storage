# Development Roadmap

Puter Cloud Storage — Android, Flutter.

Sequenced so that **the project's riskiest assumptions are tested before any feature work depends on them**.

---

## Where this stands

| Phase | State |
|---|---|
| 0 — Feasibility spike | Tooling written; **the eight questions still need a live token** |
| 1 — Foundation | **Implemented.** Transport, scheduler, vault, domain, error taxonomy, index |
| 2 — Browse | **Implemented.** Onboarding, listing, jump-to-folder, sorting, folder operations |
| 3 — Transfers | **Implemented.** Per-file queue, resume, cancel/pause/retry, quota pre-flight |
| 4 — Search and MVP | **Implemented.** Device search, settings, theming, attribution, plain-language pass |
| 5 — v1 | Not started |
| 6 — v2 | Not started |

Two Phase 3 exit criteria are **not** met, and the code says so rather than claiming otherwise:
resumable *upload* (`Content-Range` on `PUT` is unverified, so `canResumeUpload` stays `false`), and
WorkManager-backed background transfers with a foreground notification. Both wait on Phase 0.

Phase 4's diagnostics screen was rewritten and moved behind seven taps on the version row. It was a
primary Settings entry that rendered raw `TransportCapabilities` output and cited internal design
documents by number, which is a developer's console rather than a user's screen.

Phase 0 remains the gate it always was. Nothing here proves the backend works, and the quota
question — 100 MiB or 310 GB — still decides whether the product is viable. It needs a real token.

---

## Phase 0 — Feasibility spike

**Gate:** no feature work may begin until this phase completes.

The entire design rests on two unverified assumptions. If either is false, the architecture changes before a single screen is built — which is the whole point of doing this first.

### Deliverables

A throwaway Dart CLI under `tool/spike/` that answers eight questions and prints a report. Not production code; delete it or keep it as a diagnostic.

| # | Question | Method | Why it matters |
|---|---|---|---|
| 1 | **Is the real quota 310 GB or 100 MiB?** | `fs.space()` → `{ capacity, used }` | **Decides whether the project is viable at all.** Docs state 100 MiB free |
| 2 | What is the WebDAV host and path prefix? | `PROPFIND` with `Depth: 0`, `-token` / token basic auth, against candidate hosts | Determines whether the primary transport exists |
| 3 | Which verbs are implemented? | Probe `OPTIONS`, `PROPFIND`, `GET`, `PUT`, `MKCOL`, `MOVE`, `COPY`, `DELETE`, `HEAD` | Determines which features are buildable on WebDAV |
| 4 | Is the filesystem root reachable, or only a subtree? | `PROPFIND /` depth 1 | Determines path strategy |
| 5 | Does `PUT` honour `Content-Range`? | Partial `PUT`, inspect response | Determines whether resumable upload is possible |
| 6 | Are `dav` limits per-account or per-network? | Sustained loop, observe when `429` appears | Determines the safe concurrency cap |
| 7 | Real-world read/write throughput? | Time a 100 MB upload and download | Sets transfer UX expectations |
| 8 | Does a password change invalidate the token? | Dashboard behaviour, documented for the user | Onboarding copy accuracy |

### Exit criteria

- **A written answer to all eight questions**, appended to `docs/puter-api-research.md`
- A **go / no-go decision** on the storage premise, recorded explicitly
- A confirmed transport choice, or a documented reversal of ADR 0002
- Safe concurrency and chunk-size numbers, derived from measurement rather than documentation

### Failure branches

| If | Then |
|---|---|
| Quota is 100 MiB | **Stop.** A personal cloud drive is not viable. Re-scope to a Puter *client* (browse and preview only) or abandon |
| WebDAV is unavailable | Invert ADR 0002: WebView bridge becomes primary, and the transfer engine is redesigned around base64 chunking |
| `Content-Range` unsupported | Drop resumable upload from MVP; keep resume for downloads only |

---

## Phase 1 — Foundation

**Goal:** a skeleton that can authenticate, enforce limits, and be tested.

### Scope

- Project structure, linting (`analysis_options.yaml` with strict rules), CI running `flutter analyze` and `flutter test`
- **`TokenVault`** — `flutter_secure_storage` with Keystore-backed encryption; Android auto-backup exclusion configured
- **`PuterTransport` interface** plus `WebDavTransport`, with XML parsing of `207 Multistatus` **including per-entry error detection**
- **`RateLimiter` and `RequestScheduler`** — token buckets per request class, global concurrency cap, priority queue, `429` backoff with jitter, circuit breaker
- **`ErrorMapper`** — normalise everything to `PuterException` with a `PuterErrorKind`
- **Drift database** with the initial schema and migrations
- **Contract test suite** — one suite, run against every transport
- Redacting log interceptor

### Exit criteria

- Token validation succeeds against the live account in a single attempt
- Contract tests pass against `WebDavTransport` **and** a local WebDAV fixture server
- Rate limiter holds concurrency at the cap under a synthetic burst and never exceeds the bucket
- `flutter analyze` is clean under strict rules; CI is green
- Zero token material appears in logs, and a test asserts this

### Risk retired

Rate limiting and error classification are correct *before* any feature depends on them. These are the hardest things to retrofit.

---

## Phase 2 — Browse

**Goal:** the app opens, lists a real account, and navigates.

### Scope

- Onboarding: welcome, token paste, single validation attempt, error states, degraded-mode notice
- Folder listing with cursor paging, breadcrumbs, pull-to-refresh
- Grid and list views; thumbnails for images, type icons otherwise
- Sorting by name / modified / size / type — server-side where supported, client-side otherwise
- Folder operations: create, rename, delete, move, copy — each followed by a reconciling refresh
- Storage meter, with the quota warning surfaced before it becomes an error
- Local index writes on every listing; instant cold start from cache
- Offline browse of previously visited folders

### Exit criteria

- Navigating a directory tree with 1,000+ entries stays responsive and **never exceeds the request budget** — verified by counting requests, not by feel
- Cold start renders a cached folder before any network call returns
- Every mutation reconciles correctly after a simulated partial failure
- Quota warning appears at 90% of capacity

---

## Phase 3 — Transfers

**Goal:** reliable upload and download of large files. This is the phase the product is judged on.

### Scope

- Persistent transfer queue with per-file state (ADR 0004)
- **Downloads**: streamed to staging via `dart:io`, `Range` resume, size verification before promotion to final location, open-with
- **Uploads**: streamed from disk, chunked with recorded offsets, resume across process death
- Progress, cancel, pause, retry — per file and in aggregate
- Pre-flight quota check on every upload
- Failure policy per error kind; the outbox for offline-started transfers
- WorkManager integration with a foreground notification for long transfers
- Transfer screen: active, queued, failed, completed

### Exit criteria

- A **2 GB upload survives an app kill** and resumes from the last completed chunk
- A download interrupted by airplane mode resumes and verifies correctly
- Forcing `413` mid-batch blocks only the affected file; the rest complete and the failure is attributed to the right file
- Killing the process during a transfer loses no queue state
- Concurrency never exceeds the measured safe cap

### Risk retired

The two hardest engineering problems — resumability and non-atomic failure — are solved and tested here.

---

## Phase 4 — Search and MVP release

**Goal:** a file manager worth using daily.

### Scope

- FTS5 search over the local index, with as-you-type results and match highlighting
- Search scoping: current folder vs whole index
- Background incremental index refresh for recently used folders
- Settings: sort defaults, view mode, cache management, transport mode, diagnostics
- Diagnostics screen: transport probe, rate-limit status, throughput test
- Onboarding polish; empty states; error states; accessibility pass
- Material 3 theming, dark and light
- **Puter attribution** (`developer.puter.com`) in About and README
- Release build, signed APK, store listing assets

### Exit criteria

**MVP ships.** Search returns results in under 200 ms from the local index with no network call. A new user can go from install to browsing their files without external documentation.

---

## Phase 5 — v1

**Goal:** the app is genuinely good, not merely functional.

| Feature | Notes |
|---|---|
| **Photo auto-backup** | Camera roll → chosen folder; incremental, dedup by hash; background; the flagship v1 feature |
| **File preview** | Images, PDF, text, audio, video |
| **Share links** | Signed `getReadURL` URLs with TTL. **`{ anyone: true }` sharing is paid-plan only** — surface this honestly |
| **Offline mode** | Queued mutations replayed on reconnect, with conflict reporting |
| **Biometric app lock** | Independent of token validity |
| **Multi-account** | Multiple tokens, per-account index partitions |
| **Transfer scheduling** | Wi-Fi-only, charging-only, quiet hours |
| **Tablet layout** | Two-pane master/detail |

### Exit criteria

- Auto-backup runs reliably for a week without duplication or data loss
- Offline mutations replay correctly, and conflicts are reported rather than silently resolved
- Reinstall + token restore recovers full access without reconfiguration

---

## Phase 6 — v2

**Goal:** capabilities a generic client cannot match.

| Feature | Notes |
|---|---|
| **AI assist** | `puter.ai` over selected files — summarise, OCR, describe. Cheap to add given the platform provides it, and a genuine differentiator |
| Media streaming | Progressive playback without a full download |
| Archive support | Zip extract and create, client-side |
| Trash and restore | Soft delete with retention |
| Selective sync | Folder-level bidirectional sync with conflict resolution |
| Desktop client | Reuse the Dart core; only the UI layer changes |

---

## Cross-cutting workstreams

These run through every phase rather than belonging to one.

| Workstream | Cadence |
|---|---|
| **Testing** | Unit tests with every feature; contract tests whenever a transport changes; manual live-account pass before each release |
| **Observability** | Structured logs, redaction verified continuously; request counts per class, `429` rate, backoff depth, transfer success rate |
| **Security review** | Token storage, log redaction, backup exclusion, and dependency audit — re-checked at each phase boundary |
| **Documentation** | Research doc, architecture, ADRs and README kept current as decisions change, not after |

---

## Risk register

| # | Risk | Severity | Likelihood | Mitigation | Owner phase |
|---|---|---|---|---|---|
| 1 | Quota is 100 MiB, not 310 GB | **Critical** | Unknown | **Phase 0 gate.** Re-scope if false | 0 |
| 2 | WebDAV unavailable or crippled | High | Medium | WebView fallback designed in; contract tests keep it honest | 0 |
| 3 | 600 req/min shared WebDAV ceiling throttles real use | High | High | Central limiter, recursive listing, local index, request coalescing | 1, 2 |
| 4 | Token leak via logs or Android backup | High | Low | Redacting interceptor, Keystore, backup exclusion, biometric gate, asserted by test | 1 |
| 5 | Undocumented API changes | Medium | Medium | Transport abstraction — one layer to fix | ongoing |
| 6 | Android kills background transfers | Medium | High | WorkManager + resumable chunks; never trust an in-memory queue | 3 |
| 7 | Non-atomic uploads corrupt client state | Medium | High | Per-file tasks + mandatory reconciling refresh | 3 |
| 8 | Rate-limit lockout from failed probes | Medium | Low | Validate once; never auto-retry; user-initiated re-probe only | 1 |
| 9 | Egress metering surprises the user | Medium | Medium | Show `getMonthlyUsage()`; cache aggressively; never re-download gratuitously | 4 |
| 10 | Cache staleness misleads the user | Low | High | TTLs, refresh-on-open, reconcile-after-mutation | 2 |

---

## Sequencing rationale

Phase 0 exists because two assumptions — quota and WebDAV — could invalidate the design, and both are cheap to test and expensive to discover late.

Phase 1 comes before any UI because **rate limiting and error classification are the hardest things to retrofit**. Building them first means every subsequent feature inherits correctness instead of acquiring it later.

Phase 3 is the centre of gravity. A cloud storage app is judged on whether files move reliably; everything before it is scaffolding for that, and everything after it is refinement.
