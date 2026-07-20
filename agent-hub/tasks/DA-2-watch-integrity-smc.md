# DA-2: Watch Integrity & Session Minimum Charge

**Status:** Ready to build (DA-1 merged ✅ `a37af458`)
**Depends on:** DA-1 (DB v23 with `usage_log.kind` column — already shipped)

---

## What & Why

Prevent two classes of abuse that cost real CDN money without genuine viewership:

1. **Watch Integrity** — users seeking to the end or fast-forwarding through a movie to
   earn a "completion" badge without actually watching it. The player already tracks
   heartbeat watch-time; we need to enforce a minimum before awarding credit.

2. **Session Minimum Charge (SMC)** — users opening the player for ≥ 20 seconds to
   browse/evaluate a movie triggers real buffering and CDN cost. We deduct a
   quality-dependent floor charge even if the user exits early, so the cost is recovered.
   This is **silent** — the user sees no message or block.

---

## Done looks like

- A movie is only marked "completed" if the user watched ≥ 70% of its real duration
  (existing heartbeat data is used — no new tracking needed).
- Seek-to-end and sustained fast-forward (velocity ratio > 4.0 + seek jump > 40% of
  content) silently deny completion credit.
- Whenever a play session reaches ≥ 20 real wall-clock seconds, the system deducts
  `max(actual_bytes, smcFloor)` from the user's monthly quota:
  - 360p  → 80 MB floor
  - 480p  → 120 MB floor
  - 720p  → 150 MB floor
  - 1080p → 200 MB floor
- Per-title, per-day cooldown: SMC is charged at most once per `(title_id, calendar_day)`
  per user — no double-charge for re-browsing the same movie.
- Everything is **silent enforcement** — no user-facing banners, blocks, or error messages.
- `usage_log` rows written by SMC use `kind = 'smc'` so they are distinguishable from
  normal streaming in the DA-1 Data Usage dashboard.

---

## Out of scope

- Any user-facing UI about completion requirements or SMC (silent only).
- Server-side enforcement (client-side only for now).
- Changing the existing progress bar or completion badge visuals.
- DA-1 Data Usage dashboard (already shipped in commit `a37af458`).

---

## Steps

1. **Completion threshold guard**
   In the watch-session close path, read the title's total duration and the accumulated
   real playback seconds from the heartbeat tracker. If
   `realPlaytimeSecs < 0.70 × totalDurationSecs`, skip writing the completion record.
   Also check for abuse signals (velocity ratio > 4.0 sustained AND seek delta > 40%);
   if either fires, skip completion regardless of time watched.

2. **`UsageService.applySmcIfNeeded`**
   Add this method to `UsageService`. It receives `(titleId, quality, actualBytes)`,
   looks up the SMC floor for the quality, and if `actualBytes < floor`, calls
   `LocalDb.addPendingUsage(bytes: floor - actualBytes, kind: 'smc')` to top up.
   Then calls `flushPending()`.

3. **Per-title cooldown table**
   Add a `smc_log` table: `(id INTEGER PK, title_id INTEGER, charged_on TEXT, created_at INTEGER)`.
   Before charging, query `smc_log` for `(title_id, date('now'))`. If a row exists, skip.
   If not, insert then charge. Bump `catalogDbVersion` to 24. Add migration v24 that
   `CREATE TABLE IF NOT EXISTS smc_log ...`.

4. **`kind = 'smc'` in usage_log**
   SMC top-up bytes must be written with `kind = 'smc'` (already supported by DA-1's
   `addPendingUsage(kind:)` signature) so the DA-1 dashboard breakdown query doesn't
   count them as streaming.

5. **Wire into player teardown**
   Call `UsageService.applySmcIfNeeded` from the existing player lifecycle hook that
   fires on back-press, app-backgrounding, and natural end-of-video. Also hook
   `WidgetsBindingObserver.didChangeAppLifecycleState` to catch OS force-quit. Only
   fire if wall-clock seconds in the session ≥ 20.

---

## Key constants

```dart
static const Map<String, int> smcFloorBytes = {
  '360p':  80  * 1024 * 1024,  // 80 MB
  '480p':  120 * 1024 * 1024,  // 120 MB
  '720p':  150 * 1024 * 1024,  // 150 MB
  '1080p': 200 * 1024 * 1024,  // 200 MB
};
static const int smcMinSessionSecs = 20;
static const double completionThreshold = 0.70;
static const double abuseVelocityRatio  = 4.0;
static const double abuseSeekThreshold  = 0.40;
```

---

## Relevant files

- `lib/core/services/usage_service.dart`
- `lib/core/db/local_db.dart`
- `lib/screens/player_screen.dart`
- `lib/core/constants.dart`

---

## Notes for the executor

- `addPendingUsage(bytes, kind)` signature already exists (DA-1). Use it directly.
- `catalogDbVersion` is currently **23** in `lib/core/constants.dart` — bump to **24**.
- Run `bash auto_commit.sh` after the change; preflight false positive on `local_db.dart`
  is expected — use `SKIP_PREFLIGHT=1` with a note in the commit message.
- DA-2 is pure background logic. No new screens or routes needed.
