# RaddFlix Test Suite

Complete A-to-Z tests for every API, user flow, and logic path in the RaddFlix app.

## Three Files — Three Purposes

| File | What it tests | How to run |
|---|---|---|
| `run_tests.js` | Every server API, JazzDrive zero-rating, user scenarios | `node test_suite/run_tests.js` |
| `logic_tests.dart` | All business logic (no device needed) | `dart run test_suite/logic_tests.dart` |
| `jazzdrive_logic_test.js` | JazzDrive URL parsing, 3-pass match, stream/poster URLs | `node test_suite/jazzdrive_logic_test.js` |

---

## `run_tests.js` — 12 Phases (Node.js, runs from anywhere)

| Phase | What is tested |
|---|---|
| Phase 1 | Server health — ports 5000 & 6000, remote config reachable |
| Phase 2 | Auth API — guest login, register, login, /me, token refresh, expired token |
| Phase 3 | Catalog API — version check, full sync, delta sync, item structure |
| Phase 4 | Stream URL from Oracle server — get link, invalid file_id handling |
| Phase 5 | JazzDrive zero-rating — Step1 login, Step2 media fetch, URL validation, NO validationkey in final URL |
| Phase 6 | Episode navigation — next/prev, season boundaries, countdown, skip intro, watch progress |
| Phase 7 | Subscription — plans list, payment methods, TID submission validation |
| Phase 8 | Admin queue & notifications |
| Phase 9 | User scenarios — guest, Jazz SIM (zero-rated), internet bundle, expired token, poster tap flow |
| Phase 10 | Vault logic — PIN hashing, fake PIN, wrong PIN, lockout escalation, auto-lock |
| Phase 11 | Cache & TTL — 110-min window, expired detection, share key regex for all URL formats |
| Phase 12 | End-to-end full user journey — app start → remote config → guest → catalog → stream link |

### Run (from project root or Replit):
```bash
node test_suite/run_tests.js
```

No install needed — uses Node.js built-ins only (http, https, crypto).

---

## `logic_tests.dart` — 8 Sections (pure Dart, no Flutter needed)

| Section | What is tested |
|---|---|
| Section 1 | JazzDrive URL building — share key regex, buildStreamUrl, validationkey must NOT appear |
| Section 2 | Stream cache TTL — 110-min window, expiry boundary, shared watch+download cache key |
| Section 3 | Episode navigation — hasNext/hasPrev, cross-season, season grouping, countdown, skip intro, watch progress, resume logic |
| Section 4 | Vault security — PIN hashing, fake PIN decoy, wrong PIN rejection, lockout escalation, auto-lock timer |
| Section 5 | Catalog item parsing — movie vs show, isFree, episodes, genre splitting, JSON round-trip, search matching |
| Section 6 | Plan permissions — download limits, quota enforcement, 1080p/720p access, free content |
| Section 7 | API path constants — all start with /, auth paths, package ID, app name |
| Section 8 | Sync logic — version comparison, full vs delta, JazzDrive fallback trigger, episode grouping |

### Run (requires Dart SDK):
```bash
dart run test_suite/logic_tests.dart
```

No packages. Pure `dart:core` only — runs anywhere Dart is installed.

---

---

## `jazzdrive_logic_test.js` — 27 Tests (Node.js, no Jazz SIM needed)

Tests every JazzDrive logic function that mirrors the Dart `jazzdrive_service.dart` implementation.
No packages required — pure Node.js built-ins only.

| Section | What is tested | Count |
|---|---|---|
| URL parsing | `_extractShareKey` — all valid formats, malformed inputs | 7 |
| 3-pass filename match | Pass1 substring, Pass2 normalised, Pass3 episode code, fallbacks | 6 |
| `_buildStreamUrl` | Relative URL prefix, filename param, double-param guard, absolute URL | 5 |
| `_buildPosterUrl` | Relative prefix, absolute unchanged, null/empty -> null | 4 |
| `_getMedia` response shapes | All 5 JazzDrive API response shapes (data.list, data[], root.videos, etc.) | 5 |

### Run (logic only — works anywhere)
```bash
node raddflix_flutter/test_suite/jazzdrive_logic_test.js
```

### Run (full network test — Jazz SIM device required)
```bash
node raddflix_flutter/test_suite/jazzdrive_logic_test.js --live \
  "https://cloud.jazzdrive.com.pk/share/f/yourShareKey..." \
  "All Of Us Are Dead S01E01.mkv"
```

**MED-1011 note:** Share key validation returns MED-1011 from non-Jazz IPs.
Full live test requires a Jazz SIM connection.

---

## Key things verified
## Key things verified

- **JazzDrive CRITICAL rule**: `validationkey` must NEVER appear in the final stream URL — checked in both test files
- **Guest mode**: Can browse catalog and see plans, cannot access premium content
- **Jazz SIM zero-rating**: JazzDrive 2-step flow (login → media → build URL)
- **No Jazz SIM / internet bundle**: Oracle server fallback
- **Vault fake PIN**: Entering fake PIN shows decoy vault, not real content
- **Token refresh**: 401 → auto-refresh → retry original request
- **Admin adds content**: Server version increments → delta sync picks it up

---

## Fixing failures

| Failure | Likely cause | Fix |
|---|---|---|
| Phase 1: Server unreachable | Oracle VM is down | Check `92.4.95.252` server status |
| Phase 2: Guest login 500 | Flask auth route error | Check admin panel logs |
| Phase 3: Catalog sync 404 | Route not registered | Check `catalog_api.py` routes |
| Phase 5: JazzDrive skipped | No share_url in catalog | Add share_url to episodes in admin |
| Phase 5: validationkey in URL | JazzDriveService bug | Never append vk to final URL |
| Logic Section 4: PIN mismatch | Salt changed | Ensure salt is `raddflix_vault_salt_` |
