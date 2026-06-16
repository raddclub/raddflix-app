# RaddFlix — Security Architecture

> Permanent spec. Every AI agent and developer must read this before touching
> security-related files. Do not modify without understanding the threat model.

---

## Threat Model

RaddFlix is a streaming platform where **JazzDrive share_urls NEVER expire**
(confirmed architecture — links are permanent). This means:

| Threat | Risk | Mitigation |
|--------|------|-----------|
| Cracked APK redistributing share_urls | HIGH | APK signature check (AppGuard) |
| Frida hooking to extract URLs from memory | HIGH | Frida detection (AppGuard) |
| Man-in-the-middle API interception | MEDIUM | XOR encoding layer (RequestEncoder) |
| SQLCipher DB extraction on rooted device | MEDIUM | SQLCipher + share_url scrambling |
| Mass account sharing | LOW | Device-bound keys + subscription check |
| Oracle server breach | LOW | Delta never contains raw credentials |

The #1 risk is **cracked APK distribution**. Once someone has a working share_url,
they can stream content without the app. Our defense: make cracked APKs return empty
data (silent degradation), so crackers never get working URLs.

---

## Layer 1: APK Integrity (AppGuard)

**File**: `raddflix_flutter/lib/core/security/app_guard.dart`

### What It Does
Checks the APK's signing certificate SHA-256 fingerprint on every cold start.
Original APK is signed with the RaddFlix release keystore. A cracked/repackaged
APK must be re-signed with a different key → different fingerprint → `isTampered = true`.

### Silent Degradation Response
When `isTampered = true`:
- `ApiClient` returns fake empty responses (no crash, no error message)
- Catalog shows 0 items
- Login "fails" with generic network error
- Attacker sees a broken-looking app and gives up
- **We are never alerted** (no telemetry yet — future: ping Oracle with device info)

### Activation Steps
1. Build signed release APK with the official keystore
2. Run: `keytool -printcert -jarfile app-release.apk`
3. Find the `SHA-256:` line (colon-separated hex, e.g., `AA:BB:CC:...`)
4. In `app_guard.dart`: set `_officialFingerprint` to that value
5. Rebuild and distribute the new APK — enforcement is live

### Current Status
⚠️ **NOT ENFORCED** — `_officialFingerprint` is set to placeholder.
Enforcement disabled until the official keystore fingerprint is configured.

---

## Layer 2: Anti-Frida Detection (AppGuard)

**File**: `raddflix_flutter/lib/core/security/app_guard.dart`

### What It Does
Detects Frida dynamic instrumentation framework at startup.

Frida is how attackers hook into apps to:
- Extract JazzDrive URLs from function arguments at runtime
- Bypass subscription checks
- Dump SQLCipher decryption keys from Keystore calls

### Detection Methods
1. **Port probe**: Try TCP connect to `127.0.0.1:27042` (Frida default port)
   - If connects → Frida server running → `isTampered = true`
   - If refused (normal) → pass
2. **Memory scan** (via native channel): Look for Frida agent library in `/proc/self/maps`
   - Requires `MainActivity.kt` to implement `checkFrida` MethodChannel handler

### Native Channel Implementation (TODO)
Add to `MainActivity.kt`:
```kotlin
"checkFrida" -> {
    val maps = File("/proc/self/maps").readText()
    val hasFrida = maps.contains("frida") || maps.contains("gadget") || 
                   maps.contains("gum-js-loop")
    result.success(hasFrida)
}
```

---

## Layer 3: Build Obfuscation

**File**: `.github/workflows/build-apk.yml`

### What It Does
Adds `--obfuscate --split-debug-info=build/debug-info` to the Flutter build command.

Flutter obfuscation:
- Renames all Dart class/method names to meaningless identifiers in the compiled binary
- `AppGuard` becomes `a.b`, `mergeDeltaTitle` becomes `c.d.e`, etc.
- Makes decompiled APK unreadable — attacker can't find security checks to bypass

### Current Status
✅ **ACTIVE** — Added to `build-apk.yml` in Phase 25.

The `--split-debug-info` output goes to `build/debug-info/` inside the CI workspace.
Save this artifact if you need to symbolicate crash stack traces.

---

## Layer 4: share_url Scrambling (RequestEncoder)

**File**: `raddflix_flutter/lib/core/security/request_encoder.dart`

### What It Does
XOR-scrambles JazzDrive share_urls before storing them in local SQLite.

Even if an attacker:
1. Roots the device (bypasses filesystem protection)
2. Extracts the SQLCipher DB file
3. Breaks AES-256 SQLCipher encryption (requires serious hardware + time)

They still see scrambled URLs like `RF1:c2hhcmVfa2V5X3hvcl9lbmNvZGVk...` instead of
working JazzDrive links.

### Format
- Scrambled: `RF1:<base64url(XOR(url, deviceId))>`
- `RF1:` prefix identifies scrambled URLs (vs legacy plain URLs)
- Key = device ID (unique per install) → scraped DB from one device ≠ another device's URLs

### Integration Status
⚠️ **NOT YET WIRED** — `RequestEncoder.scrambleUrl()` and `.unscrambleUrl()` exist
but `local_db.dart` does not yet call them on share_url read/write.

**Next agent task**: Wire scrambling in `local_db.dart`:
- `mergeDeltaTitle()`: `shareUrl = RequestEncoder.scrambleUrl(shareUrl, await DeviceId.get())`
- `getShareUrl()`: `return RequestEncoder.unscrambleUrl(url, await DeviceId.get())`
- `upsertEpisode()`: scramble `ep['share_url']` before insert
- Same for Oracle sync in `_persistItems()`

---

## Layer 5: XOR API Encoding (RequestEncoder)

> ✅ **Server-side deployed** as `radd-hub/hub/request_encoding.py`.  
> ⏸ **Flutter side: `RequestEncoder.enabled = false`** (default).  
> To activate: set `RequestEncoder.enabled = true` in Flutter and deploy both sides together.

**File**: `raddflix_flutter/lib/core/security/request_encoder.dart`

### What It Does
Adds a session-key XOR encoding layer on top of HTTPS for Oracle API calls.

Even if TLS is stripped (via Burp Suite / Charles Proxy SSL pinning bypass):
- Request body appears as garbled base64 (`/tmp/a3Vr...`)
- Session key rotates hourly (derived independently on both sides)
- Without the key derivation formula, the body is unreadable

### Session Key Formula
```
key = SHA-256( "raddflix_xor_v1" + ":" + deviceId + ":" + UTC_day + ":" + UTC_hour )
    → first 32 hex chars
```
Both app and Oracle server derive the same key without communicating.

### Current Status
⚠️ **DISABLED** — `RequestEncoder.enabled = false` (default).

To enable:
1. Implement matching decode/encode in `radd-hub/hub/routes/api.py`
2. Set `RequestEncoder.enabled = true` in Flutter (via RemoteConfig flag)
3. Both sides must be deployed simultaneously — enabling one side alone breaks all API calls

### Server Implementation Spec (for next agent)
```python
# radd-hub/hub/request_encoding.py
import base64, hashlib, datetime

XOR_SEED = "raddflix_xor_v1"

def derive_session_key(device_id: str) -> bytes:
    now = datetime.datetime.utcnow()
    raw = f"{XOR_SEED}:{device_id}:{now.day}:{now.hour}"
    return hashlib.sha256(raw.encode()).hexdigest()[:32].encode()

def xor_decode(encoded: str, device_id: str) -> str:
    data = base64.urlsafe_b64decode(encoded + "==")
    key = derive_session_key(device_id)
    decoded = bytes(b ^ key[i % len(key)] for i, b in enumerate(data))
    return decoded.decode()

def xor_encode(payload: str, device_id: str) -> str:
    data = payload.encode()
    key = derive_session_key(device_id)
    encoded = bytes(b ^ key[i % len(key)] for i, b in enumerate(data))
    return base64.urlsafe_b64encode(encoded).decode()
```

---

## Layer 6: SQLCipher AES-256 (existing, Phase 4)

**Files**: `lib/core/security/keystore.dart`, `lib/core/db/local_db.dart`

### What It Does
- Entire SQLite database file is AES-256 encrypted via SQLCipher
- Encryption key generated on first install via Android Keystore API
- Key is device-bound: cannot be extracted even with root access
- DB file on device is opaque binary — no SQLite browser can open it

### Current Status
✅ **FULLY ACTIVE** since Phase 4 (pinned: `sqflite_sqlcipher: 3.1.0+1`)

---

## Native Channel TODO (MainActivity.kt)

The following MethodChannel handlers need to be added to `MainActivity.kt`
for full AppGuard functionality:

```kotlin
// Add to configureFlutterEngine(), inside security MethodChannel handler:
"getSignatureFingerprint" -> {
    try {
        val pm = packageManager
        val pkgInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            pm.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
        }
        val cert = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            pkgInfo.signingInfo.apkContentsSigners[0].toByteArray()
        } else {
            @Suppress("DEPRECATION")
            pkgInfo.signatures[0].toByteArray()
        }
        val md = java.security.MessageDigest.getInstance("SHA-256")
        val hash = md.digest(cert)
        val fingerprint = hash.joinToString(":") { "%02X".format(it) }
        result.success(fingerprint)
    } catch (e: Exception) {
        result.error("SIGN_CHECK_FAILED", e.message, null)
    }
}
"checkFrida" -> {
    try {
        val maps = java.io.File("/proc/self/maps").readText()
        val hasFrida = maps.contains("frida") || maps.contains("gadget") ||
                       maps.contains("gum-js-loop") || maps.contains("linjector")
        result.success(hasFrida)
    } catch (e: Exception) {
        result.success(false)
    }
}
"checkRoot" -> {
    val suPaths = listOf(
        "/system/bin/su", "/system/xbin/su", "/sbin/su",
        "/data/local/su", "/data/local/bin/su"
    )
    result.success(suPaths.any { java.io.File(it).exists() })
}
```

Register the channel in `configureFlutterEngine`:
```kotlin
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.raddflix.app/security")
    .setMethodCallHandler { call, result ->
        when (call.method) {
            "getSignatureFingerprint" -> { /* ... above ... */ }
            "checkFrida" -> { /* ... above ... */ }
            "checkRoot" -> { /* ... above ... */ }
            else -> result.notImplemented()
        }
    }
```

---

## Security Layers Status Summary

| Layer | Implementation | Status | Blocks Content? |
|-------|---------------|--------|-----------------|
| APK signature check | AppGuard._checkSignature() | ⚠️ Pending fingerprint config | Yes (isTampered) |
| Frida detection | AppGuard._checkFrida() (port+native) | ⚠️ Native channel not wired | Yes (isTampered) |
| Build obfuscation | --obfuscate in CI | ✅ Active | No |
| share_url scrambling | RequestEncoder.scrambleUrl() | ⚠️ Not wired in local_db | No |
| XOR API encoding | RequestEncoder.encode/decode | ✅ Server deployed, Flutter `enabled=false` | Activate via RemoteConfig |
| SQLCipher AES-256 | sqflite_sqlcipher 3.1.0+1 | ✅ Active | No |

---

## What the Next Agent Must Do

1. **Wire MainActivity.kt** — Add the security MethodChannel (above) to `MainActivity.kt`
   for `getSignatureFingerprint`, `checkFrida`, `checkRoot`
2. **Wire share_url scrambling** — In `local_db.dart`: call `RequestEncoder.scrambleUrl()`
   on write and `.unscrambleUrl()` on read for all share_url columns
3. **Get the official fingerprint** — Build signed APK, run keytool, set `_officialFingerprint`
4. ✅ **Server XOR encoding** — `request_encoding.py` deployed in radd-hub. To activate: set `RequestEncoder.enabled = true` in Flutter (RemoteConfig or APK update)

---

## Rules for Future Agents

1. **Never disable AppGuard** — it must run before any network call
2. **Never remove the `RF1:` prefix check** in `unscrambleUrl` — it's backward compatibility
3. **Never put real credentials in delta.json** — delta is public, Oracle DB is private
4. **`RequestEncoder.enabled = false` until server side is deployed** — don't enable unilaterally
5. **The `_officialFingerprint` placeholder means enforcement is OFF** — don't deploy
   to production without setting the real fingerprint
