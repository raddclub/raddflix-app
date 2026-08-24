---
name: JazzDrive host routing
description: JazzDrive OAuth starts on the main jazzdrive.com.pk host and uses cloud.jazzdrive.com.pk for OAuth callback and SAPI/session endpoints.
---

Use `https://jazzdrive.com.pk` for `/oauth2/authorization.php`, `/oauth2/signup.php`, `/oauth2/verify.php`, and `/oauth2/token.php`. Use `https://cloud.jazzdrive.com.pk` for the OAuth callback pages and SAPI/session APIs.

**Why:** Probing the authorization endpoint on the cloud host returns a misleading 404 even though the main OAuth entry point is healthy.

**How to apply:** Keep the authorization/token base and callback redirect host distinct when testing or changing the login flow.