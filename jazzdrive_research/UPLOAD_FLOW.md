# Jazz Drive 8.0.1 — Upload Flow (Reverse Engineered)
> From , , , 

## Overview

The Android app uses a **two-step upload** (binary stream + metadata) via Retrofit + OkHttp:



Wait — re-reading :

 = ,  = ,  = 

This is the **post-upload metadata save** (save-metadata action), not the initial binary upload.

The actual binary upload is via  which sends to an endpoint with binary stream.

## Step 1: Check Quota



Response: 

If  → upload rejected locally before network call.

## Step 2: Pre-Upload Metadata (save-metadata)

### Request


**** path parameter values:
-  — for .mp4, .mkv, .avi, .mov
-  — for .jpg, .png, .gif
-  — for .pdf, .doc, .txt

### Response (UploadResponse model)


**NO uid=1000(runner) gid=1000(runner) groups=1000(runner) field in the upload save-metadata response.**

Status values: =done/updated, =complete, =invalid, =accepted/processing, =validating

## Step 3: Binary Upload (separate call)

The binary stream upload goes to a different endpoint. From  and :



OR via multipart (older/web API approach, used by Oracle):


## Current Oracle  Issues

### Issue 1: Wrong upload endpoint path
- **Oracle uses**:  (no mediaType path param)
- **App uses**:  
- Both may work but the save-metadata endpoint is what the app code shows
- The multipart  appears to be a working web-API path (from  test script)

### Issue 2: Upload response ID extraction
- **Oracle looks for**:  or  in upload response
- **Actual response**:  — no uid=1000(runner) gid=1000(runner) groups=1000(runner) field
- **Fix**: After upload, list the parent folder to find the new file ID

### Issue 3: Missing  parameter
- App always adds  to every SAPI request URL
- Oracle  does not include this
- May cause subtle issues with token rotation detection

## Resume Upload (partial upload)

From :
- Error  = upload in progress (can resume)
-  field in local DB tracks bytes uploaded
- Resume: skip N bytes and re-send from offset via InputStream.skip()

## Upload Error Handling

| HTTP Status | Handling |
|---|---|
|  | Non-recoverable (wrong params) — log error, mark upload failed |
|  | Session expired — attempt token refresh, then retry |
|  | Server internal error — mark upload failed |
|  | Mandatory email not set — block upload, notify user |
|  | T&C not accepted — block upload, notify user |
|  | Item not found (post-upload check) — throws ItemNotFoundException |
|  | Auth failure — re-login flow |
