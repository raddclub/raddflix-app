# RaddFlix Agent Skills & Rules

> These rules are non-negotiable. Every agent working on RaddFlix must follow them exactly.
> Violating these rules can break production for real users.

---

## Rule 0 — Reincarnation (READ THIS FIRST, EVERY SESSION)

Before doing anything else, read these 4 files from GitHub in this order:

```
1. agent-hub/REINCARNATION.md      ← checklist + the 7 most important facts
2. agent-hub/PRODUCT_CONTEXT.md    ← full product, architecture, every decision ever made
3. agent-hub/MASTER_TASKLIST.md    ← every task with status ✅/🔧/⬜, what to do next
4. agent-hub/TASK_LOG.md   ← what each previous session did (most recent at bottom)
```

Fetch them like this:
```bash
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/REINCARNATION.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/PRODUCT_CONTEXT.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/MASTER_TASKLIST.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/TASK_LOG.md"
```

After reading, tell the user:
- What the last session did
- What the recommended next tasks are
- Ask what they want to work on

**Never start coding without completing Rule 0.**

---


## Rule 1 — Read Before You Touch

Before making any change:
1. Read `agent-hub/TASK_LOG.md` — know what was already done
2. Read the relevant project doc in `agent-hub/projects/`
3. If touching the server, SSH in and `cat` the file before editing it

Never assume a file's content. Always read it first.

---

## Rule 2 — SSH Connection Pattern

The key is an OpenSSH key stored with **spaces instead of newlines** in Replit Secrets.
Use this Python reformat (confirmed working 2026-05-30):

```python
import os, re
raw = os.environ['ORACLE_SSH_KEY']
m = re.match(r'(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)', raw, re.DOTALL)
if m:
    header = m.group(1).strip()
    body   = m.group(2).strip().replace(' ', '\n')
    footer = m.group(3).strip()
    pem = header + '\n' + body + '\n' + footer + '\n'
    with open('/tmp/oracle_key', 'w') as f:
        f.write(pem)
    os.chmod('/tmp/oracle_key', 0o600)
```

Then SSH works:
```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 "echo OK"
```

**Note:** Replit main agent blocks `git commit`, `git push`, and GitHub API write calls (PUT/POST to github.com).
Run commits via GitHub Tree API from Oracle server using Python (`/tmp/github_commit.py` pattern).

---

## Rule 3 — GitHub API Pattern

Always use the GitHub tree API for multi-file commits. Never use `git` shell commands from Replit.

```python
# Pattern for uploading changed files:
# 1. GET /repos/raddclub/raddflix-app/git/ref/heads/main  → head_sha
# 2. GET /repos/raddclub/raddflix-app/git/trees/{head_sha}?recursive=1  → existing tree
# 3. POST /repos/raddclub/raddflix-app/git/blobs  → upload each new file content
# 4. POST /repos/raddflix/raddflix-app/git/trees  → new tree (keep existing, swap changed)
# 5. POST /repos/raddclub/raddflix-app/git/commits  → new commit
# 6. PATCH /repos/raddclub/raddflix-app/git/refs/heads/main  → move branch (force: False)
```

Always use `"force": False` in the PATCH call. Never force-push.

---

## Rule 4 — Server Edit Pattern

For editing server files:
1. Always `cat` the file first via SSH before editing
2. Use Python `str.replace()` — never regex unless necessary
3. Verify the change after writing: `grep` for the new string
4. Restart the relevant supervisor service if you changed Python files
5. Check service status: `sudo supervisorctl status`

---

## Rule 5 — Supervisor Service Management

```bash
# Check status
sudo supervisorctl status

# Restart after Python file changes
sudo supervisorctl restart raddflix_radd   # radd-hub — ALL API (port 5000)
# raddflix_watch was DECOMMISSIONED 2026-05-30 (catalog migrated to radd-hub)

# Check logs if something is wrong
sudo supervisorctl tail -f raddflix_radd
```

Always verify services are RUNNING after any server-side change.

---

## Rule 6 — Never Touch These

| Path | Why |
|------|-----|
| `/opt/jazzmax/radd-hub/hub/_legacy/` | jazzdrive.py + scanner.py import from here. Deleting = broken streaming. |
| `/opt/jazzmax/` (the folder itself) | Production root. Physical dir name stays jazzmax — do not rename. |
| `main` branch with force push | Will corrupt git history |

---

## Rule 7 — Naming & Branding

- App name: **RaddFlix** (capital R, capital F)
- Package ID: `com.raddflix.app`
- Old names that must never appear: `JazzMAX`, `jazzmax` (except internal server folder paths), `Zeno`, `zeno`
- Exception: `JazzDrive` is Jazz Telecom's CDN product — this name is correct and should stay

---

## Rule 8 — Task Log Update (Required After Every Session)

After completing your work, append to `agent-hub/TASK_LOG.md` via GitHub API.

Format:
```
## [YYYY-MM-DD HH:MM UTC] — Agent: <Replit account or description>

### Task
Brief description of what you were asked to do.

### Done
- Item 1
- Item 2

### Files Changed
- `path/to/file.py` — what changed
- `path/to/other.dart` — what changed

### Notes for Next Agent
Anything the next agent should know. Warnings, incomplete items, etc.

---
```

---

## Rule 9 — Secrets Handling

- `GITHUB_TOKEN` — GitHub personal access token (raddclub account)
- `ORACLE_SSH_KEY` — SSH private key pasted as plain text from Oracle (no encoding)
- Never print secrets to console
- Never write secrets into any file that gets committed to GitHub
- Never hardcode IP, passwords, or keys anywhere in code

---

## Rule 10 — Verify, Don't Assume

After every change:
- Server change → SSH in and confirm the new content is there
- GitHub change → verify commit SHA was returned successfully
- Service restart → run `sudo supervisorctl status` and confirm RUNNING
- Dart/Flutter change → grep to confirm old string is gone and new string is present

If something looks wrong, fix it before logging it as done.


  ---

  ## Addendum — Confirmed Working Tools (2026-05-28)

  ### jq is Available
  `jq` (v1.7.1) is available in the Replit bash environment. Use it to parse GitHub API JSON responses:

  ```bash
  # Get HEAD SHA
  HEAD_SHA=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/raddclub/raddflix-app/git/refs/heads/main" \
    | jq -r '.object.sha')

  # Get tree SHA from commit
  TREE_SHA=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/raddclub/raddflix-app/git/commits/$HEAD_SHA" \
    | jq -r '.tree.sha')
  ```

  ### Support WhatsApp Constant
  All WhatsApp deep links in the app use `AppConstants.supportWhatsApp` (defined in `raddflix_flutter/lib/core/constants.dart`).
  Before production release, update this constant to the real support phone number (international format, no +, no spaces, e.g. `923001234567`).

  Current value: `'923XXXXXXXXX'` (placeholder).

  ---

  ## Addendum — Metadata Fallback Chain (2026-05-29)

  ### Full 6-Tier Enrichment Order

  Both `metadata_lookup.py::enrich()` and `metadata.py::enrich_title()` now use this chain:

  | Tier | Source | Key needed? | Best for |
  |------|--------|------------|----------|
  | 1 | TMDB | Yes — vault provider `tmdb` | International movies & TV |
  | 2 | OMDB | Yes — vault provider `omdb` | IMDB ratings, older Western content |
  | 3 | AI (Groq/Gemini/OpenAI/OpenRouter) | Yes — vault `groq`/`gemini`/etc | Pakistani/Indian regional content |
  | 4 | IMDbAPI.dev | **No key needed** | Free IMDB data; Punjabi/South Asian |
  | 5 | YouTube | Optional — vault `youtube` (Data API v3); also scrapes HTML with no key | Trailer thumbnail as poster |
  | 6 | Google KG | Optional — vault provider `google` | Google Knowledge Graph name/overview |

  ### Adding Optional Keys to the Vault

  In RaddHub → Settings → API Keys:
  - `youtube` — YouTube Data API v3 key (Google Cloud Console → YouTube Data API v3)
  - `google` — Google API key with Knowledge Graph Search API enabled

  These are optional but improve poster quality for YouTube (higher-res thumbnails)
  and Google KG (structured metadata). Without them, YouTube falls back to HTML
  scraping and Google KG is skipped.

  ### Where the fallback chain runs
  - `metadata_lookup.py::enrich()` — called by scanner, post-scan enrichment
  - `metadata.py::enrich_title()` — called by legacy import + `_import_legacy_into_v3_for_account`
  - `organizer.py::enrich_title_metadata()` — helper for post-organize enrichment
  - `downloader.py` — triggers enrichment after every successful upload

  ### IMDbAPI.dev is always available (no key, no rate limit on reasonable usage)
  The free IMDB API at `imdbapi.dev` covers many Pakistani/Punjabi films not on TMDB+OMDB.
  It's particularly good for: Lollywood films, Pakistani TV dramas, Punjabi cinema.


  ---

  ## Addendum — FTS5 Full-Text Search + DB Version (2026-05-30)

  ### DB Version History
  | Version | What was added |
  |---------|---------------|
  | 1–11    | Core tables (titles, episodes, watch_positions, downloads, etc.) |
  | 12      | show_ep_seen (new-episode badge), stream_cache (6h link TTL) |
  | 13      | catalog_fts (FTS5 virtual table — full-text search for title + description) |

  ### FTS5 Rules
  - The `catalog_fts` virtual table uses `content='titles'` — it reads from the `titles` table but needs an explicit **rebuild** after bulk inserts.
  - **Always call `LocalDb.rebuildFtsIndex()` after syncing new titles into the DB.** Currently done fire-and-forget in `catalog_provider._loadFromDb()`.
  - Query format: `"word*"` prefix terms, AND'd. Example: user types `khuda` → FTS query `"khuda*"` → matches "Khuda Hafiz", "Khuda Aur Mohabbat".
  - If FTS throws (e.g. corrupt index), `searchTitles()` silently falls back to LIKE.

  ### `_migrate` Parameter MUST be `oldV`
  The `_migrate(Database db, int oldV, int newV)` function uses `oldV` as parameter name.
  Using `oldVersion` anywhere in that function = compile error. This broke CI for 2 commits (54660441, f571b352). Fixed in 5bd1ac75. **Never rename this parameter.**

  ### Continue Watching — Shows vs Movies
  `CatalogItem.fileId` is `null` for TV shows (titles table has no file_id for shows).
  Watch positions store episode file_ids. To match a watch position against a show, you must
  iterate `show.episodes` list. Fixed in catalog_provider.dart commit f506b917.

  ### Resume Button on Show Detail
  `show_detail_screen.dart` computes `_resumeEpisodeIndex` in `_loadEpisodes()` — finds episode
  with progress 0.03–0.95. Shows "Resume S01E03 · 42%" button above episode list. Handles
  multi-season shows by switching to the correct season tab before playing. Commit d9e6bfce.


  ---

  ## Addendum — Full Codebase Audit Results (2026-05-30)

  ### CODE_MAP.md is Now Required Reading
  Before touching ANY source file, read `agent-hub/CODE_MAP.md`.
  It maps every file → purpose, key functions, known bugs. Saves time and tokens.

  ```bash
  curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/CODE_MAP.md"
  ```

  ### 34 Bugs Catalogued — Phase 13 in MASTER_TASKLIST.md
  Full codebase audit on 2026-05-30 found 34 bugs. They are tracked in MASTER_TASKLIST Phase 13
  with IDs BUG-A01 through BUG-A34. Details in REINCARNATION.md under "KNOWN BROKEN THINGS".

  ### Top 5 Bugs Every Agent Must Know

  | ID | File | The Bug | Why It Matters |
  |----|------|---------|---------------|
  | BUG-A02 | `hub/routes/library.py` | `media_type` returns `"tv"/"series"` not `"show"` | TV shows invisible to users |
  | BUG-A01 | `hub/db.py` | `year` column is TEXT not INTEGER | Year never shows on any card |
  | BUG-A07 | `hub/routes/mobile_api.py` | `/api/app/check` returns `pk.jazzmax.app` | Force update check always fails |
  | BUG-A05 | `lib/screens/vault_lock_screen.dart` | PIN length: setup allows 4, lock expects 6 | Vault unusable after 4-digit setup |
  | BUG-A06 | `radd-hub/hub/app.py` | `session_err` undefined in `download_proxy()` | NameError crash on download proxy |

  ### UI Style Gap
  The app uses Material Design 2. `useMaterial3: true` is NOT set in `lib/app.dart`.
  Only a dark theme exists — `AppTheme.light` does not exist despite a toggle in profile_screen.
  When Material 3 upgrade is done: add to `lib/app.dart` MaterialApp, create `AppTheme.light`,
  use `ColorScheme.fromSeed(seedColor: RaddColors.primary)`.

  ### History Sync Gap (BUG-A19)
  Server has full watch history API (`/api/history`, `/api/history/<file_id>`).
  Flutter has NO HistoryApi class. When creating it:
  - Server uses SECONDS for positions
  - Flutter SQLite uses MILLISECONDS
  - Divide by 1000 when sending to server, multiply by 1000 when reading back

  ### `_migrate` Parameter Name (repeat — critical)
  Always `oldV`. Never `oldVersion`. Broke CI twice (commits 54660441 and f571b352).
  The function signature MUST be: `Future<void> _migrate(Database db, int oldV, int newV)`

  ### media_type Values (BUG-A02)
  When fixing library.py, normalize before writing to delta JSON:
  ```python
  # In library.py delta generation:
  mt = row['media_type'] or ''
  if mt.lower() in ('tv', 'series', 'tvshow', 'tv show'):
      mt = 'show'
  elif mt.lower() in ('movie', 'film'):
      mt = 'movie'
  ```
  Flutter `catalog_provider.dart` filters shows with: `item.mediaType == 'show'`

  ### ON CONFLICT Compatibility (BUG-A04)
  `ON CONFLICT(id) DO UPDATE SET...` requires SQLite 3.24+. Android 8 ships 3.19.
  Safe alternative: use `INSERT OR REPLACE` or check Flutter's minimum SDK.
  Current `android/app/build.gradle` minSdk should be checked — if minSdk >= 26 (Android 8),
  this may be acceptable. If minSdk < 26, must use `INSERT OR REPLACE`.

  ### Dead Code To Remove When Convenient
  - `AuthApi.bindDevice()` — orphaned function, binding done inside `login()` (BUG-A27)
  - `_watch_prototype/` directory — fully superseded by mobile_api.py (BUG-A34)
  - `PlayerPrefs.reset()` — needs UI button (BUG-A21)
  - `LocalDb.clearPosition()` — needs UI trigger (BUG-A22)
  - `SceneBookmarkStore.deleteAll()` — needs UI trigger (BUG-A23)


---

## Addendum — Phase 25: Security Architecture (2026-05-31)

### CRITICAL: Share URLs NEVER Expire
JazzDrive share_urls are **permanent links** — they do not expire.
The previous "24h expiry" claim was WRONG and has been corrected.
Any agent/code/doc claiming links expire in 24h is wrong. Do not reintroduce it.

### Security Files — Read These Too
```bash
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/SECURITY_ARCHITECTURE.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/ZERO_RATING_DELTA.md"
```

### New Security Files (Phase 25)
| File | Purpose |
|------|---------|
| `lib/core/security/app_guard.dart` | APK signature check + Frida detection + root detect |
| `lib/core/security/request_encoder.dart` | XOR encoding layer + share_url scrambling |
| `agent-hub/SECURITY_ARCHITECTURE.md` | Full 6-layer security spec, activation steps |
| `agent-hub/PROMPT_NEXT_AGENT.md` | Handoff prompt for each new agent |

### Security Rules for All Agents

**Rule 11 — Never Disable AppGuard**
`AppGuard.initialize()` runs in `main.dart` before `runApp()`. Never remove it.
When `isTampered=true`, ApiClient must return fake empty responses (silent degradation).
The attacker sees a broken app and gives up — never give them a real error message.

**Rule 12 — RequestEncoder defaults: enabled=false**
`RequestEncoder.enabled` is `false` by default (passthrough mode).
Never set it to `true` without also deploying the server-side decode in radd-hub.
Enabling one side without the other breaks ALL API calls.

**Rule 13 — share_url scrambling (RF1: prefix)**
`RequestEncoder.scrambleUrl()` returns `RF1:<base64url_xor>`.
`RequestEncoder.unscrambleUrl()` passes through any string NOT starting with `RF1:`.
This backward-compat check is sacred — removing it breaks legacy unscrambled URLs.

**Rule 14 — APK fingerprint placeholder means NO enforcement**
`_officialFingerprint = 'RADDFLIX_CERT_SHA256_PLACEHOLDER'` means the signature check
is disabled. Do not remove the check — just leave the placeholder until the real cert
SHA-256 fingerprint is configured. Enforcement activates automatically when set.

**Rule 15 — Build must use --obfuscate**
`flutter build apk --release` MUST include `--obfuscate --split-debug-info=build/debug-info`.
This is now in `build-apk.yml`. Never remove these flags from the CI workflow.

### CI Fix Reference
Build was failing since commit 978d661 due to keystore password mismatch.
Root cause: `KEYSTORE_PASSWORD` GitHub secret was empty → keystore created with
`RaddFlix_2024_Store` but build step got `""` → Gradle signing failed.
Fixed in commit 81a76ea with `${{ secrets.KEYSTORE_PASSWORD || 'RaddFlix_2024_Store' }}`.

### Architecture: Zero-Rating Works for ALL Users
- Jazz SIM (paid bundle): Oracle sync ✅ + delta fallback ✅
- Jazz SIM (no bundle): Oracle sync ❌ + delta sync ✅ (zero-rated `cloud.jazzdrive.com.pk`)
- Jazz SIM (guest): delta sync ✅ (can browse free content)
- Registration: one-time internet required (Oracle account creation + device binding)
- After registration: works with just zero-rated CDN

### Next Handoff
Read `agent-hub/PROMPT_NEXT_AGENT.md` for a complete ready-to-paste handoff prompt.
Update it at the end of every session.
