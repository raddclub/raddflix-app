# JazzDrive SAPI API Reference

**Base URL**: `https://cloud.jazzdrive.com.pk/sapi/`
**Auth**: `?validationkey=<vk>&responsetime=true`
**Cookies**: `JSESSIONID=<jsid>`

## Media Endpoints

### List videos
`GET /sapi/media/video?action=get&parentId={folderId}&folderId={folderId}&responsetime=true`
Response: `{"data": {"videos": [...], "more": true/false}}`
Pagination: add `&offset=N` for subsequent pages

### List all media
`POST /sapi/media?action=get&scoring=true&responsetime=true`
Body: `{"data": {"folderid": N, "mediatype": "video"}}`
Response: `{"data": {"media": [...], "more": true/false}}`

## Upload Endpoints

### Pre-upload registration (get GUID)
`POST /sapi/upload/{mediaType}?action=save-metadata&responsetime=true`
Body: form-encoded `data=<JSON>`
```json
{"data": {"name":"file.mp4","creationdate":"1717200000000","modificationdate":"1717200000000",
          "contenttype":"video/mp4","size":104857600,"folderid":123,"favorite":false,
          "id":null,"clientproperties":[]}}
```
Response: `{"data": {"id": "456789", "success": "1", "status": "..."}}`

### Binary upload
`POST /sapi/upload?action=save&acceptasynchronous=true&responsetime=true`
Body: multipart/form-data with file binary + parentId field
Response: `{"data": {"status": "U", "etag": "abc123", "lastupdate": 1717200000}}`

### Post-upload folder assignment
`POST /sapi/upload/{mediaType}?action=save-metadata&responsetime=true`
Body: form-encoded `data={"data":{"id":"456789","folderid":123}}`

### Rename / update metadata
`POST /sapi/media/{mediaType}?action=save&responsetime=true`
Body: `{"data": {"id": 456789, "name": "NewName.mp4", "favorite": false}}`

## Folder Endpoints

### Create folder
`POST /sapi/media/folder?action=save&responsetime=true`
Body: `{"data": {"name": "FolderName", "parentid": 0}}`
Response: `{"data": {"id": 123, "name": "FolderName"}}`

### List folders (root)
`GET /sapi/media/folder?action=get&parentid=0&responsetime=true`

## System Endpoints

### Storage info
`GET /sapi/system/information?action=get&responsetime=true`
Response: `{"data": {"usedspace": N, "totalspace": N}}`

## Share Endpoints

### Create folder share link
`POST /sapi/link/folder?action=save&responsetime=true`
Body: `{"data": {"folderId": 123}}`
Response: `{"data": {"shareKey": "abc", "url": "https://cloud.jazzdrive.com.pk/f/abc"}}`

### List share links
`GET /sapi/link?action=get&responsetime=true`
