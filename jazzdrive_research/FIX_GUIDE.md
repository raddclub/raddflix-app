# Jazz Drive 8.0.1 — Bug Fix Guide for Oracle Backend
> Diagnosed from RE + Oracle source code comparison. File paths relative to .

## Bug 1: Upload Response — Missing File ID

### Symptom
After upload, Oracle  tries to extract  or  from the upload response and fails with  or .

### Root Cause (from )
The  response contains:

There is **no uid=1000(runner) gid=1000(runner) groups=1000(runner) field** in the direct upload response. The uid=1000(runner) gid=1000(runner) groups=1000(runner) must be retrieved separately.

### Oracle Code Location
 lines ~783-847 (the fallback listing code already handles this):


### Fix
The listing fallback at the end of  is correct but the primary path before it needs to be extended. When the response has / but no uid=1000(runner) gid=1000(runner) groups=1000(runner), treat it as success and always do the folder listing to find the ID:



---

## Bug 2: Scanner Using Wrong Folder Listing Endpoint

### Symptom
JD scan fails with errors like  or empty results when listing folders/files.

### Root Cause
Oracle  line 502 comment:

But  does NOT have a  endpoint. The correct endpoint is:


### Oracle Code Location
 (line ~544) and  (line ~499).

### Fix
Replace  with .

---

## Bug 3: Scanner  Module Using Legacy API Paths

### Symptom  
Scan completes but finds 0 files, or errors on API calls to non-existent endpoints.

### Root Cause
 imports a  module (line 1: , uses ). The scanner module calls  and  which are redirected via  stubs (lines 23-47). These stubs point to the legacy schema's .

### Fix
Verify  stubs (, ) call the correct SAPI endpoints and that the token storage keys match what the scanner passes in.

---

## Bug 4: Missing  Query Parameter

### Symptom
Subtle: some token rotation responses may not be handled correctly.

### Root Cause
 always appends  to every SAPI URL. Oracle  does not.

### Fix
Add to  in :


---

## Bug 5: Scan Endpoint Paging —  Not Handled

### Symptom
Scan only retrieves the first page of results (typically 100-200 items per page). Users with large libraries get incomplete scans.

### Root Cause
 has a  field:

The scan must check  and increment  until .

### Oracle Code Location
Check  and the legacy  implementation.

### Fix


---

## Bug 6: Token Endpoint URL

### Current Oracle Code
 may use  (older path).

### Fix
Canonical token endpoint from decompilation: 
Both paths likely work but use .

---

## Verification Checklist

- [ ] Upload a test video: confirm file appears in JD web UI after upload
- [ ] Confirm  is captured (not 0) in  table after upload
- [ ] Run JD scan: confirm files are found and counted correctly
- [ ] Check scan handles  pagination
- [ ] Confirm share URL is generated successfully after upload
- [ ] Verify  pings every ≤15 min via 
- [ ] Test token refresh: revoke JSESSIONID manually, verify auto-recovery
