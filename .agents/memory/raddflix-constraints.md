---
name: RaddFlix hard constraints
description: Package version caps and API rules that must never be violated
---

## Package constraints
- `sqflite_sqlcipher` must stay at `3.1.0+1` or below — later versions break the encrypted DB key derivation. Do NOT upgrade until CI uses Flutter 3.27+ and the team explicitly tests it.

## Player constraint
- Do NOT add `androidAttachSurfaceAfterVideoParameters: true` to VideoController — causes 3–5s black screen before video on Android.
- `biometricOnly: false` in vault auth — `biometricOnly: true` throws silently on Infinix/MediaTek Class 2 sensors.

## Oracle Python API
- Use `db.setting(key, default=None)` to read settings — `db.get_setting()` does NOT exist and will raise AttributeError on every call.
- Use `db.set_setting(k, v)` to write.
- Settings table columns are `k` and `v` (NOT `key` / `value`).

## XOR encoding
- Key formula: `sha256("raddflix_xor_v1:{X-Device-Id}:{utc_day_of_month}:{utc_hour}").hexdigest()[:32]`
- `_candidate_keys` must include current hour AND `utc_hour + 1` (forward-clock edge) — fixed commit 41fcc63.
- Padding fix in `request_encoder.dart`: `b64 += '=' * ((4 - b64.length % 4) % 4)` — NEVER remove.

## catalog_api.py normalization
- `catalog_api.py` normalises `tv`/`series` → `"show"` in API output.
- `zero_rating.py` preserves original media_type strings (`tv`, `series`, `show`) — uses `media_type in ("show","tv","series")` for episode fill.

## TASKS.md rule (Rule 0)
- Add a row to `/opt/jazzmax/agent-hub/TASKS.md` BEFORE starting any work.
- Also update `agent-hub/TASKS.md` on GitHub before finishing.

**Why:** Discovered during multiple A-Z audit sessions; violations caused crashes, silent wrong behaviour, or lost work context.
