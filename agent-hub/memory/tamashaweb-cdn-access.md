---
name: tamashaweb CDN access model
description: tamashaweb live streams are globally accessible (any internet/WiFi) — zero-rated only on Jazz SIM, not IP-blocked for non-Jazz traffic
---

# tamashaweb CDN Access Model

**Rule:** tamashaweb CDN streams are globally accessible from any internet connection.
Zero-rating (free data) applies only on Jazz mobile SIM. Non-Jazz users (WiFi, other SIMs) are charged normally — but the streams are NOT blocked.

**Why:** Confirmed 2026-07-24 — DVR audit over Replit environment (non-Jazz IP) successfully fetched M3U8 playlists from all live CDN hosts (`cdn07isb`, `cdn07lhr`, `cdn21lhr`, `cdn22lhr`, `cdn23lhr`, `cdn24lhr`, `cdn05khi`, `cdn12isb`). Same model as JazzDrive (globally reachable, zero-rated on Jazz SIM only).

**How to apply:** Any research task against tamashaweb CDN (DVR audit, rendition URL check, stream format inspection) can be done from Replit or any non-Jazz environment. Do NOT block work on "requires Jazz SIM" — that only applies to zero-rating, not access. Prior plan docs (LIVE_PLAYER_PLAN.md) incorrectly stated "requires Jazz mobile data to access — the CDN checks the source IP" — this was wrong and has been corrected.

**Additional confirmation (2026-07-24):** User opened `cdn05khi.tamashaweb.com:8087/jazzauth/PTVNews-abr/playlist.m3u8` directly in Chrome browser on home WiFi — it played PTV News live video instantly. Chrome v107+ supports HLS natively (no plugin needed). This proves both that streams are accessible from home WiFi and that the HLS format is standard enough for browsers to play directly.
