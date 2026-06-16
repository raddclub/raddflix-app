# RaddFlix Agent Task Board

_Last updated: 2026-06-16_

## Completed This Session (2026-06-16)

| ID | Changed | Summary |
|----|---------|---------|
| ✅ BUG-LOGIN-01 | raddflix_flutter/lib/screens/login_screen.dart | Wrong password / any login failure always navigated to home as guest. Root cause: `auth_provider.login()` never throws — catches all DioExceptions internally and sets `state.error`. `_login()` only checked `isDeviceConflict`, not `state.error`, so it always reached `Navigator.pushReplacementNamed(home)`. Fix: added `if (s.error != null) { setState(() { _error = s.error; _loading = false; }); return; }` check before navigation. |
| ✅ BUG-CATALOG-STALE | Oracle DB (settings.catalog_forced_version) | Movies missing play/download buttons + episodes showing "link expired" caused by stale share_urls and file_ids in users' Flutter SQLite from old installs. Fix: bumped `catalog_forced_version` to current timestamp (1781620750) — forces all devices to perform a full catalog re-sync on next app open, overwriting stale entries with current Oracle share_urls and file_ids. |

## Open / In Progress

_No open tasks._

## Pending / Blocked

_Nothing blocked._
