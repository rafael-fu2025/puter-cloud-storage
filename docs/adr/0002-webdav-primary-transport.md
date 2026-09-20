# ADR 0002 — WebDAV as the primary transport

**Status:** Accepted (pending Phase 0 verification)
**Date:** 2026-09-20

## Context

There is no official Dart or Flutter SDK for Puter. The client must therefore either bridge the JavaScript SDK or speak a wire protocol directly. Three paths exist:

**A. WebView bridge.** Run `@heyputer/puter.js` inside `flutter_inappwebview` and RPC over the JS bridge.
Documented and complete, but: binary payloads must cross the bridge as base64 (~33% inflation plus message-size limits), progress and cancellation are awkward, the WebView lifecycle is hostile to background transfers, and a headless WebView must stay alive for every operation.

**B. WebDAV.** Puter exposes a WebDAV endpoint. Per the official rate-limits documentation:

> Mount with `-token` username + API token as password → skips per-account ceiling, token revocable from the dashboard without changing account password.

**C. Direct REST.** Puter.js posts `{ interface, method, args }` to a driver-call endpoint with a bearer token. Unpublished and unstable.

The dominant workload is **moving large files** — a personal cloud drive is judged on upload and download reliability. That is precisely where the WebView bridge is weakest.

## Decision

Implement **`WebDavTransport` as the primary transport**, with `WebViewTransport` as a documented fallback and `RestTransport` as a disabled last resort.

All three sit behind one `PuterTransport` interface, and a single **contract test suite runs against every implementation** so the fallbacks cannot silently diverge from the primary.

Rationale:

- **Pure Dart.** No WebView, no JS bridge, no base64. Standard HTTP tooling applies.
- **Native streaming.** `GET` streams to disk with `Range` resume; `PUT` streams from disk. Neither is feasible over a JS bridge without contortion.
- **Real progress and cancellation** come free from the HTTP client.
- **Background transfers work.** WorkManager can run a Dart HTTP client; it cannot reliably keep a WebView alive.
- **Standard operations.** `PROPFIND`, `GET`, `PUT`, `MKCOL`, `MOVE`, `COPY`, `DELETE` cover the entire MVP feature set.
- **Documented and token-compatible.** It is the officially sanctioned non-browser path, and it uses the exact credential ADR 0001 mandates.

The WebView transport is retained because WebDAV covers **only the filesystem**. `fs.space()` (live quota), `fs.getReadURL()` (signed URLs), sharing, and any future AI features are reachable only through the SDK. This is a division of labour, not redundancy.

## Consequences

**Positive**

- The hard part of the app — reliable large-file transfer — is built on the strongest available foundation
- The transport is testable with a local WebDAV server, so most development needs no live account
- Failure of the primary path degrades to a working app rather than a broken one

**Negative**

- **WebDAV's ceiling is per network, not per account: 600 requests/min and 10 concurrent**, shared by everyone on that network. This is the tightest constraint in the system and forces central rate limiting, request coalescing, recursive listing and aggressive caching
- WebDAV returns `207 Multistatus`, which can carry **per-entry errors** — the XML parser must detect partial failure rather than trusting the status code
- Two transports means two code paths and a genuine divergence risk, which the contract test suite exists to contain
- **The fallback transport has no working library.** `flutter_inappwebview`'s latest stable release is 6.1.5, published October 2024 and now roughly two years stale. It does not build under the Gradle 9.1.0 toolchain Flutter 3.44 generates: `flutter_inappwebview_android` 1.1.3 calls `getDefaultProguardFile('proguard-android.txt')`, which Gradle 9 rejects outright. No stable release fixes this; only the unreleased `6.2.0-beta.3` moves. The dependency was therefore removed from `pubspec.yaml` — it was unused, and an unused dependency that breaks the build is not a trade worth making. **Phase 4 must resolve this before the WebView transport can exist**, whether by pinning Gradle 8 for that sub-build, adopting the beta, or replacing the library. The fallback is currently a design intention, not a buildable option.
- **Unverified:** the exact host, path prefix, and which verbs are actually implemented. Phase 0 settles this before any feature work depends on it

**Risk accepted**

If Phase 0 shows WebDAV is unavailable or crippled for the account, the decision inverts: the WebView bridge becomes primary and the transfer engine must be redesigned around base64 chunking. **This is why Phase 0 exists and why no feature work may begin before it completes.**

## Alternatives rejected

- **WebView-first** — wrong shape for the dominant workload; base64 and WebView lifecycle would compromise the core feature
- **Direct REST first** — depends on an unpublished contract that may change without notice
- **A server-side proxy translating REST to WebDAV** — reintroduces infrastructure and puts the developer in custody of the user's token, defeating the point of the project
