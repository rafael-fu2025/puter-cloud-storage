# Puter Platform Research

Reference material for building an Android client against Puter as a storage backend.

**Research date:** 2026-09-20
**Primary sources:** `docs.puter.com` (Puter.js reference, Rate Limits and Quotas), `developer.puter.com` (auth-token tutorial, Node.js guide), `github.com/HeyPuter/puter`.

---

## 1. Executive summary

Puter is an open-source "internet computer" that exposes a real user filesystem, a key-value store, static hosting, serverless workers and an AI gateway. For this project only two capabilities matter: **authentication by long-lived account token** and the **filesystem**.

Five findings shape the entire architecture:

| # | Finding | Consequence |
|---|---|---|
| 1 | Puter has **no OAuth-only requirement** — an account-scoped **API token** can be created in the dashboard and used from non-browser clients | The stated constraint is satisfiable, and the token is the *only* credential the app needs |
| 2 | There is **no official Dart/Flutter SDK** | We must either bridge the JS SDK through a WebView or speak a wire protocol directly |
| 3 | Puter exposes a **WebDAV endpoint that accepts the API token as the password** (username `-token`) | A **pure-Dart transport is possible with no WebView and no reverse-engineered endpoints** — this is the recommended primary path |
| 4 | Limits are **per user, per app**, and there is a **global 8,000 calls/min** account ceiling plus a **600 req/min / 10 concurrent** WebDAV ceiling | The client needs a central rate limiter and request scheduler, not ad-hoc HTTP calls |
| 5 | Free accounts get **100 MiB** of filesystem quota, not hundreds of GB | **The "310 GB" premise must be verified against the live account before committing to the product framing** — see §7 |

---

## 2. Authentication

### 2.1 The token model

Puter.js in a browser performs an interactive popup sign-in (`puter.auth.signIn()`) and manages credentials internally. That flow is **not usable** for this project and is explicitly out of scope.

For non-browser clients Puter provides an **API token**:

1. Sign in at `puter.com/dashboard#account`
2. Locate the **API token** section
3. Click **Create token**
4. The token is copied to the clipboard — store it immediately; treat it as a password

The token is a **credential tied to the account** that "you can drop into any non-browser environment to make calls on your behalf". It is:

- **Account-scoped, not app-scoped** — it grants the full authority of the account owner
- **Long-lived** — no documented expiry; it remains valid until revoked from the dashboard
- **Non-refreshable** — there is no refresh-token flow; when it dies the user must mint a new one
- **Bearer-style** — passed as `Authorization: Bearer <token>` to the API, or as the WebDAV password

### 2.2 Using the token

**Node.js / bundler path** (documented, official):

```javascript
import { init } from "@heyputer/puter.js/src/init.cjs";

const puter = init(process.env.PUTER_AUTH_TOKEN);
await puter.fs.write("hello.txt", "Hello, world!");
```

Requires **Node.js 24+**. The same `init(token)` entry point exposes the full API surface — `fs`, `kv`, `ai`, `hosting`, `workers`.

**OpenAI-compatible path** (documented, but irrelevant here):

```javascript
const client = new OpenAI({
  baseURL: "https://api.puter.com/puterai/openai/v1/",
  apiKey: process.env.PUTER_AUTH_TOKEN,
});
```

Note: the OpenAI/Anthropic-compatible endpoints **require a paid plan**; a free account receives `402 subscription_required`. This only affects AI features, not the filesystem.

**WebDAV path** (documented in the rate-limits page, and the reason this project is tractable):

> Mount with `-token` username + API token as password → **skips per-account ceiling**, token revocable from the dashboard without changing account password.

### 2.3 Security implications for the client

Because the token is account-wide and long-lived, the app is holding a **root credential**:

- Store it in `flutter_secure_storage` (Android Keystore-backed, AES-GCM), never in `SharedPreferences` or plain files
- Never write it to logs, crash reports, analytics, or error payloads — add a redacting interceptor
- Never commit it; keep it out of `.env` files that ship in the repo
- Provide explicit **revoke & replace** in Settings, and detect `401` to force re-onboarding
- Gate the app (or at least token reveal/export) behind optional biometrics via `local_auth`
- Warn the user plainly during onboarding that the token grants full account access

---

## 3. Filesystem API surface

All methods return promises and are available on the `websites`, `apps`, `nodejs` and `workers` platforms.

### 3.1 Core operations

| Method | Signature | Notes |
|---|---|---|
| `fs.write` | `(path, data?, options?)` | `data`: `String \| File \| Blob \| ArrayBuffer \| TypedArray`. Options: `overwrite` (default `true`), `dedupeName` (default `false`), `createMissingParents` (default `false`). Returns `FSItem` |
| `fs.read` | `(path)` | Returns a `Blob` — call `.text()` for text |
| `fs.readdir` | `(path \| options)` | See §3.2 |
| `fs.mkdir` | `(path, options?)` | Directory creation |
| `fs.upload` | `(items, dirPath?, options?)` | See §3.3 |
| `fs.rename` | `(path, newName)` | Rename in place |
| `fs.move` | `(path, destPath)` | Move; supports `createMissingParents` |
| `fs.copy` | `(path, destPath)` | Copy |
| `fs.delete` | `(path, options?)` | Delete file or directory |
| `fs.stat` | `(path, options?)` | Metadata; `returnShares` spends the sharing read budget |
| `fs.getReadURL` | `(path)` | **Signed temporary URL** — lets anyone read one file |
| `fs.space` | `()` | Returns `{ capacity, used }` in bytes, live |
| `fs.share` / `fs.unshare` | | Sharing; `{ anyone: true }` is **paid-plan only** |
| `fs.getShares` / `fs.listShared` | | Share introspection |
| `fs.getShareLink` | | Link that opens a file in a Puter app |

Notably **absent**: there is no documented `fs.search()` method in the SDK index, yet a `Search` rate-limit bucket exists (60/min paid, 30/min free, 10/min anonymous). Search appears reachable only through the raw driver interface, so **client-side indexing is the reliable approach**.

### 3.2 `fs.readdir` — the listing workhorse

```js
puter.fs.readdir(path)
puter.fs.readdir(path, options)
puter.fs.readdir(options)
```

Options:

- `path` — required when options are the only argument
- `uid` — read a directory by UID instead of path
- `limit`, `offset` — windowed paging (`offset` is discouraged)
- `cursor` — **preferred paging**: pass `null` for the first page, then the returned `cursor`. The cursor pins the sort order, so later pages must not change `sortBy`/`sortOrder`
- `includeTotal` — adds a `total` count (paginated responses only)
- `sortBy` — `name` (default) | `modified` | `type` | `size`
- `sortOrder` — `asc` (default) | `desc`
- `recursive` + `depth` — subtree listing; with `recursive`, `name` sorts by full path so each directory stays together
- `stream` — returns an **async iterator of pages** instead of a promise; ideal for large directories. Cannot combine with `offset`

Return shape:

- Without pagination params → a plain **array** of `FSItem` (fetched page-by-page under the hood)
- With `cursor` (even `null`) or `includeTotal` → `{ items, cursor?, total? }`
- With `stream: true` → async iterator of those page objects

Each `FSItem` carries `is_shared`: `true`/`false`/`null` (the last for items not owned by you). Only a share on the item itself counts — children of a shared folder report `false`.

**Client implication:** use `cursor` paging with `limit` around 200, and `stream: true` for recursive scans. This maps cleanly onto an infinite-scroll list and onto an incremental local index.

### 3.3 `fs.upload` — the transfer path

```js
puter.fs.upload(items, dirPath, options)
```

- `items` — `FileList`, `InputFileList`, `Array<File>`, or `Array<Blob>`
- Options: `overwrite` (default **`false`**), `dedupeName` (default `true`, ignored when overwriting), `createMissingParents` (default `false`), `generateThumbnails` (default `false`), `thumbnailGenerator`, `thumbnail`
- Callbacks: `init(operationId, xhr)`, `start()`, `progress(operationId, percent)`, `abort(operationId)`
- Returns a single `FSItem` for one item, an array for many

**Failure semantics matter for the transfer queue:**

- If *any* part fails the promise **rejects** — it never resolves to a mixed result
- Rejection carries `message`, plus `failedItems[]` (each with `path`, `message`, and where available `code`/`status`) when individual items failed
- A partial failure is **not rolled back** — items already written stay written
- When all failures share a cause, `code`/`status` are hoisted onto the rejection itself. Quota exhaustion is the common case: `code: 'storage_limit_reached'`, `status: 413`
- Legacy-endpoint fallbacks report `batch_upload_failed`, `batch_upload_partially_failed` (with `failedCount`/`totalCount`/`results`), or `batch_upload_no_results`

**Directory uploads** rely on the signed batch-write endpoint. Against a backend without one, the SDK falls back to an older batch endpoint that **cannot create directories**, and the upload rejects with `batch_upload_failed` — the directories must then be made with `fs.mkdir()` first.

**Client implication:** the upload queue must be **per-file**, not per-batch, so that one failure does not obscure the state of the others. Never assume an upload batch is atomic.

### 3.4 Path semantics

- A relative path resolves against the **app's root directory** (app-scoped sandbox)
- An absolute path addresses the user's filesystem directly
- Because this app is a *storage client*, it should use **absolute paths** rooted at the user's home so the same folders are visible in Puter's own desktop UI

---

## 4. Access paths from Flutter

### 4.1 Comparison

| | **WebDAV** | **WebView + Puter.js** | **Direct REST** |
|---|---|---|---|
| Status | Documented | Documented | **Undocumented** |
| Language | Pure Dart | JS in WebView, bridged | Pure Dart |
| Auth | `-token` / API token | `init(token)` | `Bearer <token>` |
| Binary transfer | Native streaming, Range resume | Base64 over JS bridge — costly | Native streaming |
| Progress/cancel | Native | Awkward | Native |
| Background transfers | Yes | Fragile (WebView lifecycle) | Yes |
| Stability | Standard protocol | Stable | **Fragile, may change** |
| Coverage | Filesystem only | Full API (kv, ai, hosting) | Full API |

### 4.2 Recommendation

**WebDAV is the primary transport.** It is the only documented path that gives pure Dart native streaming, resume, background transfers and standard tooling — all of which are essential for a file-manager app moving multi-hundred-MB files.

**A WebView bridge is the secondary transport**, needed for capabilities WebDAV cannot express: signed read URLs (`fs.getReadURL`), the live quota reading (`fs.space`), share management, and — later — AI features.

**Direct REST is a last resort.** Puter.js internally posts `{ interface, method, args }` to a driver-call endpoint on `api.puter.com` with a bearer token, but this contract is not published and must not be depended on. If used at all, isolate it behind the transport interface so it can be deleted.

### 4.3 The transport abstraction

Because this choice is the highest-risk decision in the project, the design must make it **swappable and testable**. See `docs/adr/0002-webdav-primary-transport.md`.

---

## 5. Rate limits and quotas

Three **independent** mechanisms gate every call. All three must pass:

| Mechanism | Bounds | Refills | Failure |
|---|---|---|---|
| Usage credit | What usage *costs* | Monthly, per plan, **no rollover** | `402 insufficient_funds` |
| Rate limit | Requests per window (10s / 1min / 1h) | Rolling window | `429 too_many_requests` |
| Storage quota | Bytes kept in the filesystem | Never — user deletes or upgrades | `413 storage_limit_reached` |

Credit balance does **not** buy rate-limit headroom, and an empty balance does **not** block free metadata reads.

### 5.1 Scope

- Every limit applies **per user, per app** — each app gets its own bucket
- Each **worker** gets an additional bucket on top of that
- A **global per-account budget of 8,000 driver calls/min** sits in front of everything. A `429` from it means the client is looping

### 5.2 Filesystem limits

Per minute unless stated. Format is **paid / free / anonymous**.

| Operation | Paid | Free | Anonymous |
|---|---|---|---|
| `stat` | 1,200 | 600 | 300 |
| `readdir` | 600 | 300 | 120 |
| `readdir` burst (per 10s) | 120 | 60 | 30 |
| `read` | 600 | 300 | 120 |
| `write` | 300 | 120 | 30 |
| Multipart upload calls | 2,400 | 1,200 | 600 |
| Mutations (mkdir/rename/delete/move/copy) | 1,200 | 900 | 600 |
| Mutations, sustained (per hour) | 6,000 | 3,000 | 1,800 |
| Search | 60 | 30 | 10 |
| `space()` | 60 | 30 | 15 |
| Sign a URL | 300 | 150 | 60 |

**Filesystem concurrency:**

| | Paid | Free | Anonymous |
|---|---|---|---|
| `read` | 10 | 5 | 3 |
| `write` | 15 | 6 | 3 |
| Search | 5 | 2 | 2 |

**Signed-URL routes** are bounded **per network** rather than per session: 3,000 reads/min, 600 writes/min, 60 concurrent.

**WebDAV** authenticates per request, so it is bounded **per network** too: **600 requests/min** and **10 concurrent** — a single ceiling shared by everyone on that network.

### 5.3 WebDAV failed sign-in lockout

| Limit | Per 15 minutes |
|---|---|
| Failed sign-ins for one account | 10 |
| Failed sign-ins from one address | 50 |

Exceeding either returns `429` **for the correct password too**. Ten wrong attempts lock the account out of WebDAV for the window. This applies **only to `dav`** — desktop, API and `puter.auth` keep working.

**Client implication:** a token-validation loop that retries on failure can lock the user out. Validation must be attempted **once**, with the failure surfaced to the user, and any retry must be explicit and user-initiated.

### 5.4 Other limits relevant to later phases

- **KV store:** key 1 KB, value 400 KB; `get`/`set` 400 per 10s (all tiers); `list` 120/min free, 240/min paid; 15 concurrent free, 30 paid
- **Sharing:** 60 `share`/`revoke` per minute, 500/day; 200 new shares/day; 10 recipients and 50 items per request; 600 share-listing reads/min
- **`{ anyone: true }` link sharing is paid-plan only**, and the link stops working if the owner's plan lapses. Named-person and team sharing is open to all tiers
- **AI (if added later):** 30 requests/10s and 3 concurrent on free; the OpenAI-compatible endpoint requires a paid plan
- **Events:** broadcast delivery 10 µ¢/event, single 100 µ¢/event; idle subscriptions are free

### 5.5 Storage quota — read this carefully

> Every account has a byte quota for the filesystem: **100 MiB free**; paid plans add more.

- Storage counts what the user **keeps**, not what is transferred
- Deleting frees space **immediately**
- At the limit, writes fail `413 storage_limit_reached` while **reads keep working**
- `fs.space()` returns `{ capacity, used }` live

**This directly contradicts the 310 GB premise.** See §7.

---

## 6. Error handling contract

Errors return JSON shaped `{ "error": …, "message": …, "code": … }`.

| Status | `code` | Meaning | Correct client response |
|---|---|---|---|
| `429` | `too_many_requests` | Rate or concurrency limit | Back off and retry. Window is at most 60s, or 1h for the sustained FS budget |
| `402` | `insufficient_funds` | Monthly credit spent | Surface upgrade prompt; **retrying changes nothing** |
| `402` | `subscription_required` | Endpoint is paid-plan only | Surface upgrade prompt; **retrying changes nothing** |
| `413` | `storage_limit_reached` | Storage quota reached | Prompt to delete or upgrade; **retrying changes nothing** |

The Puter.js SDK automatically raises an upgrade dialog for the three money-shaped errors, but **the promise still rejects**. Any client writing files must handle `storage_limit_reached` explicitly, and anything that loops must treat `429` as a back-off signal.

### 6.1 Classifying failures for retry

| Class | Codes | Policy |
|---|---|---|
| **Transient** | `429`, 5xx, timeouts, connection resets | Exponential backoff with jitter; honour `Retry-After` |
| **Permanent — user action** | `402`, `413` | Do not retry. Block the queue item, prompt, keep the file in the local outbox |
| **Permanent — auth** | `401`, `403` | Do not retry. Force re-onboarding |
| **Permanent — request** | `400`, `404`, name collisions | Do not retry. Surface inline |

---

## 7. Limitations and risks affecting this build

### 7.1 The storage-quota discrepancy — **resolve before Phase 1**

The project premise is a 310 GB Puter account. Official documentation states the free tier is **100 MiB**. There is no published plan table confirming a 310 GB tier. Three possibilities:

1. The account is on a **paid plan** that genuinely provides ~310 GB — the premise holds, and `fs.space()` will report it
2. The 310 GB figure comes from a **third-party or promotional source** and does not match the account
3. The figure is a **misreading** of some other number

**This is the single highest-priority item to verify.** It changes the product framing, the target file sizes, whether resumable transfers and chunking are worth building, and whether the app is viable at all.

**Verification (Phase 0, first task):**

```js
const space = await puter.fs.space();
console.log(space); // { capacity, used }
```

If `capacity` is ~104,857,600 bytes (100 MiB) rather than ~332,860,000,000 (310 GiB), the project needs a serious rethink — a personal cloud drive cannot run on 100 MiB.

### 7.2 No official Dart SDK

Every API call must go through a hand-built transport. There is no vendor-supported Flutter package. This is the project's largest ongoing maintenance cost, and it is why the transport layer is abstracted behind an interface.

### 7.3 WebDAV ceiling is per network, not per account

600 requests/min and 10 concurrent is a **shared ceiling for the whole network**, not a generous per-user allowance. A directory of 500 photos means 500 PROPFINDs if implemented naively — the client must **batch and cache aggressively**, and prefer one recursive listing over per-file `stat` calls.

### 7.4 No atomic batch operations

`fs.upload` is not transactional — a partial failure leaves earlier files written and is not rolled back. Every multi-file operation needs per-item state tracking and a reconciling refresh.

### 7.5 No server-side search

There is a search rate-limit bucket but no documented `fs.search()` method. **Search must be client-side**, over an incrementally built local index. This makes the local database a first-class component rather than an optimisation.

### 7.6 Attribution requirement

Apps built on Puter.js are expected to include a footer link to `https://developer.puter.com`, optionally labelled "Powered by Puter". Plan for this in the About screen and README.

### 7.7 HTTP server requirement (browser path only)

Puter.js requires being served over HTTP, not `file://`. Relevant only to the WebView fallback transport, where the bridge page must be served from an asset-backed local server or an in-app HTTP origin rather than loaded as a raw file.

### 7.8 Quota is not the only ceiling — credit is too

Egress is metered on **every byte sent to a client**. Large downloads consume the user's monthly allowance. The app should show remaining allowance (`auth.getMonthlyUsage()`) and avoid gratuitous re-downloads by caching thumbnails and previews locally.

---

## 8. Open questions to resolve in Phase 0

| # | Question | How to resolve |
|---|---|---|
| 1 | Is the real quota 310 GB or 100 MiB? | `fs.space()` against the live account |
| 2 | What is the exact WebDAV host and path prefix? | Attempt a `PROPFIND` against candidate hosts with `-token` auth |
| 3 | Does WebDAV accept the API token for the filesystem root, or only a subtree? | `PROPFIND /` with depth 1 |
| 4 | Which WebDAV verbs are actually implemented? | Probe `PROPFIND`, `GET`, `PUT`, `MKCOL`, `MOVE`, `COPY`, `DELETE`, `HEAD`, `OPTIONS` |
| 5 | Does `PUT` support `Content-Range` for resumable upload? | Send a partial `PUT` and inspect the response |
| 6 | Are `dav` limits per-account or truly per-network? | Measure sustained throughput and observe when `429` appears |
| 7 | Does the token survive a password change? | Dashboard behaviour; document for the user |
| 8 | What is the real-world read/write throughput? | Time a 100 MB upload and download |

---

## 9. Source index

| Topic | URL |
|---|---|
| Documentation root / index | `https://docs.puter.com/` |
| Full reference for LLM consumption | `https://docs.puter.com/llms.txt` |
| Auth token tutorial | `https://developer.puter.com/tutorials/puter-auth-token/` |
| Node.js quick start (token init) | `https://developer.puter.com/tutorials/puter-js-node-js/` |
| Rate limits, quotas, credits, WebDAV | `https://docs.puter.com/rate-limits-and-quotas/` |
| Filesystem overview | `https://docs.puter.com/FS/` |
| `fs.write` | `https://docs.puter.com/FS/write/` |
| `fs.readdir` | `https://docs.puter.com/FS/readdir/` |
| `fs.upload` | `https://docs.puter.com/FS/upload/` |
| User-Pays model | `https://docs.puter.com/user-pays-model/` |
| Upstream source | `https://github.com/HeyPuter/puter` |
