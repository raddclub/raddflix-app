---
name: Flutter Bug Audit
description: BUG-F01 to F15 — exact code locations and fix patterns for all Flutter app bugs
---

# Flutter Bug Audit (2026-06-03)

All bugs in `raddflix_flutter/lib/` unless noted. None fixed yet.

---

## BUG-F01 — CRITICAL | sync_service.dart — Wrong `since` timestamp (device clock vs server version)

**File:** `raddflix_flutter/lib/core/db/sync_service.dart` → `_syncFromOracle()`

**Problem:**
```dart
final lastSyncTs = await LocalDb.getLastSyncTimestamp(); // device clock time
items = await CatalogApi.syncDelta(lastSyncTs);          // sends device time to server
await LocalDb.setLastSyncTimestamp(nowTs);               // stores device clock, NOT server version
```
Server compares `since` against `titles.updated_at` (Oracle server time). Device clock ahead by minutes → items silently missed.

**Fix:** Store and use the server's `MAX(updated_at)` version, not device wall-clock:
```dart
final lastVersion = await LocalDb.getLastSyncVersion();  // server's last MAX(updated_at)
items = await CatalogApi.syncDelta(lastVersion);
// After sync, store the max updated_at from the response as new version
await LocalDb.setLastSyncVersion(newMaxUpdatedAt);
```

---

## BUG-F02 — CRITICAL | constants.dart — Color constants in wrong class

**File:** `raddflix_flutter/lib/core/constants.dart`

**Problem:** Color constants (`jazzGreen`, `jazzGreenDark`, `simosaAccent`, `orange`, `warningDark`, `layoutDeep`, `layoutPanel`, `layoutSheet`) are defined inside `ApiPaths` class but screens reference them as `AppColors.jazzGreen` etc. `AppColors` has none of these → compile error.

**Fix:** Move all color constants from `ApiPaths` to `AppColors`:
```dart
class AppColors {
  // existing colors...
  static const Color jazzGreen     = Color(0xFF00A651);
  static const Color jazzGreenDark = Color(0xFF006633);
  static const Color simosaAccent  = Color(0xFF7C5CFF);
  static const Color orange        = Color(0xFFFF9800);
  static const Color warningDark   = Color(0xFFB45309);
  // add layoutDeep, layoutPanel, layoutSheet too
}
```
Remove them from `ApiPaths`.

---

## BUG-F03 — CRITICAL | local_db.dart — Migration missing `synced` column → crash on upgrade

**File:** `raddflix_flutter/lib/core/db/local_db.dart` → `_migrate()`

**Problem:** v1→v2 migration creates `watch_positions` without `synced INTEGER DEFAULT 0`. But `getUnsyncedPositions()` queries `WHERE synced = 0` → `DatabaseException: no such column: synced` → crash on startup for users upgrading from v1.

**Fix:** In the `if (oldV < 2)` block:
```dart
await db.execute('''
  CREATE TABLE IF NOT EXISTS watch_positions (
    file_id     TEXT PRIMARY KEY,
    position_ms INTEGER DEFAULT 0,
    duration_ms INTEGER DEFAULT 0,
    updated_at  INTEGER DEFAULT 0,
    synced      INTEGER DEFAULT 0
  )
''');
// Also add ALTER TABLE for users who have the table already
try {
  await db.execute('ALTER TABLE watch_positions ADD COLUMN synced INTEGER DEFAULT 0');
} catch (_) {} // column may already exist
```

---

## BUG-F04 — HIGH | api_client.dart — _isRefreshing not atomic → double token refresh

**File:** `raddflix_flutter/lib/core/api/api_client.dart` → `_AuthInterceptor`

**Problem:** Two concurrent 401 responses both see `_isRefreshing == false`, both set it, both call `_tryRefresh()`. First succeeds, second uses revoked token → `clearAll()` → user logged out.

**Fix:** Use a `Completer` to queue pending requests:
```dart
Completer<bool>? _refreshCompleter;

if (_refreshCompleter != null) {
  final ok = await _refreshCompleter!.future;
  // retry or reject based on ok
  return;
}
_refreshCompleter = Completer<bool>();
try {
  final ok = await _tryRefresh();
  _refreshCompleter!.complete(ok);
} finally {
  _refreshCompleter = null;
}
```

---

## BUG-F05 — HIGH | remote_config.dart — Bootstrap URL is plain HTTP

**File:** `raddflix_flutter/lib/core/remote_config.dart`

**Problem:** `static const String _configUrl = 'http://92.4.95.252/api/config';` — plain HTTP. MitM can intercept, replace `api_base_url`, redirect all subsequent API traffic (login, tokens, catalog).

**Fix:** When domain + SSL are ready, change to `https://yourdomain.com/api/config`. Until then, note this is a known security risk (related to Known Issue R4 — SSL not yet set up).

---

## BUG-F06 — HIGH | sync_service.dart + catalog_api.dart — TV shows have no episodes from Oracle

**Files:** `raddflix_flutter/lib/core/db/sync_service.dart`, `raddflix_flutter/lib/core/api/catalog_api.dart`

**Problem:**
```dart
final episodes = data['episodes'] as List<dynamic>? ?? [];
```
Server's `/api/catalog/sync` response does NOT include a top-level `episodes` key — it only returns `titles` (flat list). `data['episodes']` → null → `[]` → all TV shows have `episodes: []` → user taps show → no episodes.

**Fix — Two options:**
1. **Server fix** (preferred): Add episodes to the sync response:
   ```python
   # In catalog_api.py sync()
   episodes = get_episodes_for_published_titles(since=since, db=db)
   return jsonify({"titles": titles, "episodes": episodes})
   ```
2. **Flutter fix**: Embed episodes inside each title object and parse them from `title['episodes']`.

**Note:** JazzDrive fallback path correctly embeds episodes inside each title. Match that format.

---

## BUG-F07 — HIGH | local_db.dart — usage_log grows forever

**File:** `raddflix_flutter/lib/core/db/local_db.dart` → `clearPendingUsage()`

**Problem:**
```dart
await db.update('usage_log', {'flushed': 1}, where: 'flushed = ?', whereArgs: [0]);
// Rows stay forever — just marked flushed=1
```
~90 rows/month for active user. 1000+ rows after a year.

**Fix:**
```dart
await db.delete('usage_log', where: 'flushed = ?', whereArgs: [1]);
// Or: delete rows older than 90 days
await db.delete('usage_log', where: 'flushed = 1 AND created_at < ?', whereArgs: [cutoff]);
```

---

## BUG-F08 — HIGH | local_db.dart — poster_share_url / folder_share_url not in schema

**File:** `raddflix_flutter/lib/core/db/local_db.dart`

**Problem:** delta.json includes `poster_share_url` and `folder_share_url` per title. `_syncFromJazzDriveDelta` passes them to `mergeDeltaTitle`. But `titles` table schema has neither column → crash or silent drop.

**Fix:** Add to schema in next migration (`if (oldV < 17)`):
```dart
await db.execute('ALTER TABLE titles ADD COLUMN poster_share_url TEXT');
await db.execute('ALTER TABLE titles ADD COLUMN folder_share_url TEXT');
```
And update `mergeDeltaTitle` to write both fields.

**Note:** Must also increment `catalogDbVersion` to 17.

---

## BUG-F09 — MEDIUM | catalog_provider.dart — Static _posterSyncDone prevents poster downloads after delta sync

**File:** `raddflix_flutter/lib/providers/catalog_provider.dart`

**Problem:** `static bool _posterSyncDone = false` — fires exactly once per app process. New titles added via delta sync never get posters downloaded.

**Fix:** Reset flag when new items detected in delta:
```dart
if (deltaItems.isNotEmpty) _posterSyncDone = false;
_schedulePosterSync(movies, shows);
```

---

## BUG-F10 — MEDIUM | api_client.dart — GET requests send X-Encoded:1 but session key can fail silently

**File:** `raddflix_flutter/lib/core/api/api_client.dart` → `_XorInterceptor.onRequest`

**Problem:** `X-Encoded: 1` sent on ALL requests. Server XOR-encodes responses. If session key generation fails silently, response not decoded → empty body → JSON parse fails.

**Fix:** Ensure session key generation is outside the try-catch that can fail silently. Log the failure explicitly.

---

## BUG-F11 — MEDIUM | app_guard.dart — Fingerprint enforcement live, no safe error

**File:** `raddflix_flutter/lib/core/security/app_guard.dart`

**Problem:** `_officialFingerprint` is set to a real SHA-256. If wrong signing key used (debug key, rotation), `isTampered = true` → catalog empty, login fails, no error message shown to user.

**Fix:** Add a clear error screen when `isTampered == true` instead of silent degradation. Show: "This app version is not authorized. Please download from raddflix.pk".

---

## BUG-F12 — MEDIUM | login_screen.dart — const TextSpan with runtime value

**File:** `raddflix_flutter/lib/screens/login_screen.dart` → `_Logo`

**Problem:**
```dart
text: const TextSpan(
  children: [
    TextSpan(text: 'Radd', style: TextStyle(color: t.textPrimary)), // t is runtime!
  ]
)
```
`t.textPrimary` is runtime (from `RaddTheme.of(context)`). `const` on parent TextSpan is invalid.

**Fix:** Remove `const`:
```dart
text: TextSpan(
  children: [
    TextSpan(text: 'Radd', style: TextStyle(color: t.textPrimary)),
  ]
)
```

---

## BUG-F13 — LOW | connectivity_sync_service.dart — Race on startup

**Fix:** Add `await Future.delayed(Duration(milliseconds: 200))` before checking `_wasOffline` in the `onConnectivityChanged` listener, giving `checkConnectivity()` time to complete.

---

## BUG-F14 — LOW | local_db.dart — No migration adds `synced` to existing tables (extends F03)

**Fix:** Same as F03 — add `ALTER TABLE watch_positions ADD COLUMN synced INTEGER DEFAULT 0` in the appropriate migration step, wrapped in try-catch.

---

## BUG-F15 — LOW | pubspec.yaml — sqflite_sqlcipher pinned to old version

**Note:** This pin is intentional — 3.2.x breaks Gradle on Flutter 3.22 CI. Do NOT unpin until CI uses Flutter 3.27+. Acknowledge the risk but do not fix until CI is upgraded.
