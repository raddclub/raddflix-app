# Next Agent Instructions — RaddFlix

## MANDATORY FIRST STEPS — DO NOT SKIP
1. Read REINCARNATION.md for full project context
2. Read AGENT_RULES.md for rules you must follow
3. Read MASTER_PLAN.md for task history
4. Use the user_query popup tool to confirm your plan with the user BEFORE writing any code
5. Always confirm with popup before each major section

## How to read any file
```
curl -H "Authorization: token $GITHUB_TOKEN" https://raw.githubusercontent.com/raddclub/raddflix-app/main/FILENAME
```

## All changes go via GitHub API only. No SSH. No local builds.
Token: $GITHUB_TOKEN env var
Repo: raddclub/raddflix-app, branch: main

## Current state (as of 2026-06-01)
Brand Studio (P6) is fully implemented. All 9 parts are live on main branch.

Admin panel has a new 🎨 Brand Studio section at /brand/ with:
- Live Config tab: color pickers, tagline, logo URL, onboarding pages JSON editor
- Icon & Splash tab: file upload, 3 adaptive icon previews, phone frame mockup
- Build tab: trigger GitHub Actions APK builds from browser, poll status every 8s

Flutter app reads brand_ fields from /api/config on startup and applies:
- brand_splash_color → SplashScreen background
- brand_onboarding_pages → OnboardingScreen pages (falls back to hardcoded)

## Suggested next tasks
1. **P7 — Brand Asset CI Pipeline**: When admin uploads an icon/splash in Brand Studio,
   automatically commit the file to the repo (via GitHub API) so the build-apk workflow
   can pick it up with the brand_build=true flag.
   Files: brand_studio.py (add commit-to-repo logic in upload endpoint)

2. **P8 — Push Notifications**: FCM integration for admin broadcast
   to app users. Admin panel: /broadcast/ already exists for WhatsApp,
   extend it for FCM push.

3. **P9 — App primary color theming**: Flutter app should read brand_primary_color
   from SharedPreferences and apply it as the MaterialApp theme primaryColor
   at app startup, so the whole UI reflects the admin's chosen color.
   File: raddflix_flutter/lib/app.dart or main.dart

## Before starting ANY work
Show the user a popup (user_query tool) summarizing what you're about to do.
