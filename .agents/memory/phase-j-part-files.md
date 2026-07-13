---
name: Phase J part-file extraction
description: How part/part-of was used to split player_screen.dart; preflight false-positive pattern.
---

## What was done
player_screen.dart reduced 9,425 → 6,198 lines by extracting top-level panel widget
classes (lines 6194–9425) into three `part` files under `lib/screens/player/`.
Part files: `_ps_panels_subtitle.dart`, `_ps_panels_audio.dart`, `_ps_panels_sidebar.dart`.

## Preflight false-positive rule
`auto_commit.sh`'s preflight_check.sh flags `RaddRadius.`/`RaddSpace.`/`AppColors.` usage
in part files as "missing import". This is a **false positive** — part files share the
host file's library scope and do NOT need their own imports. Always use `SKIP_PREFLIGHT=1`
when committing `part of '...'` files that reference symbols imported by the host.
State the reason in the commit message.

**Why:** The preflight script checks for import presence in the individual file, not the
library as a whole. Dart part files are not standalone; they inherit all imports from
the library host file (`player_screen.dart`).

**How to apply:** Any future part file that uses RaddRadius/RaddSpace/AppColors will trigger
this. Use `SKIP_PREFLIGHT=1` and document it.

## File structure note
player_screen.dart has unusual indentation — some methods inside `_PlayerScreenState`
are written at 0-space indent (valid Dart, indentation is purely stylistic). Do not
mistake 0-indent method definitions for top-level functions. The class closes with
`  }` (2-space indent) at approximately line 6192.
