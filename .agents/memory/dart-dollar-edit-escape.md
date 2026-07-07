---
name: Dart $ in Edit tool new_string
description: Dart source code with $ characters (string interpolation, regex patterns) corrupts files when passed as new_string to the Edit tool — use Python str.replace() instead.
---

## Rule
Never use the Edit tool to modify Dart files when `new_string` contains `$` characters (Dart string interpolation like `$filterStr`, regex patterns like `r'^,|,$'`, or multiline strings with `$`).

**Why:** Replit's Edit tool uses JavaScript `String.replace()` internally. The JS replacement string treats `$'` as "insert the substring after the match", `$\`` as "insert the substring before the match", and `$$` as a literal `$`. When `new_string` contains Dart's `$variable` or `$` at end of regex like `r'^,|,$'`, the JS engine expands these and splices the rest of the file into the replacement — causing the file to balloon from ~9000 to ~16000+ lines.

**How to apply:**
1. Any time a Dart edit contains `$` in the new code (interpolation, regex, template), use a Python script instead:
   ```python
   src = src.replace(OLD, NEW, 1)  # Python str.replace() has no $-special-pattern issues
   ```
2. Always assert `count == 1` before replacing to catch ambiguous matches.
3. Sanity-check after: `assert src.count('class MyClass') == 1` guards against file doubling.
4. If the Edit tool accidentally corrupts a file, restore with: `git checkout -- path/to/file`

**Confirmed:** Hit this on player_screen.dart (9090→16399 lines) during Audio Lab bugfix. Python script approach works cleanly.
