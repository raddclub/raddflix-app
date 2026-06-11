# JazzDrive Upload Flow — Confirmed from Android APK RE

## Response Models

### `UploadSaveMetadataResponse` (save-metadata response)
```java
@SerializedName("error")   ErrorWrapper error;
@SerializedName("success") String success;
@SerializedName("id")      String id;       // FILE GUID — parse as Long
@SerializedName("status")  String status;
```

### `UploadSaveMetadataRequest` (save-metadata body)
```java
@SerializedName("name")             String name;
@SerializedName("creationdate")     String creationDate;   // epoch ms String
@SerializedName("modificationdate") String modificationDate;
@SerializedName("contenttype")      String contentType;    // "video/mp4"
@SerializedName("size")             long size;
@SerializedName("clientproperties") List<ClientProperty> clientProperties; // []
@SerializedName("folderid")         long folderId;
@SerializedName("favorite")         boolean favorite;      // false
@SerializedName("id")               Long guid;             // null for new file
@SerializedName("picture_score")    PictureScore pictureScore; // null
```

### `UploadResponse` (binary upload response — NO id field)
```java
@SerializedName("error")      ErrorWrapper error;
@SerializedName("status")     String itemStatus;  // "U"/"C"/"A"/"V"/"I"
@SerializedName("etag")       String eTag;
@SerializedName("lastupdate") long lastUpdate;
// NO id/guid field — ID already assigned by pre-upload save-metadata
```

## Android Upload Sequence

```
1. mo107994a(item) → POST /sapi/upload/{mediaType}?action=save-metadata&responsetime=true
   Body: form-encoded  data=<JSON UploadSaveMetadataRequest>  (id=null for new file)
   Response: UploadSaveMetadataResponse.id = FILE GUID

2. mo107996c(item, inputStream) → binary upload stream
   Response: UploadResponse  (status/etag/lastupdate, no id)

3. Fetch item by GUID → GET /sapi/media/{mediaType}/{guid}?action=get
```

## Oracle Backend Implementation

### `_pre_upload_save_metadata()` — new function
- Calls save-metadata before binary upload
- Parses `response["data"]["id"]` → GUID
- Returns `int(guid)` or `None` on failure

### `_upload_file()` decision tree
```
1. _pre_guid = _pre_upload_save_metadata(...)   # try to get GUID first
2. binary_upload()                              # POST multipart
3. if response has "id" field → return it
4. elif _pre_guid → return it (normal case)
5. elif HTTP 200 → listing fallback (find file by name in parent folder)
6. else → raise RuntimeError
```

## Upload Status Codes
- `U` — uploaded (new file)
- `C` — chunked / partial
- `A` — already exists (server dedup)
- `V` — verified
- `I` — invalid
