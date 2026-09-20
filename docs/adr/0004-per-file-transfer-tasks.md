# ADR 0004 — Per-file transfer tasks, never batch operations

**Status:** Accepted
**Date:** 2026-09-20

## Context

Puter's upload API accepts many items at once:

```js
puter.fs.upload(items, dirPath, options)  // items: FileList | Array<File> | Array<Blob>
```

The convenience is tempting — one call for a 200-photo selection. But the documented failure semantics make batch operations a liability:

- If **any** item fails, the promise **rejects**. It never resolves to a mixed result
- A partial failure is **not rolled back** — items already written stay written
- Per-item detail arrives in `failedItems[]`, each with `path`, `message`, and where available `code` and `status`
- When every failure shares a cause, `code`/`status` are **hoisted onto the rejection itself**, erasing per-item attribution. Quota exhaustion does exactly this: `code: 'storage_limit_reached'`, `status: 413`
- The legacy-endpoint fallback cannot create directories at all and rejects with `batch_upload_failed`

Combined with a **100 MiB free quota** (pending verification — see the research doc), quota exhaustion mid-batch is not a corner case. It is the expected outcome of a large selection on a small account.

## Decision

Model transfers as **independent per-file tasks**, each with its own persistent state:

- One `transfer_tasks` row per file: `state`, `bytesDone`, `bytesTotal`, `attempts`, `lastError`
- One `transfer_chunks` row per completed chunk, enabling resume after process death
- **Never** submit an unbounded batch. Where the API's batching is used at all, it is bounded to a small window (≤10 files) purely to reduce request count, and each item's outcome is still tracked individually
- **Pre-flight every upload** against `usage().capacity - used`, refusing early with a clear message rather than failing at 99%
- **Reconcile after every multi-file operation** — since nothing is transactional, the client re-lists the affected directory rather than assuming its optimistic state is true
- **Concurrency is owned by the request scheduler**, never by the queue, so the global cap and the rate limiter stay authoritative
- **Failure policy per error kind**: transient → backoff and retry; `402`/`413` → block the task, keep the local file, prompt the user; `401` → halt the queue and re-onboard

## Consequences

**Positive**

- **Failure isolation.** One file hitting the quota limit does not obscure the fate of the other 199, and the user sees exactly which succeeded and which did not
- **Resumability.** A killed process loses at most the current chunk
- **Honest progress.** Per-file and aggregate progress are both derivable, and both are truthful
- **Clean retry semantics.** Retry a single file without re-uploading a batch
- **Correct quota handling**, because each task can be blocked individually and the remaining files held in the outbox

**Negative**

- **More requests.** One per file instead of one per batch, against a tight per-minute ceiling. Mitigated by the multipart-upload budget (1,200/min free, 2,400/min paid) and a small bounded batch window
- More client complexity than a single fire-and-forget call
- A persistent queue must be migrated and garbage-collected

**Accepted trade-off:** request efficiency is sacrificed for correctness and user-visible truth. On a quota-constrained account, that is the right direction.

## Alternatives rejected

- **Unbounded batch uploads** — non-atomic, poor failure attribution, and the natural failure mode on a small quota is the one that loses information
- **In-memory queue only** — Android kills background work; the queue must survive process death
- **Client-side rollback on partial failure** — cannot be made correct. Writes that succeeded are already durable and may not be safely deletable, and rolling back a successful upload could destroy a file the user wanted
