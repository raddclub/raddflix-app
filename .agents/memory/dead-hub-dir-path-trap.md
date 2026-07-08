---
name: Dead hub/ directory at repo root vs. real radd-hub/hub/
description: A leftover, unused hub/ folder exists at the repo root (mirrored on the Oracle server too) and silently swallows path mistakes during verification.
---

The repo has two directories named `hub/`: a dead one at the repo root (leftover from an earlier
restructure) and the real one at `radd-hub/hub/`, which is what the Flask app actually is. This
isn't just a GitHub-push-path footgun (already called out for template files) — it also exists on
the Oracle server's git checkout, since Oracle mirrors this same repo layout.

**Why:** an SSH `grep`/`cat`/`diff` against a bare `hub/...` path on Oracle returns real output from
the dead copy instead of erroring "file not found," which reads as a legitimate but confusing
result — e.g. a grep for a known-present fix appears to find nothing, or a diff shows unexpected
content, even though the live file is fine. This produced a false alarm during a deploy
re-verification pass before the correct path was identified.

**How to apply:** never grep/cat/diff a bare `hub/...` path against this repo or the Oracle server.
Always use `radd-hub/hub/...`. To be certain which copy is actually live on Oracle, check the
supervisor config's `directory=` line (`sudo cat /etc/supervisor/conf.d/*.conf`) rather than
assuming from the path name — for `raddflix_radd` it's `/opt/jazzmax/radd-hub`.
