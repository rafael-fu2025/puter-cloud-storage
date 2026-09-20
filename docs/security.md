# Security

The threat model is unusual and worth stating plainly: **this app holds a credential that is equivalent to the user's account password.**

---

## 1. The credential

Per ADR 0001, authentication uses a **Puter account API token** created at `puter.com/dashboard#account`.

Its properties drive everything in this document:

| Property | Value | Consequence |
|---|---|---|
| Scope | **Entire account** | No least-privilege narrowing is possible. Leakage = full compromise |
| Lifetime | **Indefinite** until revoked | A leaked token does not expire on its own |
| Refresh | **None** | Cannot be rotated automatically; the user must mint a new one |
| Revocation signal | **None pushed to the client** | The app discovers revocation only by getting a `401` |
| Storage format | Opaque bearer string | Nothing to derive, nothing to validate offline |

Puter does not document scoped, per-app, or expiring tokens. **This risk cannot be engineered away by narrowing the credential — only by protecting it.**

---

## 2. Threats and controls

| # | Threat | Control |
|---|---|---|
| 1 | Token extracted from device storage | Keystore-backed `flutter_secure_storage` with `encryptedSharedPreferences`; never `SharedPreferences`, never plain files |
| 2 | Token leaked in logs or crash reports | Redacting interceptor strips `Authorization` and basic-auth credentials before any log or error payload. **Asserted by an automated test** |
| 3 | Token exfiltrated via Android auto-backup | Secure-storage entries **excluded** in `backup_rules.xml` and `data_extraction_rules.xml`. Otherwise the token restores onto another device |
| 4 | Token committed to version control | `.gitignore` covers `.env*`, `*.keystore`, `key.properties`. **No token ever appears in the repo or its history.** CI scans for token-shaped strings |
| 5 | Shoulder-surfing or device sharing | Optional biometric app lock (`local_auth`), independent of token validity; biometric required to reveal the token |
| 6 | Malicious app on a rooted device reads memory | Out of scope. Documented as an accepted limitation — root compromises every secret on the device |
| 7 | Man-in-the-middle | HTTPS only, no cleartext exemptions. No certificate pinning initially, because Puter's infrastructure may rotate; revisit once the host set is stable |
| 8 | Token brute-forced via WebDAV | Not applicable — but the **failed sign-in lockout is a real hazard**: 10 failures locks the account out of WebDAV for 15 minutes, including for the correct password. See §4 |
| 9 | Third-party dependency compromise | Minimal dependency surface; `flutter pub outdated` and advisory checks at each phase boundary |
| 10 | Over-broad Android permissions | Request only what each feature needs, and only when it needs it. Auto-backup permissions requested at the point of enabling auto-backup, not at install |

---

## 3. Handling rules

These are not guidelines. They are the rules the code must satisfy, and each is testable.

1. The token is read from the vault at the moment of use and **never** held in a long-lived field, provider, or singleton.
2. No Riverpod provider **ever** exposes the raw token. Providers expose `isAuthenticated` and identity metadata only.
3. Every outbound request goes through the redacting client. There is no second HTTP client.
4. The token is never written to: logs, analytics, crash reports, error messages, URLs, filenames, or clipboard history.
5. The token is never rendered in the UI except behind an explicit, biometric-gated reveal.
6. On `401` or `403`: clear the vault, emit `AuthRevoked`, route to onboarding. **No silent retry, no fallback credential.**
7. On app lock or token replacement: clear in-memory references before the new value is stored.
8. Debug builds must not enable verbose HTTP logging of headers.

---

## 4. The WebDAV lockout hazard

A subtle and easily-missed trap, documented in Puter's rate-limit reference:

| Limit | Per 15 minutes |
|---|---|
| Failed sign-ins for one account | 10 |
| Failed sign-ins from one address | 50 |

Exceeding either returns `429` **for the correct password too**.

This means a naive implementation — for example, a validation retry loop, or a token-refresh poller that retries on failure — can **lock the user out of their own storage** for 15 minutes.

**Therefore:**

- Token validation is attempted **exactly once** per user action
- **No automatic retry on authentication failure**, anywhere in the codebase
- A failed validation surfaces to the user with an explicit, manual retry control
- Any background health check is **disabled by default** and user-initiated when enabled
- The lockout window and its cause are explained in the UI when a `429` follows a failed auth attempt, so the user does not assume the token is wrong

This applies only to the WebDAV host. The desktop, REST API, and `puter.auth` keep working during a lockout — worth saying in the error message, since it tells the user their token is fine.

---

## 5. Onboarding disclosure

The welcome screen must state, without hedging:

> Your Puter auth token grants full access to your Puter account. Anyone who obtains it can read, modify, and delete your files.
>
> Store it as you would a password. You can revoke it at any time from your Puter dashboard.

The user is being asked to hand over a root credential. They are entitled to know that before they paste it.

---

## 6. Incident response

If a token is suspected compromised:

1. Revoke it immediately at `puter.com/dashboard#account` — this is the only effective action, and it is instant
2. In the app: **Settings → Account → Replace token**, which validates the new one before swapping
3. The old token is cleared from the vault on replace; no copy is retained
4. Review the Puter account for unexpected files or shares

Revocation is server-side and authoritative. The app holds no cached authority, so nothing else needs to be done.

---

## 7. Verification checklist

Re-run at every phase boundary.

- [ ] Token present in Keystore-backed storage, absent from `SharedPreferences` and all files
- [ ] Automated test asserts the token never appears in log output
- [ ] Automated test asserts the token never appears in a serialised error payload
- [ ] `backup_rules.xml` and `data_extraction_rules.xml` exclude secure-storage entries
- [ ] `.gitignore` covers all secret-bearing paths; `git log -p` searched for token-shaped strings
- [ ] No provider exposes the raw token
- [ ] `401` handling clears the vault and routes to onboarding, with no retry
- [ ] No code path retries a failed authentication
- [ ] Biometric gate works and cannot be bypassed by process restart
- [ ] No cleartext HTTP anywhere; `usesCleartextTraffic` is not enabled
- [ ] Onboarding disclosure text is present and accurate
- [ ] Debug builds do not log request headers
