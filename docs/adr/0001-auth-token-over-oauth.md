# ADR 0001 — Authenticate with a Puter auth token, not OAuth

**Status:** Accepted
**Date:** 2026-09-20

## Context

Puter.js provides an interactive sign-in flow (`puter.auth.signIn()`) that opens a popup, has the user log into their Puter account, and hands the app a session. That is the default and most-documented way to authenticate a Puter-backed app.

The project requirement is the opposite: **the app must authenticate using a Puter auth token, not the OAuth flow.**

The two options are materially different in what they imply for the client:

| | OAuth / popup sign-in | Auth token |
|---|---|---|
| Who authenticates | The end user, in a browser | The developer, once, in the dashboard |
| Credential lifetime | Session-scoped | Long-lived until revoked |
| Refresh mechanism | Handled by the SDK | **None** |
| Browser required | Yes | No |
| Multi-user | Yes, per user | One account per token |
| Suitable for a personal drive | No — wrong shape | Yes |

This is a single-user personal cloud drive. The OAuth flow would ask the user to log in repeatedly for an app whose entire purpose is to reach *their own* storage. The token is the correct credential shape for the product.

## Decision

Authenticate exclusively with a **Puter account API token**, created by the user at `puter.com/dashboard#account` → **Create token**, and:

- Validate it with a **single** cheap authenticated request at onboarding
- Store it in `flutter_secure_storage`, backed by the Android Keystore
- Pass it as HTTP Basic (`-token` / token) for WebDAV, or as `Authorization: Bearer` for API calls
- Never refresh it — there is no refresh flow; on `401` the user mints a new one

The interactive sign-in flow is **not implemented**, not even as a convenience.

## Consequences

**Positive**

- Works headlessly and in the background — no browser, no popup, no session expiry mid-transfer
- Dramatically simpler auth state: valid or invalid, nothing in between
- Enables the WebDAV transport, which in turn enables pure-Dart streaming and resumable transfers
- The app can start working before any UI is shown, which matters for background auto-backup

**Negative**

- The token is an **account-wide root credential**. Leakage means full account compromise. This forces the security posture in ADR 0003 and `docs/security.md`
- The user must perform manual setup outside the app. This is a real onboarding friction cost, and the welcome screen must carry it well
- No revocation signal reaches the app — the token simply stops working, so the app must handle mid-session `401` gracefully
- Changing the account password may or may not invalidate the token; this is unverified and must be documented for the user

**Accepted risk**

The account-wide scope cannot be narrowed. Puter does not document per-app or scoped tokens. This is accepted, and mitigated by storage, redaction, and biometrics rather than by scope reduction.

## Alternatives rejected

- **OAuth popup sign-in** — violates the stated requirement, requires a browser, and gives session-scoped credentials unsuited to background transfers
- **Storing the account password** — strictly worse than a revocable token; also breaks WebDAV's per-account lockout protection
- **A proxy backend holding the token** — reintroduces the server infrastructure the project exists to avoid, and makes the developer the custodian of the user's credential
