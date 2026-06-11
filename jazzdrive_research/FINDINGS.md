# JazzDrive APK RE — Key Findings

**Source**: Jazz Drive 8.0.1 XAPK decompiled (29,381 Java files)
**Date**: June 2026

## Upload Flow (Confirmed)

### Pre-upload save-metadata → returns file GUID
`POST /sapi/upload/{mediaType}?action=save-metadata`
- Body: form-encoded `data=<URL-encoded JSON>`
- Request class: `UploadSaveMetadataRequest`
- Response class: `UploadSaveMetadataResponse`
  - `id` (String) — server-assigned file GUID ← **THE FILE ID**
  - `success` (String)
  - `status` (String)
  - `error` (ErrorWrapper)

### Binary upload → NO id field in response
`POST /sapi/upload?action=save` (multipart)
- Response class: `UploadResponse`
  - `status` (String) — U/C/A/V/I
  - `etag` (String)
  - `lastupdate` (long)
  - **NO id field** — ID already assigned by pre-upload step

### Android interface `InterfaceC33222a` (UploadClient.kt)
```java
Observable<Long> mo107994a(Item item);   // pre-upload → GUID
Observable<Long> mo107995b(Item item);   // get remote byte offset (resume)
ICancelableUpload mo107996c(Item, InputStream, boolean, long); // binary upload
```

### `ItemUploadTask` execution order
1. `m46417O1()` → `mo107994a(item)` → save-metadata → GUID stored in local DB
2. `m46445Z1()` → `mo107996c(item, inputStream)` → binary upload
3. `m46448a2(guid)` → fetch complete item metadata by GUID

## Scan/List Flow

### `GetMediaWrapper` (media list response)
- `media` — `List<Item>` — the items on this page
- `more` — `boolean` — true if more pages available
Pagination uses `offset` parameter.

### `SapiHandler.m52004k`
Always appends `responsetime=true` to every SAPI URL.

## Authentication
- Android OAuth2 client: `fnbroot` / `f&rW23`
- Token types: `validationkey` (rotates on SEC-1003), `jsessionid`, `refresh_token`
- `refresh_token` valid ~90 days; exchange via POST /oauth2/refresh_token.php
