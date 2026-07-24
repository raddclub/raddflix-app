---
name: LIVE-P6/P7-A blocked on Jazz SIM
description: DVR URL audit and quality rendition research require Jazz mobile data — blocked in Replit.
---

Two remaining live-player tasks cannot be completed from Replit:

**LIVE-P6 — DVR URL audit:**
- All 84 channel stream URLs need to be checked for the `playlist_dvr_timeshift-0-3600.m3u8` variant.
- The tamashaweb CDN requires a Jazz mobile SIM to access (source IP check).
- Currently only `geo-news` is known to have DVR (`has_dvr=1, dvr_window_seconds=3600` set in Oracle seed).
- When Jazz SIM is available: check each channel path, update `has_dvr`/`dvr_window_seconds` in `radd-hub/hub/db.py` `_dvr_channels` dict, then `push_to_oracle.sh`.

**LIVE-P7-A — Quality rendition research:**
- Tamashaweb ABR streams use `-abr/playlist.m3u8` master playlists.
- Need to check whether rendition-level playlists exist (`playlist_720p.m3u8`, `playlist_480p.m3u8`).
- If they exist: build a quality picker sheet. If not: "Auto (ABR)" label only (already implemented in P7-B).
- Requires Jazz SIM to load the URLs.

**Why blocked:** CDN does source-IP verification — non-Jazz traffic gets 403.

**How to apply:** Skip P6 and P7-A until the user can test with a Jazz SIM. P7-B's "Auto (ABR)" label is the correct fallback in the meantime.
