---
name: RaddFlix DB Migration Rules + Critical Architecture Rules
description: SQLite migration rules, sqflite pin, Android compat, SSH pattern, key architecture decisions
---

## _migrate Parameter Name
_migrate(Database db, int oldV, int newV) — MUST be oldV not oldVersion.
Using oldVersion = compile error. Broke CI twice.
**Why:** Code uses oldV. Comments say oldVersion. AI agents confuse them.
**How to apply:** Every if (oldV < N) block must use oldV.

## sqflite_sqlcipher Version Lock
Exact pin: sqflite_sqlcipher: 3.1.0+1 (no caret).
3.2.x breaks Gradle on Flutter 3.22 CI (flutter.compileSdkVersion not found in LibraryExtension).
**Why:** Pinned after CI broke, diagnosed via pub.dev API.
**How to apply:** Do not upgrade until CI is on Flutter 3.27+.

## Current DB Version
catalogDbVersion = 16 (as of 2026-06-02)
| v14 | vault_items table |
| v15 | Open With / external URI play history |
| v16 | stream_cache CDN URL cache (3h TTL) |
Next version: 17 — add if (oldV < 17) block.

## Android 8 SQLite Compatibility
ON CONFLICT(id) DO UPDATE requires SQLite 3.24+. Android 8 = 3.19-3.22. Crashes.
mergeDeltaTitle() uses SELECT + db.update()/db.insert().
**How to apply:** Never use raw SQL UPSERT if minSdk < 26. Use conflictAlgorithm: ConflictAlgorithm.replace or manual SELECT+UPDATE/INSERT.

## XOR Encoding Rule
ALL API responses are XOR-encrypted. Both sides must always be in sync:
- Flutter: XorInterceptor in api_client.dart (onRequest XOR-encodes body, onResponse XOR-decodes, onError XOR-decodes error body)
- Server: encode_response(data, device_id, status=200) in request_encoding.py
NEVER disable on one side only. NEVER change encoding scheme without deploying both sides.
encode_response() now accepts status kwarg (fixed commit ae96f15e — was hardcoded 200 before).

## JazzDrive share_url — Public Links
share_urls (https://cloud.jazzdrive.com.pk/share/f/XXXXX) are PUBLIC.
Anyone can call /sapi/link/login with the access token from the share URL to get a CDN stream URL.
The server's JazzDrive session expiring (SAPI 401 in logs) ONLY affects new file uploads.
It does NOT affect end users streaming already-uploaded content.
**Why:** User confirmed this 2026-06-02. Zero-rating + public share links = no server login needed for playback.

## SSH Key Pattern
ORACLE_SSH_KEY env var = OPENSSH key with spaces instead of newlines.
Reformat with Node.js (confirmed 2026-06-02):
  node -e "const raw=process.env.ORACLE_SSH_KEY||'';const m=raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);if(m){require('fs').writeFileSync('/tmp/oracle_key',m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n',{mode:0o600});console.log('key ready');}"
Then: ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 "echo OK"

## GitHub Commit Pattern
blob->tree->commit->PATCH ref.
For large files (base64 > ~50KB): use Node.js https module, not curl -d (shell arg size limit).
Always "force": false in PATCH. Never force-push.

## Flask strict_slashes Rule
All Flask blueprint routes with empty string path need strict_slashes=False.
e.g. @bp.route('', strict_slashes=False)
Without it: nginx redirects to trailing-slash URL, client gets 301 instead of 200.
Applies to: bp_rec, bp_hist, bp_usage, bp_pay, and any new blueprint.

## HistoryApi + watched_at Units
Server /api/history GET returns watched_at as epoch SECONDS (not ms).
Always use HistoryApi.watchedAtToDateTime(watchedAt) — it multiplies by 1000.
syncPosition() is fire-and-forget; called from player_screen dispose.

## JWT Secret Persistence
_secret() in mobile_api.py reads from settings table key mobile_jwt_secret.
First server restart after deploy generates + stores the key.
All existing sessions invalidated once — expected, users log in once.

## Real vs Fake Catalog DB
Real: /opt/jazzmax/radd-hub/data/radd_hub.db (SQLCipher — use sudo python3 with hub db.conn())
Fake/legacy (ignore): /opt/jazzmax/radd-hub/data/raddflix.db (empty)

## _legacy/ Files — Required for Server Startup
8 Python files at /opt/jazzmax/radd-hub/hub/_legacy/ are REQUIRED.
Missing = ImportError on startup = supervisor spawn error.
Restore: cd /opt/jazzmax && git pull && sudo supervisorctl restart raddflix_radd
