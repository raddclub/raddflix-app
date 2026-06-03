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
