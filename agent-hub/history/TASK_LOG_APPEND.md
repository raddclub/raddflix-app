
## Session 2026-06-07 — JazzDrive Dart Integration Test

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| TASK-021 | JazzDrive Dart integration test + CI job | ✅ DONE |

### Files changed
| File | Change | Commit |
|------|--------|--------|
| raddflix_flutter/test_suite/jazzdrive_dart_test.dart | New: real HTTP Dart test, 8 test cases | 9614dae |
| .github/workflows/ci-tests.yml | New job: jazzdrive-dart (continue-on-error) | 9614dae, 72beab0, this commit |
| agent-hub/TASKS.md | Added TASK-021 | this commit |

### Key findings (from running the test — CI run #681)
1. **Dart link generation code is correct** — Pass 0, Pass 3 all work
2. **JazzDrive filenames use original upload names** — files uploaded as "Vncenz0 S01E01.mp4" (corrupted special char) are stored that way on JazzDrive. Pass 1/2 substring match can never work for these (app sends "Vincenzo", CDN has "Vncenz0"). Only Pass 0 (remote_id) or Pass 3 (SxxExx episode code) can match.
3. **GitHub Actions can't reliably reach cloud.jazzdrive.com.pk** — rotating Azure IPs, sometimes blocked. jazzdrive-dart job is continue-on-error. When reachable, tests pass.
4. **Luka Chuppi folder has 2 files** (original + duplicate) — remote_id is essential for movies too, not just TV.

### State at end of session
- Oracle Flask: ✅ RUNNING
- Account: ✅ ACTIVE (session auto-recovers)
- Open tasks: none
