# ADR 0003 — A local SQLite index is a core component, not a cache

**Status:** Accepted
**Date:** 2026-09-20

## Context

Three facts from the platform research force this decision:

1. **There is no server-side search.** The SDK documents no `fs.search()` method, despite a search rate-limit bucket existing (30/min free, 60/min paid). Search appears reachable only through the raw driver interface, which is undocumented.
2. **Rate limits are tight.** `readdir` allows 300/min on free and 600/min paid, with a burst of 60 per 10s. WebDAV is worse: 600 requests/min **shared per network**, 10 concurrent.
3. **Listing is the only enumeration primitive.** Discovering what exists means walking the tree with `readdir`, paying a request per directory.

A naive file manager re-lists on every navigation and searches by crawling. Against these limits that is not merely slow — it will trip `429` during ordinary use, and the 1h sustained-mutation budget makes recovery slow.

## Decision

Treat a **local SQLite database (Drift)** as a first-class component of the data layer, holding:

- **Cached node metadata** — `path`, `parentPath`, `name`, `isDir`, `size`, `modifiedAt`, `mimeType`, `etag`, `indexedAt`
- **An FTS5 full-text index** over `name` (and later extracted text), which is what makes search possible at all
- **The transfer queue and chunk offsets**, so transfers survive process death
- **Sync roots and settings**

And adopt these rules:

- **Lazy, incremental indexing** — index a directory the first time it is opened. Never eagerly crawl the whole account
- **Serve reads from cache first**, refresh in the background, and reconcile on `etag`/`modifiedAt` rather than re-listing wholesale
- **Reconcile mutations locally** — after a rename, update the affected subtree in the database immediately and refresh lazily, instead of re-listing to discover what changed
- **Prefer one recursive listing over N per-file `stat` calls.** This is the single largest saving against the WebDAV ceiling
- **Bound the cache** — evict by age and size, never unbounded growth

## Consequences

**Positive**

- Search becomes possible — impossible otherwise, given no server-side search
- Cold start is instant and navigation is immediate, because the first paint comes from disk
- Offline browsing of previously visited folders falls out for free, and is the foundation of the v1 offline mode
- Request volume against the rate limiter drops by an order of magnitude, which is what keeps the app inside the WebDAV ceiling
- Thumbnails, previews and metadata have somewhere to live

**Negative**

- **Cache invalidation is now a real correctness problem.** The client can display stale state if another device or the Puter web UI changes files. Mitigated by refresh-on-open, TTLs on cached listings, and explicit reconcile-after-mutation
- A schema is a long-lived commitment requiring migrations
- The index can drift from reality after partial failures. `fs.upload` is non-atomic and leaves earlier files written, so the reconciling refresh after any multi-file operation is mandatory, not optional
- More moving parts than a stateless client, and more to test

## Alternatives rejected

- **Stateless, always-fetch** — simplest to write, but trips rate limits during normal browsing and makes search impossible
- **In-memory cache only** — survives neither process death nor offline use, and does not solve search
- **Server-side search via the undocumented driver interface** — depends on an unpublished contract, and the 30/min free ceiling is too low to power a search-as-you-type UI regardless
