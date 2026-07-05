# RaddFlix Full Audit & Task Plan — 2026-07-04

## Executive Summary

Three independent workstreams were identified during this session's codebase audit. All three are queued as project tasks for the next session:

| Task | Priority | Risk if deferred | Parallel-safe? |
|---|---|---|---|
| Strip sensitive logger output | 🔴 High | Anyone with USB debug or file access can read JazzDrive internals and Oracle URLs | ✅ Yes |
| Rebrand zero-rating copy | 🔴 High | "JazzDrive CDN" literally printed on the subscription screen | ✅ Yes |
| UI/UX upgrade pass | 🟡 Medium | Visual quality gap vs competitor apps | ✅ Yes |

All three tasks touch independent parts of the codebase and can be executed in parallel by separate task agents.

---

## Audit 1 — Logger Exposure (Security Critical)

### What the audit found

The app has a custom `DebugLogger` class (`lib/core/debug/debug_logger.dart`) with a 5,000-entry ring buffer that persists to `raddflix_debug.log` in the system temp directory. This file can be copied to clipboard or shared from the UI.

**Strings that expose internal architecture — currently in the ring buffer:**

| File | Line | Log message | What it reveals |
|---|---|---|---|
| `download_service.dart` | 70, 95 | "Using JazzDrive URL for $fileId" | JazzDrive is the download backend |
| `jazzdrive_service.dart` | 179 | "Generated + cached link for file $fileId → ${link.filename}" | JazzDrive link generation confirmed |
| `jazzdrive_service.dart` | 478 | Full list of filenames/records from JazzDrive share | Complete catalog structure |
| `jazzdrive_service.dart` | 522 | Matching episode code (e.g. s01e01) | Episode-matching algorithm exposed |
| `poster_service.dart` | 124 | "Saved JazzDrive poster for title $titleId" | JazzDrive is the poster CDN |
| `sync_service.dart` | 91 | "Oracle sync complete: N item(s)" | Oracle is the catalog source |
| `sync_service.dart` | 26 | "Oracle sync failed" | Same |
| `api_client.dart` | 383, 411, 449 | "XOR encoded/decoded for path X" | Confirms XOR obfuscation is in use |
| `request_encoder.dart` | 82 | "[XOR] decode failed: $e" (via `print()`) | Same, unconditional |
| `debug_logger.dart` | 33 | `sid` session ID at startup | Session identifier |
| `api_client.dart` | 212 | "Attaching Bearer token to /path" | All authenticated endpoints logged |
| `usage_service.dart` | 56, 68, 96 | Exact byte counts, MB estimates, flush confirmations | Quota and usage implementation detail |
| `search_screen.dart` | 244 | Full search query, result count, filters | User behaviour |
| `show_detail.dart` | 264, 285 | fileId and title being played | User behaviour + internal IDs |

**Additional risk:** `DebugLogger.logApi` truncates request/response bodies to 200–300 characters. If `validationkey`, `k=` tokens, or JSESSIONID appear near the start of a payload, they will be captured.

### Fix strategy

- Replace all JazzDrive/Oracle/XOR-named log strings with generic user-space terms ("Stream provider ready", "Catalog sync complete") or remove them
- Wrap all auth, XOR, and session-ID log calls in `if (kDebugMode)` blocks
- Remove user behaviour logging (search queries, fileIds played)
- Replace the in-app log share feature with a sanitised summary (app version, device tier, last 10 generic error messages only)
- Remove the unconditional `print()` in `request_encoder.dart`

---

## Audit 2 — Zero-Rating Copy Exposure

### What the audit found

The zero-rating feature is correctly kept as a product-level selling point. However, one string goes too far by naming the infrastructure provider:

**`subscription_screen.dart` line 817:**
> "Stream all day — JazzDrive CDN means ZERO data deducted from your Jazz balance."

This tells any user (or competitor) exactly who provides the zero-rated CDN.

**Other Jazz-related strings — all fine:**
- "Zero-rated on Jazz SIM" — ✅ product feature, not infrastructure
- "Join RaddFlix — free for Jazz SIM users" — ✅ marketing, fine
- "Jazz SIM required to stream" (player error) — ✅ necessary user guidance
- "Earn Free MB on Jazz via SIMOSA" — ✅ correct, SIMOSA is a public Jazz program
- "JazzCash or Easypaisa" (payment) — ✅ payment providers, not infrastructure

**`debug_diagnostics_screen.dart` line 109:** label says "Oracle Server" — this screen must be gated behind `kDebugMode` or admin mode.

### Fix strategy

The framing model: users know they need a Jazz SIM. They do not need to know *why* it works data-free. Attribute the feature to RaddFlix, not to a CDN provider.

```
OLD: "JazzDrive CDN means ZERO data deducted from your Jazz balance"
NEW: "RaddFlix streams free on Jazz — no data ever deducted from your balance"
```

Netflix runs on AWS. No Netflix screen says "AWS CloudFront means your shows load fast." Same principle.

---

## Audit 3 — UI/UX Gap Analysis

### Current state vs 2026 streaming standard

| Area | Current state | Gap |
|---|---|---|
| Primary CTAs | Flat `#E8002D` (AppColors.primary) | `AppGradients.brand` defined but never used on buttons |
| Bottom nav tabs | Home / Local / Downloads / Profile | Search buried in AppBar; Local and Downloads waste prime tab slots |
| Show detail | Season tabs → episode rows | Synopsis not above the fold; reads like a file manager |
| Data-free indicator | Onboarding only | No persistent badge during actual use |
| Typography | Dynamic font loaded, letter-spacing defined | Not enforced consistently across screens |
| Gradient usage | 406× AppColors.primary vs 2× AppGradients | Gradient token system is defined but disconnected |

### What's genuinely good (keep as-is)
- AnimConfig device tier system — excellent degradation on low-end devices
- Frosted glass bottom nav with spring pill — 2026-standard
- Hero transition from content card to detail screen
- JazzDrive 2-step stream link architecture (110-min TTL, filename-only CDN URL)
- Dynamic branding via RemoteConfig

### Fix strategy (priority order)

1. **Wire AppGradients to CTAs** — single change, largest visual impact
2. **Move Search to tab position 1** — merge Local into Downloads tab
3. **Show detail: synopsis above the fold** — restructure the hero region
4. **Data-free badge** — `DataFreeBadge` widget, RaddFlix-branded, no CDN attribution
5. **Type scale enforcement** — codify 4-5 text styles and apply consistently

---

## Task Dependency Map

```
Task A (Logger strip) ──────────────────── independent
Task B (Copy rebrand) ──────────────────── independent  
Task C (UI/UX upgrade) ─────────────────── independent
                                              ↑
                        (B should complete before C so gradient
                         CTAs and data-free badge don't accidentally
                         re-introduce JazzDrive copy)
```

Recommended execution order: A and B in parallel first, then C after B is merged.

---

## Files Touched Per Task

### Task A — Logger strip
`lib/core/debug/debug_logger.dart`, `lib/core/download/download_service.dart`, `lib/core/services/jazzdrive_service.dart`, `lib/core/services/poster_service.dart`, `lib/core/db/sync_service.dart`, `lib/core/api/api_client.dart`, `lib/core/security/request_encoder.dart`, `lib/screens/player_screen.dart`

### Task B — Copy rebrand  
`lib/screens/subscription_screen.dart`, `lib/screens/debug_diagnostics_screen.dart`, `lib/screens/player_screen.dart`, `lib/screens/settings_screen.dart`, `lib/screens/onboarding_screen.dart`, `lib/screens/register_screen.dart`

### Task C — UI/UX upgrade
`lib/core/constants.dart`, `lib/widgets/play_button.dart`, `lib/widgets/content_section.dart`, `lib/screens/home_screen.dart`, `lib/screens/show_detail.dart`, `lib/screens/player_screen.dart`, `lib/widgets/radd_bottom_nav.dart`, `lib/main.dart`

---

*Report generated: 2026-07-04 | Session: correction pass + audit + task planning*
