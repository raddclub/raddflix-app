# Agent Status
**Last Updated:** 2026-06-21
**Build:** #1218 ✅ SUCCESS (run id=27904238382, ~6 min)
**Run:** https://github.com/raddclub/raddflix-app/actions/runs/27904238382

---

## Latest Session — Player UI Overhaul (2026-06-21)

### Work Completed
| Task | Commit | Status |
|------|--------|--------|
| Right-slide panels (all 10 showModalBottomSheet → showGeneralDialog, 45% width, 60% dark bg) | 2b477ac | ✅ |
| MX Player-style brightness (LEFT, amber) + volume (RIGHT, white/orange) vertical pill indicators | 42388f1 | ✅ |
| Auto-rotation via native Android sensor (SCREEN_ORIENTATION_SENSOR, ignores system toggle) | fd9f8c3 | ✅ |
| Customizable persistent shortcut sidebar (toggle, scroll, all 19 shortcuts, drag reorder, add/remove) | 9e8a1bf | ✅ |
| Brace fix: _SidebarCustomizerPanel class was nested inside _ReverbSelectorState | d70ca1f | ✅ |
| QSP dead slots fixed: PiP button wired, empty slot → Sidebar shortcut | 9e8a1bf | ✅ |

### Current Player File
- **raddflix_flutter/lib/screens/player_screen.dart** — 7071 lines, 21 widget classes
- **Build:** #1218 ✅ clean compile, no errors

---

## Critical Rules (Never Break)
| Rule | Detail |
|------|--------|
| NO `vf=` property | Destroys GL surface on MediaTek → permanent black screen |
| NO `hwdec` mid-play | Only in initial player config before open() |
| NO `androidAttachSurfaceAfterVideoParameters: true` | Same black screen bug |
| db.setting(k) | NOT db.get_setting(k) |
| NO local var named `_np` | Reserved for the mpv player instance |
| Channel names | pip, media, cast, intent, security, orient (all under com.raddflix.app/) |

---

## Build History (Recent)
| Build | Date | Result | Notes |
|-------|------|--------|-------|
| #1218 | 2026-06-21 | ✅ SUCCESS | Sidebar + rotation fixes |
| #1217 | 2026-06-21 | ❌ FAILED | _SidebarCustomizerPanel inside _ReverbSelectorState |
| #1216 | 2026-06-21 | ❌ FAILED | Wrong closing brace insertion |
| #1153 | 2026-06-19 | ✅ SUCCESS | FIX-VF-ROOT black screen fix |
