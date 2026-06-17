# TASK_LOG_APPEND — 2026-06-17
> Staging area. Merged into TASK_LOG.md at session end.

## Session 2026-06-17 — Player UX: 8 MX Player Layout Improvements

### Commits
- `01fc775f` — feat(player): add sidebarMode pref + default rotation → auto
- `bd75f9d6` — feat(player): floating ball, sidebar 3-state, speed track, side panels, clock, auto-rotate

### 8 Improvements Delivered
1. Floating draggable ball — white circle, tap=controls, drag=reposition
2. Sidebar 3-state — full→icons-only→hidden (chevron toggle at top of rail)
3. Sidebar state memory — sidebarMode int persisted in SharedPreferences
4. Clock overlay — top-right white70, always visible when controls hidden, 30s timer
5. Subtitle+Audio panels → right-side overlays (320px, black26 scrim)
6. Speed picker → horizontal dot-rail (#4DB6FF active, white38 inactive)
7. Default rotation → auto (was sensor_landscape)
8. _MxSideBtn icons-only mode (36×36, icon 19px, no label)

### Verification
- 25/25 checks passed before push
- player_prefs.dart: 1152→1158 lines
- player_screen.dart: 6963→7087 lines
