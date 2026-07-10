#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  RaddFlix — Preflight Static Check (runs automatically inside        ║
# ║  auto_commit.sh before every push that touches .dart files)          ║
# ║                                                                      ║
# ║  No Flutter/Dart SDK is available in this Replit environment (see   ║
# ║  UI_UX_MIGRATION_PLAN.md Phase 0), so `flutter analyze` cannot run   ║
# ║  locally and CI is the only real compiler check. This script closes ║
# ║  the gap for the two mistake classes that have actually broken CI   ║
# ║  before (commit 45a5f1cd): a design-token class used without its    ║
# ║  import, and a static field called like a const constructor         ║
# ║  (e.g. `const AppColors.error`).                                    ║
# ║                                                                      ║
# ║  This is a heuristic, not a real compiler — it cannot catch every   ║
# ║  possible error. It exists to catch the SPECIFIC repeat mistakes    ║
# ║  logged in agent-hub/RULES.md and agent-hub/TASKS.md. CI is still   ║
# ║  the source of truth (Rule 46) — this just avoids paying for a red  ║
# ║  build on mistakes we already know how to catch for free.           ║
# ║                                                                      ║
# ║  HOW TO RUN standalone:                                              ║
# ║    bash preflight_check.sh file1.dart [file2.dart ...]              ║
# ║  Exits 0 if clean, 1 if it finds a known-bad pattern.                ║
# ║  auto_commit.sh calls this automatically; SKIP_PREFLIGHT=1 bypasses ║
# ║  it for an emergency push (use sparingly, and say why).             ║
# ╚══════════════════════════════════════════════════════════════════════╝

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAIL=0

# Classes that are static-only (fields, not constructors) — `const Class.x` or
# `Class.x()` used as a constructor call is always wrong for these.
STATIC_ONLY_CLASSES="AppColors AppIcons AppConstants AppRoutes"

# Map of "identifier prefix" -> "substring that must appear in some import line"
# Add new Radd*/App* token classes here as the design system grows.
declare -A REQUIRES_IMPORT=(
  [AppColors]="core/constants.dart"
  [AppRadius]="core/constants.dart"
  [AppConstants]="core/constants.dart"
  [AppRoutes]="core/constants.dart"
  [RaddRadius]="radd_radius.dart"
  [RaddSpace]="radd_space.dart"
  [RaddTheme]="radd_theme.dart"
  [RaddType]="radd_type.dart"
  [RaddMotion]="radd_motion.dart"
  [AppIcons]="app_icons.dart"
)

for f in "$@"; do
  [[ "$f" == *.dart ]] || continue
  DISK_PATH="$(cd "$REPO_ROOT" && realpath -m "$f" 2>/dev/null || echo "$REPO_ROOT/$f")"
  [ -f "$DISK_PATH" ] || continue

  # Strip line comments and the file's own class declarations don't matter here —
  # we only care whether an identifier is REFERENCED and whether an import exists.
  BODY="$(grep -v '^\s*//' "$DISK_PATH" || true)"
  IMPORTS="$(grep -E '^\s*import ' "$DISK_PATH" || true)"

  # If this file itself DEFINES one of the watched classes, importing it doesn't apply.
  DEFINES_HERE="$(grep -oE 'class [A-Za-z0-9_]+' "$DISK_PATH" | awk '{print $2}' || true)"

  # 1. Missing-import check
  for cls in "${!REQUIRES_IMPORT[@]}"; do
    NEEDLE="${REQUIRES_IMPORT[$cls]}"
    if echo "$DEFINES_HERE" | grep -qx "$cls"; then
      continue
    fi
    if echo "$BODY" | grep -qE "\b${cls}\."; then
      if ! echo "$IMPORTS" | grep -q "$NEEDLE"; then
        echo "  ❌ PREFLIGHT: $f uses '$cls.' but has no import containing '$NEEDLE'"
        FAIL=1
      fi
    fi
  done

  # 2. Static-field-as-constructor check: `const AppColors.foo` / `AppColors.foo()`
  #    where foo does NOT look like a known constructor name pattern. Real bug seen:
  #    `const AppColors.error` (a static Color field, not a constructor).
  for cls in $STATIC_ONLY_CLASSES; do
    if echo "$BODY" | grep -qE "const\s+${cls}\.[A-Za-z0-9_]+(\s|,|\)|;)"; then
      MATCH="$(echo "$BODY" | grep -oE "const\s+${cls}\.[A-Za-z0-9_]+" | head -1)"
      echo "  ❌ PREFLIGHT: $f has '$MATCH' — $cls has no const constructor, only static fields."
      echo "     Fix: drop the 'const' keyword, e.g. '${cls}.xxx' not 'const ${cls}.xxx'."
      FAIL=1
    fi
  done
done

if [ "$FAIL" = "1" ]; then
  echo ""
  echo "  ❌ Preflight check failed — these are the exact mistake patterns that broke CI before."
  echo "     Fix the file(s) above, or re-run with SKIP_PREFLIGHT=1 if this is a false positive"
  echo "     (and say why in the commit message)."
  exit 1
fi

exit 0
