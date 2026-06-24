# RaddFlix Task Log

## Session 2026-06-07 — OPS-01 Session Expired Fix

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| OPS-01 | Fix JazzDrive session expiry / auto-re-auth | DONE |

### State at end of session
- Oracle Flask: RUNNING
- Account: ACTIVE
- Open tasks: none


---

## Session 2026-06-18 — Phase 19: A/B Pin Loop + Phase 20: Subtitle/Local Cleanup

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| P19-01 | A pin (green draggable flag) on seek bar | DONE |
| P19-02 | B pin (red draggable flag) on seek bar | DONE |
| P19-03 | Loop region band between A and B | DONE |
| P19-04 | Drag to adjust A/B without opening menu | DONE |
| P19-05 | Double-tap to clear pin | DONE |
| P20-01 | Subtitle margin 90→140px (clears transport row) | DONE |
| P20-02 | ASS subtitle font/color live update (sub-ass-override=force) | DONE |
| P20-03 | _isLocal class field (tracks local vs streaming) | DONE |
| P20-04 | Sidebar fully hides with controls (opacity 0.4→0.0) | DONE |
| P20-05 | Lock / Immersive / Settings in transport row | DONE |
| P20-06 | Guard Find-in-Another-Language for local files | DONE |
| P20-07 | FAB Resume Last Video in Local Media screen | DONE |
| P20-08 | Series auto-grouping in Local Folder (collapse/expand) | DONE |
| FIX-VF-BLACKSCREEN-GAP | _applyVideoFilters startup gate: set _lastAppliedVf even when blocked | DONE (a7898f8) |
| FIX-BLACKSCREEN-LP2 | Recovery seek on longPress START (framedrop+speed set) | DONE (69824d79) |

### State at end of session
- Oracle Flask: RUNNING (v3.0.0)
- Build: triggered after fixes
- Open tasks: none


---

## Session 2026-06-24 — Phase 21: Local Media Audio/Sort/Filter

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| P21-01 | isAudio/isVideo detection in LocalVideo model | DONE |
| P21-02 | LocalFolder.folderType (audio/mixed/video) | DONE |
| P21-03 | Audio folder icon in folder list | DONE |
| P21-04 | Mixed folder icon in folder list | DONE |
| P21-05 | Audio track count label in folder tiles | DONE |
| P21-06 | MUSIC badge on grid cards | DONE |
| P21-07 | MX-style Sort sheet in LocalMediaScreen | DONE |
| P21-08 | Sort by Name/Date/Size/Count/Duration | DONE |
| P21-09 | A→Z / Z→A direction toggle | DONE |
| P21-10 | List/Grid layout toggle in LocalMediaScreen | DONE |
| P21-11 | MX-style Sort sheet in LocalFolderScreen | DONE |
| P21-12 | Sort by Name/Date/Size/Duration/Resolution/Type | DONE |
| P21-13 | Type filter: All / Videos / Audio | DONE |
| P21-14 | AUDIO badge + music icon for audio files in folder | DONE |
| P21-15 | Type filter pills in stats bar (mixed folders) | DONE |
| BUILD-FIX-01 | Fix const MethodChannel compile error in local_media_screen.dart:378 | DONE (310016f) |

### State at end of session
- Oracle Flask: RUNNING (v3.0.0)
- Build: triggered after fixes
- Open tasks: none


---

## Session 2026-06-24 — Phase 22: Bug Fixes

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| BUG-22-01 | Remove red dot indicator from bottom nav | DONE (3d1b275) |
| BUG-22-02 | Fix grey screen opening local folder (invalid (?i) regex crash) | DONE (217f1e8) |
| BUG-22-03 | Add bottom nav to LocalMediaScreen | DONE (7ed61f7) |
| BUG-22-04 | Add bottom nav to DownloadsScreen | DONE (6a5e6e6) |
| BUG-22-05 | Add bottom nav to ProfileScreen | DONE (f938e67) |
| BUG-22-06 | Player sidebar default collapsed instead of expanded | DONE (493d842) |
| BUG-22-07 | Fix build: vault_service.dart imports local_auth/auth_strings.dart (removed in 2.x) | DONE |

### State at end of session
- Oracle Flask: RUNNING (v3.0.0)
- Build: triggered after fixes
- Open tasks: none


---

## Session 2026-06-24 — Phase 23: Vault + Biometrics

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| BUG-23-01 | Fix authenticateBiometric: use getAvailableBiometrics() (Infinix/MediaTek Class 2 fix) | DONE |
| BUG-23-02 | Add to Vault from Downloads screen (selection toolbar vault button) | DONE |
| BUG-23-03 | Add to Vault from Local Media screen (folder long-press menu) | DONE |
| BUG-23-04 | LinearProgressIndicator on folder cards in LocalMediaScreen | DONE |

### State at end of session
- Oracle Flask: RUNNING (v3.0.0)
- Build: triggered after fixes
- Open tasks: none


---

## Session 2026-06-24 — Phase 24: Oracle Backend Fix (from previous agent's incomplete task)

### Context
Previous agent session ran out of quota while fixing the JazzDrive auto-upload pipeline.
The agent had pushed Python fixes to GitHub but:
1. Never pulled them to the Oracle server
2. Left `hub/_legacy/scanner.py` with 3 git merge conflict markers → SyntaxError
3. Oracle Flask was in a crash-loop (schema-check spam in logs every 2s)

### Root cause of crash-loop
`hub/_legacy/scanner.py` had git conflict markers at lines 699, 1227, 1263 from a failed
`git stash pop`. Import chain: `hub.app` → `hub.routes.scan` → `hub.scanner` →
`hub._legacy.scanner` → **SyntaxError** → supervisord restart every 2s.

### What was already completed by previous agent
- `uploader.py` watcher_loop: `_release_stuck_uploads()` correctly moved before both
  JAZZDRIVE_ENABLED and UPLOAD_ENABLED toggle checks (working tree on server was already fixed)
- `upload.html`: stuck-banner, reset-incl-failed checkbox, 4s auto-poll for jobs table,
  split pending stats (queued vs uploading) — all in server's working tree

### Tasks completed this session
| ID | Task | Status |
|----|------|--------|
| ORA-24-01 | Resolve 3 conflict markers in _legacy/scanner.py (take stashed: DB device_id, cleaner Accept header) | DONE (dde7498) |
| ORA-24-02 | Push corrected uploader.py from Oracle server to GitHub | DONE (7974e8e) |
| ORA-24-03 | Push corrected upload.html from Oracle server to GitHub | DONE (39b532a) |
| ORA-24-04 | Restart Oracle Flask — verified {"ok":true,"version":"3.0.0"} | DONE |

### Files changed
| File | Change |
|------|--------|
| hub/_legacy/scanner.py | Resolved 3 conflict markers (stashed version: DB device_id/name, Accept: application/json) |
| hub/uploader.py | _release_stuck_uploads() before both toggle gates — pushed server's working version |
| hub/templates/upload.html | Stuck-banner + reset-failed checkbox + 4s poll — pushed server's working version |

### State at end of session
- Oracle Flask: RUNNING pid 780429, {"ok":true,"version":"3.0.0"}
- APK build: triggered (monitoring)
- Open tasks: none


---

## Session 2026-06-24 — Phase 25: Full Profile Edit Feature

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| PRO-25-01 | AppUser model — displayName, email, avatarColor, avatarEmoji + display getters | DONE |
| PRO-25-02 | AuthApi — updateProfile() PUT + changePassword() POST | DONE |
| PRO-25-03 | ApiPaths — /api/auth/profile, /api/auth/change-password | DONE |
| PRO-25-04 | EditProfileScreen — avatar color picker, name/email fields, change-password sheet | DONE |
| PRO-25-05 | ProfileScreen — colored avatar ring, displayName, edit pencil overlay | DONE |
| PRO-25-06 | Oracle db.py — display_name/email/avatar_color/avatar_emoji columns + safe migrations | DONE |
| PRO-25-07 | Oracle mobile_api.py — PUT /profile + POST /change-password + /me extended | DONE |

### Files changed
| File | Change |
|------|--------|
| raddflix_flutter/lib/models/user.dart | +displayName, email, avatarColor, avatarEmoji, displayLabel, avatarInitial |
| raddflix_flutter/lib/core/api/auth_api.dart | +updateProfile(), +changePassword() |
| raddflix_flutter/lib/core/constants.dart | +ApiPaths.updateProfile, .changePassword |
| raddflix_flutter/lib/screens/edit_profile_screen.dart | NEW — full profile editor |
| raddflix_flutter/lib/screens/profile_screen.dart | Avatar uses color/name, edit pencil button |
| hub/routes/mobile_api.py | PUT /api/auth/profile, POST /api/auth/change-password, /me extended |
| hub/db.py | 4 new app_users columns + safe ALTER TABLE migrations |

### State at end of session
- Oracle Flask: restarted with new endpoints
- APK build: triggered
- Open tasks: none


---

## Session 2026-06-24 — Verification & Doc Sync

### Context
User requested verification that all previously logged tasks were completed.
Confirmed all phases 17–25 done, latest APK build run#1267 successful on commit e20a8df.

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| VER-01 | Verified all phases 17–25 marked DONE in TASKS.md | DONE |
| VER-02 | Confirmed latest APK build run#1267 success on commit e20a8df | DONE |
| VER-03 | Fixed duplicate Open Tasks section in TASKS.md | DONE |
| VER-04 | Created AGENT_HANDOFF.md with current state | DONE |
| VER-05 | Appended session summary to TASK_LOG.md | DONE |

### State at end of session
- Oracle Flask: RUNNING (v3.0.0)
- APK build: ✅ run#1267 success (e20a8df)
- Open tasks: none
