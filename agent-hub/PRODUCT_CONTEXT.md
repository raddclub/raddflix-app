# RaddFlix — Full Product Context
> **Any AI agent reading this: this is your reincarnation document.**
> Read this file completely before touching any code. It contains every decision ever made.
> After this, read MASTER_TASKLIST.md to see what's done and what needs doing.

---

## What is RaddFlix?

RaddFlix is a Pakistani streaming platform. Jazz SIM users stream movies and dramas for **free** — no data bundle needed — because video is served through JazzDrive, which Jazz zero-rates (doesn't charge data for it).

**Previous names (dead, never use): JazzMAX, Zeno**

---

## The Core Trick (Zero-Rating)

Jazz Pakistan zero-rates JazzDrive traffic. This means:
- User has Rs.0 balance
- Opens RaddFlix
- Watches a full movie
- Rs.0 data charged

This is not magic — all video files live on JazzDrive. The app reads JazzDrive share folder URLs from its local SQLite database and generates stream/download links directly. No RaddFlix server involved at playback time.

---

## Streaming Architecture (IMMUTABLE — never change this mental model)

```
RaddFlix Server (92.4.95.252)
  → Does: accounts, subscriptions, data tracking, admin panel, metadata
  → Does NOT: serve video, store stream URLs, proxy streams

JazzDrive CDN (jazzdrive.com.pk)
  → Stores: all video files, in organized share folders
  → Zero-rated: Jazz does not charge data for this traffic
  → Also stores: delta catalog JSON (updated every 24h)

User's Phone (RaddFlix Flutter App)
  → Local SQLite: full catalog + JazzDrive share folder URLs
  → App generates stream/download links LOCALLY from SQLite
  → Streams directly from JazzDrive (zero-rated)
  → No server call at playback time — EVER
```

**The most important secret in the system: JazzDrive share folder URLs stored in SQLite.**
If someone extracts those → they can stream everything without the app.
Protection: SQLCipher encryption + Android Keystore.

---

## Infrastructure

| Component | Location | Tech | Supervisor name |
|-----------|---------|------|----------------|
| Flask admin panel (Radd Hub) | Oracle server /opt/jazzmax/radd-hub/ | Python 3.12 + Flask + SQLite | raddflix_radd (port 5000) |
| Watch API | ~~DECOMMISSIONED 2026-05-30~~ | Migrated to radd-hub port 5000 | — |
| Flutter mobile app | raddflix_flutter/ | Flutter/Dart | N/A (build on dev machine) |
| WhatsApp bot | /opt/jazzmax/wa-bot/ | Node.js 20 | N/A |
| GitHub repo | raddclub/raddflix-app | — | main branch |

**Oracle server IP: 92.4.95.252 | User: ubuntu**
**NOTE: Oracle SSH (port 22) is unreachable from Replit container. All server file changes must go via GitHub API, then manually deployed or auto-deployed.**

---

## Business Model

### Subscription Plans (data-volume based — NO quality tiers)
No 480p/720p/1080p restrictions. Plans are purely data:

| Plan | Data/month | Notes |
|------|-----------|-------|
| Free | Limited catalog + small data | Guest/expired users |
| Basic | 30 GB/month | Entry plan |
| Standard | 50 GB/month | Most popular |
| Premium | 100 GB/month | Power users |

### Jazz Package Comparison (marketing hook)
Jazz sells 30GB for Rs.600, 50GB for Rs.900, 100GB for Rs.1500 — data only, no content.
RaddFlix gives same data PLUS full streaming library for less. This is the value proposition.

### SIMOSA / Jazz World Integration (planned)
SIMOSA (Jazz's daily reward app, previously Jazz World) gives free daily MB:
Day 1: 25MB, Day 2: 50MB, Day 3: 75MB, Day 4: 100MB, Day 5: 125MB, Day 6: 150MB, Day 7: 200MB
= ~725MB/week = ~2.9GB/month free

Plan: Show daily reminder in app → deep link to SIMOSA → 7-day streak tracker → Jazz partnership badge.

---

## Security Architecture

### Goal
Not maximum security — just make the database hard enough to decrypt that:
- Casual root users get nothing useful
- APK decompilers get nothing useful  
- The share folder URLs (most critical secret) stay protected
- Someone CAN watch movies but CANNOT extract the full catalog to build a clone app

### Implementation
| Layer | What | How |
|-------|-----|-----|
| Local SQLite | SQLCipher encryption | Key from Android Keystore (hardware-backed) |
| Delta JSON on JazzDrive | Metadata only | NO share folder URLs, NO file IDs |
| Stream URLs | Generated locally | Never touch the server, never in transit |
| Auth tokens | FlutterSecureStorage | Android Keystore, not SQLite |

### Android Keystore
- Key never leaves secure hardware chip
- Key is bound to app signing certificate
- Modified APK = different key = SQLite unreadable
- Even root access cannot extract the key
- Use package: `flutter_secure_storage` + `sqflite_sqlcipher`

---

## One Account = One Device

- First login: app generates device fingerprint → registers with server
- Second device: server rejects login
- Lost phone / new phone: admin resets device binding, or user does OTP-based switch
- Server table: `device_bindings (user_id, device_id, device_model, bound_at)`

---

## Data Usage Tracking (no media server)

Since JazzDrive serves video directly (not through our server), we cannot count bytes server-side. Solution:

```
Streaming starts
  → App measures every video chunk downloaded (player bytes callback)
  → Every 30s: saves bytes_used to encrypted local SQLite
  → Usage report queued for server sync

User gets any internet
  → App immediately flushes queue to server: POST /api/usage
  → Server adds to monthly counter
  → Server responds: { remaining_gb, plan_limit_gb }
  → App caches this locally

User hits quota (local counter = 0)
  → App blocks all streaming (even zero-rated)
  → Shows: "Plan quota full — tap to sync & verify"
  → Forces server sync before unlocking
  → If plan expired → auto-downgrade to free tier locally

Re-subscribe / renew
  → Requires internet (any amount, even Rs.5)
```

**Tamper protection:** SQLCipher on usage counter + server is authoritative (not app).

---

## Zero-Rated Full Flow

### First install (one time, internet required)
1. User installs app, registers → needs internet for this
2. App downloads full catalog from server → stored in SQLite
3. App downloads poster images in background (100/day limit)
4. Session + quota cached locally

### Every day after (zero-rated mode possible)
```
App opens → reads local SQLite → shows full catalog instantly
        ↓
Tries to fetch delta JSON from JazzDrive (zero-rated)
  → New titles added in last 24h → merged into SQLite
        ↓
User picks something to watch
  → App reads share folder URL from local SQLite
  → Calls JazzDrive API to list files (zero-rated)
  → Gets video URL → streams (zero-rated)
        ↓
Byte counter runs locally
  → Reports to server when internet available
```

---

## Poster Image System

### What's built (poster_service.dart)
- Permanent local storage: `raddflix_posters/title_{id}.jpg`
- Never re-downloads if file already on disk
- `runBackgroundSync()`: downloads up to 100 posters/day when online (called from catalog_provider after load)
- `saveFromJazzDrive()`: saves poster from JazzDrive when stream link generated (zero-rated, free)
- `poster_path` column in local SQLite titles table

### Priority chain
```
Online (has bundle):    Local file → TMDB/OMDB URL download → placeholder
Zero-rated (Rs.0):      Local file → JazzDrive thumbnail (free) → placeholder
```

### Known gaps (NOT YET FIXED — see MASTER_TASKLIST.md)
1. home_screen.dart uses CachedNetworkImage(url) instead of local file path
2. downloadAndCache() never calls LocalDb.savePosterPath() after saving
3. saveFromJazzDrive() exists but is never called from jazzdrive_service.dart

---

## Flutter App File Map

```
raddflix_flutter/lib/
├── main.dart
├── app.dart
├── core/
│   ├── constants.dart          ← AppConstants, JazzDrive URLs, TTLs
│   ├── db/
│   │   ├── local_db.dart       ← SQLite schema, all DB operations
│   │   └── sync_service.dart   ← Server sync logic
│   ├── services/
│   │   ├── jazzdrive_service.dart  ← JazzDrive API, stream link generation
│   │   ├── poster_service.dart     ← Poster download/cache (see gaps above)
│   │   └── notification_service.dart
│   ├── security/
│   │   ├── device_id.dart      ← Device fingerprint generation
│   │   └── keystore.dart       ← Android Keystore wrapper
│   ├── player/                 ← Player prefs, AB loop, bookmarks, etc.
│   └── download/
│       └── download_service.dart
├── providers/
│   ├── catalog_provider.dart   ← Catalog loading, trending, search
│   ├── auth_provider.dart
│   └── subscription_provider.dart
├── screens/
│   ├── player_screen.dart      ← 3400+ lines, MX Player-style UI
│   ├── home_screen.dart        ← Main browsing screen
│   ├── show_detail_screen.dart
│   └── ... (other screens)
└── widgets/
    ├── content_card.dart       ← Poster card, long-press quick view
    └── ...
```

---

## Server File Map

```
/opt/jazzmax/radd-hub/hub/
├── app.py                  ← Flask entry point
├── routes/
│   ├── zero_rating.py      ← Zero-rating manager UI
│   ├── library.py
│   ├── scan.py
│   ├── stream.py
│   └── ...
├── metadata_lookup.py      ← 6-tier enrichment (TMDB→OMDB→AI→IMDbAPI→YouTube→Google KG)
├── metadata.py             ← Secondary enrichment (legacy import)
├── organizer.py            ← File rename/organize
├── downloader.py           ← Download + upload to JazzDrive
├── jazzdrive.py            ← JazzDrive client facade
└── _legacy/                ← !! DO NOT DELETE !! scanner.py imports from here
```

---

## GitHub API Pattern (for Replit agents — no git commands)

```bash
# 1. Get HEAD SHA
HEAD_SHA=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/git/refs/heads/main" \
  | jq -r '.object.sha')

# 2. Get tree SHA
TREE_SHA=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/git/commits/$HEAD_SHA" \
  | jq -r '.tree.sha')

# 3. For large files (>3000 lines): write payload to disk, POST with --data-binary
node -e "
const fs = require('fs');
const content = fs.readFileSync('/tmp/myfile.dart', 'utf8');
fs.writeFileSync('/tmp/blob.json', JSON.stringify({ encoding: 'utf-8', content }));
"
BLOB=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/json" -X POST \
  "https://api.github.com/repos/raddclub/raddflix-app/git/blobs" \
  --data-binary @/tmp/blob.json | jq -r '.sha')

# 4. Create tree
NEW_TREE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/json" -X POST \
  "https://api.github.com/repos/raddclub/raddflix-app/git/trees" \
  -d "{\"base_tree\":\"$TREE_SHA\",\"tree\":[{\"path\":\"path/to/file\",\"mode\":\"100644\",\"type\":\"blob\",\"sha\":\"$BLOB\"}]}" \
  | jq -r '.sha')

# 5. Commit + push (never force)
NEW_COMMIT=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/json" -X POST \
  "https://api.github.com/repos/raddclub/raddflix-app/git/commits" \
  -d "{\"message\":\"your message\",\"tree\":\"$NEW_TREE\",\"parents\":[\"$HEAD_SHA\"]}" \
  | jq -r '.sha')

curl -s -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/json" -X PATCH \
  "https://api.github.com/repos/raddclub/raddflix-app/git/refs/heads/main" \
  -d "{\"sha\":\"$NEW_COMMIT\",\"force\":false}"
```

---

## Secrets (stored in Replit Secrets — never print or commit)
- `GITHUB_TOKEN` — GitHub PAT for raddclub account
- `ORACLE_SSH_KEY` — SSH private key as plain text (no base64 encoding)
- `SESSION_SECRET` — Flask session secret

## Tools Available in Replit Bash
- `jq` v1.7.1 — available, use for GitHub API JSON parsing
- `curl` — available
- `node` — available (use for large file payload writing)
- `python3` — available

