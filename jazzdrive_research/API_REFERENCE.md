# Jazz Drive 8.0.1 — Complete SAPI API Reference
> Reverse-engineered from MediaSapi.java, SapiHandler.java, and other com.funambol.* sources.
> Base URL: 

## Authentication

All authenticated requests require:

Oracle uses  header + Cookie (no Authorization header needed for web API paths).

---

## Media Endpoints

### GET /sapi/media?action=get&scoring=true
List media items. **This is the primary scan endpoint.**

Query params:
-  (required)
-  — max items to return (default varies)
-  — pagination offset
-  — comma-separated list (e.g. )
-  — filter by folder ID
-  — boolean filter
-  — single origin filter
-  — filter by shared label

Response:


---

### GET /sapi/media?action=get-storage-space&softdeleted=true
Get account quota information.

Response:


---

### POST /sapi/media?action=get-validation-status
Check validation status of uploaded items.

Body: 

---

### POST /sapi/media?action=import
Import an item by ID (copy from another source).

Query: 

---

### POST /sapi/media/twins
Find duplicate files by name/size/type.

Body form fields: 

---

### GET /sapi/media/set?action=get
Get a media set (shared folder/album).

Query:  OR  (for public links)

With items: 
With thumbnails: 

---

### POST /sapi/media/set?action=save
Create a media set (album/shared folder).

---

### POST /sapi/media/set?action=update
Update media set permissions.

---

### POST /sapi/media/picture/tag?action=save
Save picture tags (face recognition labels).

---

### POST /sapi/facerecognition?action=mark
Mark face recognition results.

---

## Upload Endpoints

### POST /sapi/upload/{mediaType}?action=save-metadata
Save file metadata after binary upload.

Path param : , , , 

Body:


Response: 

---

### POST /sapi/upload (multipart — web/legacy)
Upload file via multipart form. Used by Oracle backend ().



---

## Login / Auth Endpoints

### POST /sapi/login/oauth?action=login&platform=Android&keytype=oauth2code
Exchange auth code for access token + session.

Query params:
- 
- 
- 
- 

Response includes , ,  (base64-encoded JSON).

---

### GET /sapi/login/oauth?action=login&platform=Android&keytype=accesstoken&key={b64_accesstoken}
Re-login silently using stored access token (no OTP needed).

 = base64()

Response: 

---

### GET /sapi/login/oauth?action=login&platform=web&keytype=accesstoken&key={b64_accesstoken}
Same as above but for web platform.

---

### POST /sapi/login/oauth?action=logout
Log out (invalidate session).

---

### POST /sapi/login?action=login&action=login
Legacy session login (validationkey-based).

---

## Folder Endpoints

### GET /sapi/media/folder?action=get
Get folder contents. *(Not in MediaSapi.java but used by uploader.py)*

Query: 

---

## System Endpoints

### GET /sapi/system/information?action=get
Session health check / system info.

Query: 

Response: 

Used as a keep-alive ping to prevent JSESSIONID expiry.

---

## OAuth2 Endpoints (jazzdrive.com.pk)

### POST https://jazzdrive.com.pk/oauth2/token.php
Refresh access token using refresh_token.

Body (form-urlencoded, ):


Response:


### POST https://jazzdrive.com.pk/oauth2/authorization.php
OAuth2 authorization endpoint (Step 1 of PKCE flow).

### POST https://jazzdrive.com.pk/oauth2/token.php (authorization_code)
Exchange auth code for tokens.


