---
name: Infrastructure Constraints & Known Limitations
description: Hard facts about the production stack that every agent must know before touching security, networking, or API code — things that look like bugs but are deliberate or blocked by real-world constraints.
---

# Infrastructure Constraints & Known Limitations

## TLS / HTTPS — Not yet available
- **The production API runs over plain HTTP on a bare IP: `http://92.4.95.252`.**
- There is **no domain name** registered for this server yet.
- There is **no TLS certificate** — self-signed, Let's Encrypt, or otherwise.
- `constants.dart` `kBaseUrl` and `remote_config.dart` both use the plain HTTP URL intentionally — this is not an oversight, it is the current production reality.
- **Do NOT change these URLs to HTTPS** until the user has acquired a domain and provisioned a certificate. Switching to HTTPS prematurely will break all app connectivity.
- SEC-01 in TASKS.md tracks this as a known CRITICAL issue. When the user is ready to fix it, the steps are: (1) point a domain at 92.4.95.252, (2) provision a cert (Certbot / Let's Encrypt works fine on Oracle), (3) configure nginx/Flask to terminate TLS, (4) update `kBaseUrl` and `remote_config.dart`.

**Why:** The Oracle VPS does not have a domain name. Let's Encrypt requires domain validation — it cannot issue a cert for a bare IP. The owner is aware and has accepted the risk in the interim.

## APK Signature Check — Placeholder, not a mistake
- `app_guard.dart` contains `RADDFLIX_CERT_SHA256_PLACEHOLDER` as the expected signing fingerprint.
- The tamper-detection check is **intentionally disabled** because the release signing cert SHA-256 has not been extracted and hardcoded yet.
- SEC-05 in TASKS.md tracks this. When fixing: run `keytool -printcert -jarfile app-release.apk` to extract the SHA-256 and replace the placeholder.
- Do NOT remove the check — just leave the placeholder until the cert SHA is available.

## XOR Obfuscation Layer — Intentional, not encryption
- `request_encoder.dart` uses XOR with seed `raddflix_xor_v1` as a request obfuscation layer.
- This is **not intended as encryption** — it is obfuscation. The owner is aware it is reversible.
- The seed is hardcoded intentionally; moving it to a native string is a future improvement, not an urgent bug.
- Once HTTPS is in place (SEC-01), the XOR layer's security value is largely moot. Do not propose removing it without confirming with the user — it may serve as a simple API gating mechanism.

## XOR Key Clock Sensitivity — Known fragility
- The XOR session key rotates by UTC hour. Device clock skew ≥1 hour breaks all API calls.
- This is a known design fragility (BUG-XOR-CLOCK in TASKS.md). The server currently does not accept a ±1h window.
- Do not "fix" the client-side key derivation without a coordinated server-side change — they must stay in sync.

## Oracle VPS — No auto-deploy, no public port 5000
- Flask runs on port 5000, **localhost only** — not public. All API access from the app goes through the nginx/Flask stack on 92.4.95.252:80 (HTTP).
- Oracle does NOT auto-deploy on `git push`. Run `push_to_oracle.sh` explicitly and verify with `git rev-parse HEAD` on the server. See OPERATIONS.md §5.
- Supervisor service name: `raddflix_radd`. Restart: `sudo supervisorctl restart raddflix_radd`.

## Voice Commands — Intentional stub
- `voice_commands_service.dart` `requestPermission()` always returns `false`; `start()` is a no-op.
- This is an **incomplete feature**, not a bug introduced accidentally. The UI toggle is wired up but the backend implementation does not exist yet.
- BUG-VOICE-STUB in TASKS.md. Fix: hide the setting in release builds or add a "Coming Soon" label — do not attempt to implement voice recognition without explicit user instruction.

## Flutter SDK — Not available in this Replit environment
- There is no Flutter SDK / Dart SDK in this Replit workspace.
- `preflight_check.sh` is a heuristic script (not a real compiler) that catches two known repeat-mistake patterns: missing design-token imports and invalid `const SomeStaticClass.x` usage. It is NOT a substitute for CI.
- **Never claim a Dart/Flutter change is "verified"** based on preflight_check.sh alone. Rule 46 requires checking the actual GitHub Actions CI run after every Flutter push.
- Two tasks permanently blocked by missing SDK: G4 (folder reorg) and K5 (const sweep).

## Vault PIN Hashing — Static salt, known weakness
- Vault PINs are hashed as `SHA-256("raddflix_vault_salt_" + pin)` with a static hardcoded salt.
- SEC-04 in TASKS.md. The fix (per-user random salt + PBKDF2) requires a one-time migration of existing hashes — coordinate with the user before implementing, since existing vaults will need re-PINning.

## Profile PINs — Stored plaintext in SQLite
- Profile switch PINs are stored as raw plaintext in the local SQLite DB (not in flutter_secure_storage).
- BUG-PROFILE-PIN in TASKS.md. Fix requires a DB migration to store hashes — existing PINs are lost in migration; users must re-set them.

## Unauthenticated Tamper-Report Endpoint
- `/api/security/tamper-report` on the Flask server accepts unauthenticated POST requests by design.
- It is intentionally open so tampered APKs (which would not have valid auth tokens) can still phone home.
- Rate limiting has not been implemented on the server side. Noted as a known DoS vector.

## Debug Diagnostics Screen — Exposed to all users (known, to be fixed)
- The 5-tap-on-version-text gesture opens a full diagnostics screen in all builds, including production.
- SEC-02 in TASKS.md. This IS a bug — not a deliberate choice — and should be gated behind `kDebugMode`. Has not been fixed yet.

## `_isFree` Revenue Bug — Unverified in mixin-split layout
- Previously confirmed that the `_isFree` flag is not reset on content transition (player_screen.dart ~L1099–1105).
- Phase J split the monolithic player into 8 mixin/part files. The exact location of this logic in the new layout has not been re-verified.
- BUG-FREE-EP-02 in TASKS.md. Must be found and fixed before any premium content enforcement work.
