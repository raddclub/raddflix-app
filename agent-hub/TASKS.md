# RaddFlix Task Tracker

## All Phases 17-20 Complete

| Task | Phase | Status |
|------|-------|--------|
| Empty center (cinematic clean) | 17 | DONE |
| Transport row below seek bar | 17 | DONE |
| Remove CC/Audio/PiP/Rotate/Lock from top bar | 17 | DONE |
| Panel width 55% | 17 | DONE |
| Sidebar auto-hides when panel open | 17 | DONE |
| Both indicators on LEFT | 17 | DONE |
| sub-opacity subtitle fix | 17 | DONE |
| Sidebar width 54->64px | 18 | DONE |
| Accent chevron tab (AnimatedContainer) | 18 | DONE |
| Remove counter badge | 18 | DONE |
| Thin item separators | 18 | DONE |
| Left-border active state | 18 | DONE |
| Icon 20->22px, label 9->10px | 18 | DONE |
| Fix sleep shortcut onTap | 18 | DONE |
| A pin (green draggable flag on seek bar) | 19 | DONE |
| B pin (red draggable flag on seek bar) | 19 | DONE |
| Loop region band between A and B | 19 | DONE |
| Drag to adjust A/B without opening menu | 19 | DONE |
| Double-tap to clear pin | 19 | DONE |
| Subtitle margin 90→140px (clears transport row) | 20 | DONE |
| ASS subtitle font/color live update (sub-ass-override=force) | 20 | DONE |
| _isLocal class field (tracks local vs streaming) | 20 | DONE |
| Sidebar fully hides with controls (opacity 0.4→0.0) | 20 | DONE |
| Lock / Immersive / Settings in transport row | 20 | DONE |
| Guard Find-in-Another-Language for local files | 20 | DONE |
| FAB Resume Last Video in Local Media screen | 20 | DONE |
| Series auto-grouping in Local Folder (collapse/expand) | 20 | DONE |


| isAudio/isVideo detection in LocalVideo model | 21 | DONE |
| LocalFolder.folderType (audio/mixed/video) | 21 | DONE |
| Audio folder icon (🎵) in folder list | 21 | DONE |
| Mixed folder icon in folder list | 21 | DONE |
| Audio track count label in folder tiles | 21 | DONE |
| MUSIC badge on grid cards | 21 | DONE |
| MX-style Sort sheet in LocalMediaScreen | 21 | DONE |
| Sort by: Name, Date, Size, Count, Duration | 21 | DONE |
| A→Z / Z→A direction toggle in sort sheet | 21 | DONE |
| List/Grid layout toggle in LocalMediaScreen | 21 | DONE |
| MX-style Sort sheet in LocalFolderScreen | 21 | DONE |
| Sort by: Name, Date, Size, Duration, Resolution, Type | 21 | DONE |
| Type filter: All / Videos / Audio | 21 | DONE |
| AUDIO badge + music icon for audio files in folder | 21 | DONE |
| Type filter pills in stats bar (mixed folders) | 21 | DONE |

## Phase 26 — GB Subscription System (2026-06-24)

| ID | Task | Status |
|----|------|--------|
| SUB-26-01 | subscription.dart: replace downloadsPerDay/hdAccess → GB fields (dataGb, usagePercent, daysUntilExpiry) | ✅ DONE |
| SUB-26-02 | subscription_api.dart: add getQuota(), resubscribe/upgrade support | ✅ DONE |
| SUB-26-03 | subscription_provider.dart: add refreshQuota(), resetTidSubmitted(), clearError flag | ✅ DONE |
| SUB-26-04 | usage_service.dart: add addDownloadBytes(); document free/local skip rules | ✅ DONE |
| SUB-26-05 | download_service.dart: count actual fileSize bytes toward quota at download completion | ✅ DONE |
| SUB-26-06 | player_screen.dart: _isFree + _trackUsage flags; quota gate in _openMedia; 30s usage timer; _startUsageTimer/_stopUsageTimer | ✅ DONE |
| SUB-26-07 | show_detail_screen.dart: pass 'is_free' in player route args for both episode and movie | ✅ DONE |
| SUB-26-08 | subscription_screen.dart: GB-based plan cards (big GB number + approx hours + Jazz savings), active plan progress bar, resubscribe/upgrade UI, catchy messaging | ✅ DONE |
| SUB-26-09 | quota_full_screen.dart: GB used/limit bar, reset date, catchy "You've Hit Your Data Limit" messaging, SIMOSA correctly labeled | ✅ DONE |
| SUB-26-10 | profile_screen.dart: live GB usage progress bar in subscription card | ✅ DONE |
| SUB-26-11 | mobile_api.py: 4 new seed plans (10GB/150, 30GB/250, 60GB/400, 100GB/700); _compute_app_quota enriched with is_exceeded + resets_at in all response paths | ✅ DONE |

## Open Tasks
None — all phases 17–26 complete. Awaiting next task.

## Phase 22 — Bug Fixes (2026-06-24)

| ID | Task | Status |
|----|------|--------|
| BUG-22-01 | Remove red dot indicator from bottom nav | ✅ DONE (3d1b275) |
| BUG-22-02 | Fix grey screen opening local folder (invalid (?i) regex → crash) | ✅ DONE (217f1e8) |
| BUG-22-03 | Add bottom nav to LocalMediaScreen | ✅ DONE (7ed61f7) |
| BUG-22-04 | Add bottom nav to DownloadsScreen | ✅ DONE (6a5e6e6) |
| BUG-22-05 | Add bottom nav to ProfileScreen | ✅ DONE (f938e67) |
| BUG-22-06 | Player sidebar default collapsed instead of expanded | ✅ DONE (493d842) |
| BUG-22-07 | Fix build: vault_service.dart imports local_auth/auth_strings.dart (removed in 2.x) | ✅ DONE |

## Phase 23 — Completing Task from Previous Session (2026-06-24)

| ID | Task | Status |
|----|------|--------|
| BUG-23-01 | Fix authenticateBiometric: use getAvailableBiometrics() (Infinix/MediaTek Class 2 fix) | ✅ DONE |
| BUG-23-02 | Add to Vault from Downloads screen (selection toolbar vault button) | ✅ DONE |
| BUG-23-03 | Add to Vault from Local Media screen (folder long-press menu) | ✅ DONE |
| BUG-23-04 | LinearProgressIndicator on folder cards in LocalMediaScreen | ✅ DONE |

## Phase 24 — Oracle Backend Fixes (2026-06-24)

| ID | Task | Status |
|----|------|--------|
| ORA-24-01 | Fix _legacy/scanner.py git conflict markers (SyntaxError crash-loop) | ✅ DONE (dde7498) |
| ORA-24-02 | Fix uploader.py: _release_stuck_uploads() before JAZZDRIVE+UPLOAD toggle gates | ✅ DONE (7974e8e) |
| ORA-24-03 | Admin upload.html: stuck-banner + reset-failed checkbox + 4s auto-poll + split stats | ✅ DONE (39b532a) |
| ORA-24-04 | Restart Oracle Flask + verify healthz {"ok":true,"version":"3.0.0"} | ✅ DONE |

## Phase 25 — Full Profile Edit Feature (2026-06-24)

| ID | Task | Status |
|----|------|--------|
| PRO-25-01 | AppUser model: displayName, email, avatarColor, avatarEmoji + displayLabel/avatarInitial getters | ✅ DONE (dc335f7) |
| PRO-25-02 | AuthApi: updateProfile() + changePassword() | ✅ DONE (dc335f7) |
| PRO-25-03 | ApiPaths: /api/auth/profile + /api/auth/change-password | ✅ DONE (dc335f7) |
| PRO-25-04 | EditProfileScreen: avatar color picker (8 colors), name/email fields, change-password bottom sheet | ✅ DONE (dc335f7) |
| PRO-25-05 | ProfileScreen: colored avatar, displayName label, edit pencil button | ✅ DONE (dc335f7) |
| PRO-25-06 | Oracle db.py: 4 new columns + additive migrations | ✅ DONE (dc335f7) |
| PRO-25-07 | Oracle mobile_api.py: PUT /profile + POST /change-password + /me returns new fields | ✅ DONE (dc335f7) |
