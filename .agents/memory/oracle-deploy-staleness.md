---
name: Oracle deploy staleness after multi-commit sessions
description: Oracle does not auto-deploy on GitHub push; a mid-session deploy does not cover later commits in the same session.
---

`push_to_oracle.sh` only updates the live server when someone explicitly runs it — there is no
webhook or CI step that deploys on push to `main`. In a session that makes several commits (e.g.
a code fix, then a follow-up build-break fix, then a docs commit), deploying once after the first
commit leaves the server stale relative to every commit that lands afterward, and nothing surfaces
this automatically — the server keeps responding normally, just with old code.

**Why:** this happened for real — O1/O2/O3 were deployed, then a later P1 build-fix + docs commit
landed on `main` without a follow-up deploy, and it went unnoticed until a dedicated re-verification
pass diffed the Oracle git SHA against GitHub's.

**How to apply:** treat "deployed" as a per-commit claim, not a per-session one. Before ending any
session that touched `radd-hub/**`, run `push_to_oracle.sh` once more against the final `main` HEAD,
then confirm via SSH (`cd /opt/jazzmax && git rev-parse HEAD`) that it matches the GitHub `main` SHA
from the REST API — don't trust an earlier deploy's success message as still valid.
