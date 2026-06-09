---
name: Catalog Sync Auth
description: Why catalog/sync must be public and how guest token timing causes empty catalog
---

## Bug
`/api/catalog/sync` in `catalog_api.py` had `@_catalog_require_auth` decorator, returning `{"error":"auth required"}` (401) when called without a Bearer token.

Guest users call `continueAsGuest()` which immediately marks the user as authenticated and calls `_tryAcquireGuestServerToken()` in the **background** (async, non-blocking). The catalog `initialize()` then calls `syncFromServer()` immediately — before the guest token is saved to Keystore. Result: catalog sync fires without a token → 401 → empty catalog, only SimosaCard visible.

## Fix
Removed `@_catalog_require_auth` from the `/sync` route in `/opt/jazzmax/radd-hub/hub/routes/catalog_api.py`. The `/api/catalog/sync` endpoint is now fully public — catalog metadata (titles, descriptions, posters, share_urls) is available to all users without authentication.

Individual playback (`/api/catalog/share_url`, `/watch/api/play/`) still requires auth; premium content still blocked at stream time.

**Why:** Catalog metadata is not sensitive. Zero-rated Jazz SIM users need catalog access before they register or log in.


## BUG-STALE-IDS — Oracle DB Rebuild + Version Match Trap (2026-06-09)

### What happened
Oracle DB was rebuilt (new title IDs 1–20). The server's `catalog_version` was
regenerated from timestamps and happened to match Flutter's cached `localVersion`
(both were `1780929441`). Flutter's logic: if `localVersion >= serverVersion` → skip.
Result: Flutter never re-synced; kept stale entries like Spider-Noir `id=28 file_id=31`
(which no longer exists → 404 → "Jazz SIM Required").

Also: `/sync` is ADDITIVE ONLY. Even when sync ran, old IDs were never removed.

### Fix applied
1. `POST /api/catalog/force-version-bump` → `catalog_forced_version = 1781003205`
   Flutter checks: `if forcedTs > localVersion → needsFullSync = true`
   All devices re-sync on next open.
2. `/api/catalog/sync` now returns `valid_title_ids` list
3. Flutter `pruneStaleIds(validIds)` deletes any title whose ID is not in the server list
   (runs after full sync, commit 338ad31b)

### Rule
After ANY Oracle DB rebuild or bulk title ID change:
**Always run `POST /api/catalog/force-version-bump`** to force all devices to re-sync.
Otherwise Flutter will silently use stale data if the version hash happens to match.
