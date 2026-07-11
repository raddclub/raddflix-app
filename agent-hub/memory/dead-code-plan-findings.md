---
name: TEN_POINT_PLAN dead-code findings need re-verification
description: A large plan doc's "dead variable" claims can be stale by the time an agent acts on them — always re-grep before deleting.
---

`agent-hub/TEN_POINT_PLAN.md` was produced by a broad multi-subagent audit pass over the whole
codebase. Its per-item descriptions (including "this variable is dead / unused") are a snapshot
judgment, not a guarantee — they can be wrong or go stale as the code around them changes.

**Why:** During Phase C, the plan flagged `_currentFramedrop` and `_labDialogueOnly` in
`player_screen.dart` as dead/duplicate state. Direct grep showed both have real reads and writes
that affect behavior (a seek-flush branch and an audio-pan filter respectively), and the
"duplicate" `_labDialogueOnly` was actually a separate class's own field, not a stale copy. Acting
on the plan text without checking would have deleted live logic.

**How to apply:** Before deleting anything a plan/audit document calls "dead", "unused", or
"duplicate", grep the exact identifier across the file(s) yourself. If it has more than a
declaration + one assignment, treat the finding as unconfirmed and verify manually before
removing. If the finding doesn't hold, say so explicitly in the task log rather than silently
skipping the checklist item — future sessions need to know it was checked, not missed.
