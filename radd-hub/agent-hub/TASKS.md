# RaddFlix Agent Task Board

_Last updated: 2026-06-08_

## Completed This Session

| ID | Changed | Summary | Ref |
|----|---------|---------|-----|
| FIX-CATALOG-01 | Oracle DB | Bumped updated_at on 3 published titles to force Flutter re-sync | SQL |
| FIX-PLAYER-01 | player_screen.dart L2701 | Local video black screen: changed _position==Duration.zero to _duration==Duration.zero in AnimatedOpacity — _duration never resets mid-play on Infinix | GitHub 215bbc2055 |
| FIX-VAULT-01 | vault_service.dart L157 | Vault biometric: biometricOnly:true throws silently on Infinix Class 2 sensor; changed to false | GitHub 59fc97249c |
| FEAT-AUTOPUB-01 | scanner.py L600,L807,L820 | Auto-publish titles after scan: new SQL helper publishes any title with a linked file that has a share_url | Oracle only |
| FIX-CATALOG-02 | Oracle DB | Unpublished 3 ghost titles (Dune id=15, Animal id=16, Inception id=20) that had is_published=1 but zero files linked | SQL |
| FIX-CATALOG-03 | Oracle DB | Regenerated db_update.json from scratch — stale June 2 version had no share_urls and wrong file_ids; new version has 4 real titles all with share_urls | Oracle file |

## Current Published Catalog (clean state)

| title_id | Title | Type | file_id | share_url |
|----------|-------|------|---------|-----------|
| 25 | Bhooth Bangla | movie | 18 | YES |
| 27 | Luka Chuppi | movie | 28 | YES |
| 28 | Spider-Noir | show | — | S1E1(f31) S1E2(f30) YES |
| 30 | Vincenzo | show | — | S1E1(f35) S1E2(f32) YES |

## APK Status

| Build | Status | Fixes included | Size | Expires |
|-------|--------|----------------|------|---------|
| 1023 | OLD — do not use | none of our fixes | 56MB | — |
| 1025 | LATEST — install this | FIX-PLAYER-01 + FIX-VAULT-01 | 56MB | 2026-07-07 |

GitHub Actions run: https://github.com/raddclub/raddflix-app/actions/runs/27100948120

## Backlog

| ID | Issue | Priority |
|----|-------|----------|
| BUG-CATALOG-REGEN | db_update.json does NOT auto-regen on direct SQL updates — must run Python script manually after any is_published change | High |
| BUG-DUNE-FILE | Dune Part Two, Inception have no files scanned — need scan or manual file link before they can be published | Medium |

## Non-Negotiable Rules

- Never upgrade sqflite_sqlcipher past 3.1.0+1
- Never add androidAttachSurfaceAfterVideoParameters: true
- XOR padding fix must stay in request_encoder.dart
- GitHub pushes via Contents API only — no git shell
- Oracle Python3 for large file GitHub API calls
- GitHub token in local Replit env GITHUB_TOKEN (Oracle .env empty)
- SSH key: reconstruct from ORACLE_SSH_KEY env var to /tmp/oracle_key on each session
- db.setting(k) not db.get_setting(k)
- DB: /opt/jazzmax/radd-hub/data/radd_hub.db
- Backend process: python3 radd_hub.py run --skip-setup in /opt/jazzmax/radd-hub/
- After ANY direct SQL change to is_published: regenerate db_update.json via Python script
- Add tasks to TASKS.md BEFORE making changes
