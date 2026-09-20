# Puter Cloud Storage

An Android file manager that uses **Puter** as its storage backend, built with Flutter.

Your files stay in your own Puter account. This app is a client, not a service — it holds no
servers, no database, and no copy of your data. It authenticates with a Puter **auth token** you
create yourself, so there is no OAuth popup and no password to share.

---

## Status

**Phase 1 — foundation.** The transport layer, request scheduler, token vault, domain model and
error taxonomy are implemented and tested. The app compiles and packages for release; feature
screens arrive in Phases 2–4.

See [`docs/roadmap.md`](docs/roadmap.md) for the full plan.

---

## The one thing to know before starting

> **Puter's free tier provides 100 MiB of storage, not hundreds of gigabytes.**
>
> Official documentation states the free filesystem quota is **100 MiB**, with paid plans adding
> more. If you are expecting ~310 GB, verify it against your own account before building on this
> premise — the answer changes what the app can be.
>
> Run the Phase 0 spike (below) or open the Puter web UI and check.

This is not a footnote. It is the project's critical unknown, and it is the first thing
[`docs/roadmap.md`](docs/roadmap.md) sets out to settle.

---

## Documentation

| Document | What it covers |
|---|---|
| [`docs/puter-api-research.md`](docs/puter-api-research.md) | Puter's storage API, auth tokens, endpoints, **full rate-limit tables**, error codes, and every limitation that affects this build |
| [`docs/architecture.md`](docs/architecture.md) | Layering, transport design, token handling, rate limiting, local index, transfer engine |
| [`docs/roadmap.md`](docs/roadmap.md) | Six phases with exit criteria, plus the risk register |
| [`docs/security.md`](docs/security.md) | Threat model for an account-wide credential, and the verification checklist |
| [`docs/build-assessment.md`](docs/build-assessment.md) | What the toolchain can build, verified output sizes, and the five defects that only a real build exposed |
| [`docs/adr/`](docs/adr/) | The four decisions that shape everything else |

The ADRs are worth reading if you only read one thing. They record *why* the architecture looks
the way it does, including the alternatives that were rejected:

- [0001 — Auth token over OAuth](docs/adr/0001-auth-token-over-oauth.md)
- [0002 — WebDAV as the primary transport](docs/adr/0002-webdav-primary-transport.md)
- [0003 — A local SQLite index is core, not a cache](docs/adr/0003-local-sqlite-index.md)
- [0004 — Per-file transfer tasks, never batches](docs/adr/0004-per-file-transfer-tasks.md)

---

## Architecture at a glance

```
Presentation   Flutter screens, Riverpod
     │
Domain         RemoteNode, TransferTask, StorageUsage — pure Dart
     │
Data           Repositories · Drift database · local index
     │
Transport      ┌──────────────────────────────────────────┐
               │ abstract PuterTransport                  │
               │   WebDavTransport    primary, pure Dart  │
               │   WebViewTransport   Puter.js fallback   │
               │   RestTransport      disabled by default │
               └──────────────────────────────────────────┘
     │
Core           TokenVault · RequestScheduler · RetryPolicy · ErrorMapper
```

Three decisions carry most of the weight:

**WebDAV is the primary transport.** Puter exposes a WebDAV endpoint that accepts the API token as
the password (username `-token`). It is the only documented path that gives pure-Dart streaming,
`Range` resume and background transfers — all essential for moving large files. A WebView bridge
wraps the official SDK for what WebDAV cannot express, such as live quota and signed URLs.

**All traffic goes through one scheduler.** Rate limits are per-user-per-app, with a global
8,000 calls/min account ceiling — and WebDAV adds a **600 requests/min, 10 concurrent** ceiling
shared *per network*. Without central control the app rate-limits itself during ordinary browsing.

**Every transfer carries its own state.** Puter's upload API is not atomic: a partial failure
leaves earlier files written and is never rolled back. Transfers are therefore per-file tasks with
persistent state, not batches.

---

## Quick start

### Prerequisites

- Flutter 3.44+ (Dart 3.12+)
- An Android device or emulator
- A Puter account

### Get a Puter auth token

1. Sign in at [puter.com/dashboard#account](https://puter.com/dashboard#account)
2. Find the **API token** section
3. Click **Create token** — it is copied to your clipboard
4. Store it somewhere safe, as you would a password

The token is **account-wide and long-lived**. Anyone holding it can read, modify and delete every
file in your account. There is no narrower scope and no refresh flow; when you want it gone, revoke
it from the same dashboard page.

### Run the Phase 0 spike first

Before writing any feature code, confirm the assumptions the architecture rests on:

```bash
PUTER_AUTH_TOKEN=<your-token> dart run tool/spike/phase0_spike.dart
```

It answers the eight questions in [`docs/roadmap.md`](docs/roadmap.md), including the storage quota
and whether WebDAV is available. It attempts each host **once** and never retries, because ten
failed sign-ins lock the account out of WebDAV for 15 minutes.

### Run the app

```bash
flutter pub get
flutter run
```

### Build

```bash
# Sideload — 15.4 MB for arm64-v8a, versus 43.8 MB for the fat APK
flutter build apk --release --split-per-abi

# Play Store
flutter build appbundle --release
```

The release APK is **98.8% native libraries**. The app's own code is 0.8 MB, so splitting per ABI
is worth 2.8× on the delivered download. Budget ~11 GB of disk for a full build cycle and keep at
least 15 GB free.

Sizes, the toolchain inventory, and the constraints worth knowing before you build are in
[`docs/build-assessment.md`](docs/build-assessment.md).

### Test

```bash
flutter analyze                     # static analysis, strict rules
flutter test                        # widget and unit tests

# Verification that needs no Puter account, no network, and no test framework
dart run tool/verify/verify_core.dart        # 21 checks — error taxonomy, scheduler, limits
dart run tool/verify/verify_transport.dart   # 64 checks — WebDAV transport against a live fixture
```

The two `verify_*` scripts exist because `flutter test` and `dart test` both fail in some
environments — the former on the WebSocket upgrade to `flutter_tester`, the latter on the
native-assets build hook. They depend on nothing but the Dart VM, so they always run.

`verify_transport.dart` is the more interesting one. It starts
[`test/support/webdav_fixture.dart`](test/support/webdav_fixture.dart) — a real HTTP server on
loopback — and drives the transport against it over actual sockets. That catches things a mock
never would: `207` responses carrying per-entry failures, `413` quota rejection, `429` handling,
`412` overwrite refusal, `Range` resume, and a server that ignores `Range` and would otherwise
corrupt a resumed download.

It found four real defects the first time it ran.

---

## Project layout

```
lib/
├── app/                    Composition root, shell, providers
├── core/
│   ├── config/             AppConfig, endpoints, plan tiers
│   ├── error/              PuterException, error taxonomy, ErrorMapper
│   ├── network/            RequestScheduler, token buckets, backoff
│   └── security/           TokenVault, credential redaction
├── data/
│   └── transport/          PuterTransport + WebDAV implementation
├── domain/entities/        RemoteNode, StorageUsage, TransferTask
└── features/               Screens, added in Phases 2–4
docs/                       Research, architecture, roadmap, security, ADRs
tool/spike/                 Phase 0 feasibility diagnostic
tool/verify/                Dependency-free verification (core + transport)
test/support/               WebDAV fixture server for transport tests
test/                       Unit, widget and contract tests
```

---

## Rate limits, briefly

Three independent gates apply to every call. All must pass.

| Mechanism | Bounds | Failure |
|---|---|---|
| Usage credit | What usage costs, monthly, no rollover | `402 insufficient_funds` |
| Rate limit | Requests per rolling window | `429 too_many_requests` |
| Storage quota | Bytes kept | `413 storage_limit_reached` |

Filesystem limits on the **free** tier, per minute:

| Operation | Free | Paid |
|---|---|---|
| `stat` | 600 | 1,200 |
| `readdir` | 300 (60 per 10s burst) | 600 |
| `read` | 300 | 600 |
| `write` | 120 | 300 |
| Mutations | 900 | 1,200 |
| Search | 30 | 60 |

Plus a **global 8,000 calls/min per account**, and WebDAV's **600/min and 10 concurrent per
network**. Full tables in [`docs/puter-api-research.md`](docs/puter-api-research.md) §5.

Two consequences worth internalising:

- **`402` and `413` are not retryable.** Retrying changes nothing; the user must act.
- **Search has no server-side implementation.** It is served from a local index, which is why the
  database is a core component rather than a cache.

---

## Security

The auth token is a root credential for the whole account. The app treats it accordingly:

- Stored in `flutter_secure_storage`, backed by the Android Keystore
- Never logged, never rendered, never in an error payload — enforced by a redacting interceptor
  and covered by tests
- Excluded from Android auto-backup, so it cannot be restored onto another device
- Optional biometric lock, independent of token validity
- On `401`: clear and re-onboard. **Never retry** — a retry loop can trip WebDAV's lockout and lock
  you out of your own storage for 15 minutes

Full threat model and verification checklist in [`docs/security.md`](docs/security.md).

---

## Attribution

Built on [Puter](https://developer.puter.com). Apps using Puter.js are expected to carry a link
back to the platform, and this one does.

---

## Licence

Not yet chosen. Add one before publishing.
