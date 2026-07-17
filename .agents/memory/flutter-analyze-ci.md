---
name: Flutter analyze CI gate
description: How flutter analyze is wired into the CI workflow and why it uses grep instead of exit code.
---

## Rule
The CI workflow runs `flutter analyze` before the 8-minute build step. The step captures output via `tee` and exits 1 only if `"  error •"` lines are present.

## Why
`flutter analyze` exits 1 for warnings AND errors regardless of `--no-fatal-warnings` in Flutter 3.22. Relying on the exit code causes the step to fail on 900+ pre-existing warnings. The grep approach gates only on actual Dart errors.

## How to apply
When adding or modifying the analyze step, keep the tee+grep pattern:
```yaml
run: |
  flutter analyze 2>&1 | tee /tmp/analyze_out.txt || true
  if grep -q "  error •" /tmp/analyze_out.txt; then
    echo "❌ Dart errors detected"; grep "  error •" /tmp/analyze_out.txt; exit 1
  fi
  echo "✅ No Dart errors"
```
If new error-level issues appear, fix them before the build step runs — this saves the full 8-minute build cycle per round trip.
