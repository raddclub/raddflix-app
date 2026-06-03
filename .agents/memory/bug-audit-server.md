---
name: Server Bug Audit
description: BUG-S01 to S15 — exact code locations and fix patterns for all server-side bugs
---

# Server Bug Audit (2026-06-03)

All bugs in `radd-hub/hub/routes/` unless noted. None fixed yet.

---

## BUG-S01 — CRITICAL | delta_push.py — Wrong version in delta.json after force-bump

**File:** `radd-hub/hub/routes/delta_push.py` → `generate_delta_json()`

**Problem:**
```python
ver_row = c.execute("SELECT MAX(updated_at) AS v FROM titles WHERE is_published=1").fetchone()
catalog_version = int(ver_row["v"] or now_ts)
```
Ignores `catalog_forced_version` from settings. But `/api/catalog/version` uses `_catalog_version()` which returns `max(titles_max, forced_ts)`. After force-bump, delta.json has old version → infinite re-sync loop on every app open.

**Fix:** In `generate_delta_json()`, compute version same way as `_catalog_version()`:
```python
forced = int(db.get_setting("catalog_forced_version") or 0)
titles_max = int(ver_row["v"] or 0)
catalog_version = max(titles_max, forced, now_ts if ver_row["v"] is None else 0)
```

---

## BUG-S02 — HIGH | catalog_api.py — NULL updated_at titles in every delta

**File:** `radd-hub/hub/routes/catalog_api.py` → `sync()`

**Problem:** `WHERE t.is_published = 1 AND (t.updated_at IS NULL OR t.updated_at > ?)` — the `IS NULL` clause always passes, sending un-updated titles on every delta.

**Fix:** `WHERE t.is_published = 1 AND t.updated_at IS NOT NULL AND t.updated_at > ?`  
Handle NULL-updated_at titles separately (treat as since=0 on first sync only).

---

## BUG-S03 — HIGH | catalog_api.py — Random file_id per sync for multi-file movies

**File:** `radd-hub/hub/routes/catalog_api.py` → `sync()` SQL

**Problem:** `GROUP BY t.id` with no ORDER on files side → SQLite returns arbitrary file row for movies with multiple quality files (720p + 1080p).

**Fix:** Use `MIN(f.id)` or `MAX(f.id)` explicitly:
```sql
MIN(f.id) AS file_id,
MIN(f.share_url) AS file_share_url
```

---

## BUG-S04 — HIGH | library.py — Trending always returns 0 results

**File:** `radd-hub/hub/routes/library.py` → `api_trending()`

**Problem:** `"t.poster_url IS NOT NULL AND t.poster_url != ''"` — column `t.poster_url` doesn't exist. SQLite treats it as NULL → condition always False → 0 results.

**Fix:** Change to `t.poster IS NOT NULL AND t.poster != ''` (or `t.poster_share_url` for JazzDrive URL).

---

## BUG-S05 — HIGH | library.py — recent_views always 0 (wrong date compare)

**File:** `radd-hub/hub/routes/library.py` → `api_trending()`

**Problem:** `AND wh.watched_at >= datetime('now', '-60 days')` but `watched_at` is stored as Unix epoch int (e.g. `1748000000`). Comparing int to datetime string `'2026-04-04 12:00:00'` always returns False.

**Fix:**
```sql
AND wh.watched_at >= strftime('%s', 'now', '-60 days')
-- or
AND wh.watched_at >= (strftime('%s', 'now') - 5184000)
```

---

## BUG-S06 — HIGH | Double-decode when XorWsgiMiddleware + decode_request() both active

**Files:** `radd-hub/hub/app.py`, `radd-hub/hub/routes/request_encoding.py`

**Problem:** Middleware decodes body before Flask. Routes calling `decode_request()` try to re-decode already-plain JSON → garbage → body lost → silent 400.

**Fix:** Audit all routes for manual `decode_request()` calls. Remove them. Use `request.json` directly (body already decoded by middleware). Keep `@encoding_supported` decorator only if middleware is NOT active for that route.

---

## BUG-S07 — MEDIUM | subscriptions.py — Expired premium user gets "basic" on extend

**File:** `radd-hub/hub/routes/subscriptions.py` → `extend()`

**Problem:** `SELECT ... WHERE user_id=? AND is_active=1` finds nothing for expired sub → INSERT new "basic" plan.

**Fix:**
```python
sub = c.execute("SELECT * FROM app_subscriptions WHERE user_id=? ORDER BY expires_at DESC LIMIT 1", (user_id,)).fetchone()
if sub:
    new_exp = max(sub["expires_at"], now) + days * 86400
    c.execute("UPDATE app_subscriptions SET expires_at=?, is_active=1 WHERE id=?", (new_exp, sub["id"]))
```

---

## BUG-S08 — MEDIUM | mobile_api.py — Race condition in register() → 500 not 409

**File:** `radd-hub/hub/routes/mobile_api.py` → `register()`

**Problem:** CHECK then INSERT is not atomic. Concurrent double-tap → UNIQUE violation → 500.

**Fix:**
```python
try:
    c.execute("INSERT INTO app_users(phone, password_hash, created_at) VALUES(?,?,?)", ...)
except sqlite3.IntegrityError:
    return jsonify({"error": "Phone already registered"}), 409
```

---

## BUG-S09 — MEDIUM | mobile_api.py — Hardcoded HTTP URL in app_config()

**File:** `radd-hub/hub/routes/mobile_api.py` → `app_config()`

**Problem:** `"api_base_url": "http://92.4.95.252"` hardcoded. Will break when HTTPS/domain added.

**Fix:** Read from settings table:
```python
api_base_url = db.get_setting("api_base_url") or "http://92.4.95.252"
```

---

## BUG-S10 — MEDIUM | catalog_api.py — force-version-bump can silently no-op

**File:** `radd-hub/hub/routes/catalog_api.py` → `force_version_bump()`

**Problem:** If `titles_max >= now_ts` (e.g. server clock drift), forced bump is useless.

**Fix:** Write `now_ts + 1` to ensure it's always larger than any existing title timestamp.

---

## BUG-S11 — MEDIUM | mobile_api.py — watch_history UPSERT silently fails

**File:** `radd-hub/hub/routes/mobile_api.py` → `save_history()`

**Problem:** `ON CONFLICT(user_id, file_id)` only works if `UNIQUE(user_id, file_id)` exists in schema. If missing, every save inserts new row → duplicates in Continue Watching.

**Fix:** Check schema — add `UNIQUE(user_id, file_id)` index if missing. Also increment `catalogDbVersion` in Flutter to add matching migration.

---

## BUG-S12 — LOW | delta_push.py — Bulk-enrich triggers rapid consecutive re-uploads

**Fix:** Add a debounce (e.g. 30s) before triggering JazzDrive upload after version change.

---

## BUG-S13 — LOW | library.py — WhatsApp blast fires immediately on publish

**Fix:** Add configurable delay (e.g. 5 minutes) before sending blast. Or require explicit admin confirmation.

---

## BUG-S14 — LOW | mobile_api.py — Login rate-limit resets on server restart

**Fix:** Persist rate-limit counters in the SQLite settings table or a dedicated rate_limit table.

---

## BUG-S15 — LOW | catalog_api.py — Poster push job state lost on restart

**Fix:** Persist job state in DB. Or accept the limitation (low impact, admin can retry).
