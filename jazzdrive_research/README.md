# JazzDrive Research
> XAPK: Jazz_Drive_8.0.1 · Decompiled 2026-06-11 · jadx 1.5.1 · 29,381 Java files

## Files

| File | Description |
|------|-------------|
| [FINDINGS.md](FINDINGS.md) | Complete RE findings: server config, auth scheme, error codes, Item model |
| [UPLOAD_FLOW.md](UPLOAD_FLOW.md) | Two-step upload flow, request/response format, Oracle bugs |
| [API_REFERENCE.md](API_REFERENCE.md) | All SAPI endpoints with params and response formats |
| [AUTH_FLOW.md](AUTH_FLOW.md) | Full OAuth2 + validationkey + JSESSIONID auth flow |
| [FIX_GUIDE.md](FIX_GUIDE.md) | 6 specific bugs in Oracle backend + how to fix each |
| [HANDOFF.md](HANDOFF.md) | New-agent orientation: server, files, quick-fix steps |

## Key Discoveries

1. **Upload endpoint is ** (POST + JSON body)
2. **Upload response has NO uid=1000(runner) gid=1000(runner) groups=1000(runner) field** — use folder listing to get file ID post-upload
3. **No SSL pinning** — cleartext allowed for jazzdrive.com.pk
4. **Token endpoint**:  (not )
5. **** — credentials go in POST body, not Authorization header
6. **Authorization header**:  (lowercase , not )
7. **Scan pagination**:  field — must loop until 
8. **Status codes**: upload response  ∈ {U=done, C=complete, A=processing, I=invalid, V=validating}

## XAPK Source

Download: https://github.com/raddclub/raddflix-app/releases/tag/jazzdrive-apks-v1

## How to Re-Decompile (Oracle)


