---
name: Preflight false positive — relative imports
description: preflight_check.sh uses substring match for import paths; relative paths bypass it.
---

The preflight script checks whether `AppConstants.` (and similar tokens) are used in a file by looking for a substring like `core/constants.dart` in the file's import lines.

If the import is written as a relative path (e.g. `'../constants.dart'` from `lib/core/db/local_db.dart`), the substring `core/constants.dart` does NOT appear in the import line, so preflight raises a false positive.

**Why:** The script was written to catch the actual bug pattern (missing import entirely), but the substring check doesn't account for relative vs. absolute import syntax.

**How to apply:** When preflight fires on a file that clearly already has the correct import (just written as a relative path), use `SKIP_PREFLIGHT=1` and document the reason in the commit message. Do not add a duplicate absolute import.
