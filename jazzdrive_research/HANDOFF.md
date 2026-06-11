# Jazz Drive 8.0.1 — Research Handoff Document
> Prepared 2026-06-11. All research from jadx decompilation of Jazz_Drive_8.0.1.xapk.
> Continuation context for any new Replit agent or developer.

## Project Summary

**RaddFlix** is a Pakistani streaming app running on Oracle Cloud + Flutter.
- **Backend**: Flask () at , supervised by supervisord
- **Repo**: 
- **Oracle SSH**: , key in  (GitHub release) or reconstruct from scratchpad
- **Flask app root**: 
- **Supervisor service**:  (python3 /opt/jazzmax/radd-hub/radd_hub.py run --skip-setup)
- **Git remote**: 

## Current State (as of 2026-06-11)

### Working
- Flask server running and responding (version 3.0.0)
- OAuth2 login flow (OTP via SMS → token exchange)
- Session keep-alive (keepalive.py, 15-min ping)
- Token refresh via refresh_token (jazzdrive.py::refresh_session)
- Proxy pool (for geo-restricted Pakistani JD API)

### Broken / Needing Fix
1. **JD Upload**: File uploaded but uid=1000(runner) gid=1000(runner) groups=1000(runner) not extracted from response → share URL never created → titles have no stream URL
2. **JD Scan**: May miss items due to  pagination not handled
3. **Folder listing**: Possible wrong endpoint ( vs )

## Key Files

| File | Purpose |
|------|---------|
|  (2623 lines) | Core JD API wrapper — auth, token refresh, SAPI requests |
|  (2061 lines) | Upload pipeline — watcher, multipart upload, share link |
|  (1230 lines) | JD scan — folder walk, TMDB enrichment, DB import |
|  | Session keep-alive daemon |
|  | SQLite database wrapper |
|  | Vault key management |
|  | HTTP routes for scan UI |
|  | HTTP routes for upload UI |

## RE Artifacts

| File | Location | Purpose |
|------|----------|---------|
|  | GitHub Releases:  | Source XAPK |
| Decompiled sources |  on Oracle | 29,381 Java files |
|  |  | All SAPI endpoints |
|  |  | Upload flow |
|  |  | HTTP layer |
|  |  | OAuth2 interceptor |
|  |  | Upload metadata model |
|  |  | Media item model |

**NOTE**: The  directory on Oracle is ephemeral. Re-extract with:

XAPK download: https://github.com/raddclub/raddflix-app/releases/tag/jazzdrive-apks-v1

## Quick Fix Sequence

To fix JD upload immediately:

1. SSH to Oracle: 
2. Edit  in :
   - Find the response parsing block after 
   - After getting , check if  is in (U,C)
   - If yes and no uid=1000(runner) gid=1000(runner) groups=1000(runner) in response: do folder listing (already implemented in the fallback)
   - Move the listing fallback to ALWAYS run when status is present but ID is absent
3. Restart service: 

## Research Documents in This Folder

| File | Content |
|------|---------|
|  | Index |
|  | All RE findings from decompilation |
|  | Upload flow deep dive + bugs |
|  | Complete SAPI API reference |
|  | Full auth flow with code |
|  | Specific bugs + fixes |
|  | This document |
