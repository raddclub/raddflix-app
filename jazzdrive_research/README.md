# JazzDrive Integration — Master Reference

> **Purpose:** Definitive reference for every agent and developer who works on the JazzDrive
> integration inside the `radd-hub` Flask backend. Sourced directly from the live production
> code (Oracle 92.4.95.252, `hub/jazzdrive.py`, `hub/scanner.py`, `hub/uploader.py`).
> Last verified: **2026-06-15**.

---

## Document Index

| File | What it covers |
|------|---------------|
| [LOGIN_FLOW.md](LOGIN_FLOW.md) | OTP trigger → submit → full token extraction |
| [AUTH_FLOW.md](AUTH_FLOW.md) | Token types, session refresh chain, SAPI auth headers |
| [API_REFERENCE.md](API_REFERENCE.md) | Every JazzDrive endpoint with verified HTTP details |
| [UPLOAD_FLOW.md](UPLOAD_FLOW.md) | File upload pipeline from queue to share link |
| [FINDINGS.md](FINDINGS.md) | Confirmed discoveries (geo, UA gate, token mismatch) |
| [FIX_GUIDE.md](FIX_GUIDE.md) | Common failures and exact fixes |
| [HANDOFF.md](HANDOFF.md) | Current state snapshot for session handoff |

---

## Quick Architecture Summary

```
Flutter app
    ↕ HTTPS (XOR-encoded)
Oracle Flask (92.4.95.252)   ← wg0 VPN → Jazz datacenter IPs
    ├── hub/jazzdrive.py      Main client: login, OTP, SAPI requests, refresh
    ├── hub/scanner.py        Scan worker: walks JazzDrive folders → DB
    ├── hub/uploader.py       Upload worker: local file → JazzDrive → share link
    ├── hub/keepalive.py      Background: heartbeat to keep JSESSIONID alive
    └── hub/_legacy/          v2 scanner + jazz_share (reused under hub facade)
```

## The Two JazzDrive Host Names

| Host | Purpose |
|------|---------|
| `https://jazzdrive.com.pk` | OAuth2 token exchange only (`/oauth2/token.php`) |
| `https://cloud.jazzdrive.com.pk` | Everything else: SAPI, login, upload, media, share |

---

## Accounts DB Table (SQLite)

```sql
CREATE TABLE accounts (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    msisdn            TEXT UNIQUE NOT NULL,   -- Jazz phone number (03xxxxxxxxx)
    label             TEXT,
    validation_key    TEXT,   -- 32-char hex; needed for every SAPI request
    jsessionid        TEXT,   -- 38-char; session cookie; expires after 3600s idle
    refresh_token     TEXT,   -- 40-char hex; OAuth2 layer; rotated on each use
    raw_accesstoken   TEXT,   -- 40-char hex; OTP-issued; SAPI-registered; no SAPI expiry
    token_expires_at  INTEGER,-- Unix timestamp we set; NOT from JazzDrive API
    last_scan_at      INTEGER,
    last_keepalive_at INTEGER,
    is_active         INTEGER DEFAULT 1,
    role              TEXT    DEFAULT 'flix',
    created_at        INTEGER
);
```

---

## Critical Rules (Never Forget)

1. **`User-Agent: omh android client`** — required on ALL JazzDrive HTTP requests. Without it, SAPI returns a static 401 empty file. This was confirmed by APK decompile of JazzDrive 8.0.1.

2. **SAPI login only accepts the OTP-issued `raw_accesstoken`** — the OAuth2-rotated `access_token` from `token.php` is NEVER accepted by SAPI (`keytype=accesstoken` → 401). The OTP-issued token IS accepted (→ 200). Confirmed live 2026-06-15.

3. **`Authorization` header must match the `key=` param** — for SAPI login, both the `key=<b64>` URL param and the `Authorization: oauth <b64(cred_JSON)>` header must wrap the SAME token.

4. **JazzDrive is NOT geo-restricted** — works from any IP with correct UA. Oracle's IP (92.4.95.252, Indian) works fine. The wg0 VPN routes only 3 Jazz datacenter IPs for zero-rating purposes.

5. **`refresh_token` rotates on every `token.php` call** — never call `token.php` twice with the same RT. The second call gets `invalid_grant`. Save the new RT immediately after step 1, before SAPI step 2.

6. **`startup_refresh` warning ≠ dead session** — when `invalid_grant` fires, `startup_refresh` logs a WARNING but does NOT wipe VK/JID from DB. Uploads use VK directly and will keep working as long as VK is valid.

7. **No `keytype=otp` in JazzDrive 8.0.1** — the endpoint `/sapi/login/oauth?keytype=otp` was removed. Use `keytype=accesstoken` with the OTP-issued `raw_accesstoken` instead.

8. **Do not git-pull on Oracle** — all code changes go: edit locally → push to GitHub via Trees API → pull is blocked by repo rules. Patches are applied via Python scripts SCP'd to Oracle.
