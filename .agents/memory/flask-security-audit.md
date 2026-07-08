---
name: Flask security audit results
description: Full radd-hub Flask route security audit — scope, clean findings, 3 bugs fixed (O1/O2/O3), intentionally-public routes.
---

# Flask Route Security Audit — 2026-07-07

## Bugs Fixed

### O1 — ValueError → 500 (`app.py`)
- All 35 `int(request.args.get())` calls raised unhandled `ValueError` on malformed params → HTTP 500.
- Fix: global `@app.errorhandler(ValueError)` returning 400 JSON in `hub/app.py`.
- Commit: `a2943fd`

### O2 — Unauthenticated stop endpoint (`catalog_api.py`)
- `POST /api/catalog/poster-push/job/<job_id>/stop` had no auth guard.
- Job IDs are Unix timestamps (`str(int(time.time()))`) — guessable by any caller.
- Fix: added `if not _check_admin_auth(): return 401` matching the pattern in `poster-push/bulk`.
- Commit: `20765be`

### O3 — OTP brute-force (`mobile_api.py`)
- `POST /api/auth/device-switch/verify`: 6-digit OTP, 10-minute window, no attempt counter.
- Wrong guesses did not consume the OTP → 1,000,000 combinations were brute-forceable.
- Fix: `_otp_attempts` dict (phone-keyed in-memory); 5 wrong guesses burns OTP from DB + returns 429; correct guess clears counter.
- Pattern: mirrors `_login_ip_window` / `_login_rate_check` already in the same file.
- Commit: `bcbd41f`

## Clean Findings (no action needed)

| Category | Finding |
|---|---|
| JSON hard-subscripts | 0 found — all routes use `get_json(silent=True) or {}` |
| f-string SQL injection | Safe: `{order}` = "DESC"/"ASC" only; `sort_clause` uses `_SORT_MAP` allowlist; `{name}` vs `ALL_TABLES`; `{tbl}` from hardcoded `RESET_TABLES` |
| SSRF | `brand_studio.py` fetches GitHub API with hardcoded `_GITHUB_API`/`_GITHUB_REPO` only |
| Open redirects | `subscriptions.py` uses `url_for` for all redirects |
| DB editor column injection | Admin-only (`@auth.login_required`) — intentional design for the DB editor |
| File uploads | `upload.py` uses `werkzeug.utils.secure_filename`; configurable `max_size_gb` |
| Login rate limiting | `_login_rate_check()` — DB-backed per-IP, 10 attempts / 15-min sliding window |
| CSRF | All admin routes use HTTP Basic Auth, not session cookies — CSRF inapplicable |
| Password hashing | bcrypt via `_hash_user_password()` / `_verify_user_password()` |
| Password validation | Minimum 6 chars checked at registration |

## Intentionally Public Routes (documented, no auth by design)

| Route | Reason |
|---|---|
| `GET /ping` | Silent session-keepalive probe, no data exposed |
| `GET /config` | Flutter fetches remote config before user logs in |
| `GET /api/queue/status` | Queue progress only, no credentials exposed |
| `GET /api/catalog/poster-push/status` | Upload coverage report, no secrets |
| `GET /api/catalog/poster-push/job/<job_id>` | Read-only job-progress polling |

## Auth Patterns in radd-hub

- **Admin HTML panel routes** (`admin.py`, `library.py`, etc.): `@auth.login_required` decorator (HTTP Basic Auth via `RADD_ADMIN_USER`/`RADD_ADMIN_PASS` env vars).
- **catalog_api.py privileged routes**: `_check_admin_auth()` inline function (same Basic-auth env vars).
- **mobile_api.py**: `_require_auth()` — JWT bearer token issued at login.
- **`_catalog_require_auth`**: separate catalog-JWT pattern for Flutter client endpoints.
