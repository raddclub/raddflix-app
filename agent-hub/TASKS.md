# RaddFlix Player — Task Log
> Last updated: 2026-06-22 | File: player_screen.dart (7033 lines)

---

## ✅ Completed Phases

### Phase 13–14: Right-side panels + MX-style indicators
- All `showModalBottomSheet` → `showGeneralDialog` right-side panels (45% → **55%** width in Phase 17)
- Brightness: LEFT amber vertical pill | Volume: RIGHT → **LEFT in Phase 17**

### Phase 15: Auto-rotation
- Native `SCREEN_ORIENTATION_SENSOR` via Android channel `com.raddflix.app/orient`
- Fixes orientation locking to video aspect ratio

### Phase 16: Customizable Sidebar (Build #1218 ✅)
- Right-edge strip, chevron toggle, scrollable, 19 shortcuts
- Drag-reorder via ReorderableListView
- Accent-color active states, persisted SharedPreferences
- `_sidebarExpanded` (bool) + `_sidebarOrder` (List<String>)

### Phase 17: Cinematic UI Cleanup (Build #1219 ⏳)
**Goal:** Clean cinematic experience — controls out of the way

#### Changes made:
1. **Zero buttons in center** — `_buildCenterControls()` returns `SizedBox.shrink()`
2. **Transport row below seek bar** — `_buildTransportRow()` inserted between seek bar and icon row
   - Layout: `⏪ skip · ⏮ prev · ▶/⏸ play/pause · ⏭ next · skip ⏩`
   - Skip buttons respect `_showSkipBtns` setting
   - Prev/Next respect `_showPrevNextBtns` + dim 25% when unavailable
3. **Top bar: 5 buttons removed** — CC, Audio, PiP, Rotate, Lock (sidebar-only now)
   - Kept: Back, Title, Episode badge, Zoom badge, Sub/Audio sync badges, Replay, Clock, Sleep, Rotation degree, Info
4. **Panel width 55%** — `widthFactor = 0.55` (was 0.45)
5. **Sidebar auto-hide on panel open** — `bool _panelOpen = false`
   - Set `true` before `showGeneralDialog`, reset `false` via `.then()`
   - Sidebar opacity + IgnorePointer both check `!_panelOpen`
   - Respects manual close: if `_sidebarExpanded=false`, sidebar stays closed after panel dismiss
6. **Volume indicator → LEFT** — `right: 20` → `left: 20` (sidebar was blocking it)
7. **Subtitle `sub-opacity` fix** — was `sub-ass-fade-in-time` (fake property)
8. **Subtitle margin max 200px** — was 80px

---

## 🐛 Known Bugs / Open Items

| Priority | Bug | Notes |
|----------|-----|-------|
| P2 | Background color subtitle format | `#ffRRGGBB` might need testing on device |
| P3 | One-handed mode center controls still gone | `_buildCenterControls` is now empty for one-handed too — likely intended |
| P3 | Sleep timer shortcut in transport row | User idea, not yet requested |

---

## Architecture: Key Functions
| Function | Location | Purpose |
|----------|----------|---------|
| `_openRightPanel()` | line ~3213 | All panels — sets `_panelOpen=true`, clears on dismiss |
| `_buildTransportRow()` | line ~2617 | New transport controls below seek bar |
| `_buildSidebar()` | line ~2920 | Right-edge shortcut sidebar |
| `_buildCenterControls()` | line ~2589 | Empty — returns SizedBox.shrink() |
| `_openSubtitlePanel()` | line ~3259 | Opens subtitle right-panel |
