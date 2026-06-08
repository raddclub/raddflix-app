# Memory Index

- [Player local-file black screen bugs](player-local-bugs.md) — BUG #3 + #4 root causes and fixes in player_screen.dart
- [Oracle DB structure](oracle-db.md) — radd_hub.db backup has all catalog data; live raddflix.db is empty (sync target)
- [JazzDrive share validation](jazzdrive-connectivity.md) — cloud.jazzdrive.com.pk reachable from any IP but share keys return MED-1011 without Jazz SIM.
- [JazzDrive Pass3 escape bug](jazzdrive-pass3-bug.md) — Dart \$ in non-raw strings = literal dollar, not interpolation; Pass3 was dead.
- [Admin panel anchor quirks](admin-panel-anchors.md) — setState block has _resumeEpisodeIndex between _watchProgress and _loading; skip-condition must check for method signature not call site.
- [Dart reserved field names](dart-field-name-pitfalls.md) — naming a widget field override shadows the @override annotation causing compile error; use statusOverride or similar.
- [Proxy pool bypass mode](warp-tunnel.md) — JAZZDRIVE_PROXY_BYPASS=1 in DB disables hc/recovery/disc threads; 33k proxies caused 6GB RAM / 60% CPU when left running unused.
- [Keepalive interval is DB-driven](keepalive-config.md) — keepalive_interval_min in settings table; code reads it at startup and end of each cycle; default was hardcoded 15 min, now 360 min.
- [upload_to_jazzdrive direct call](jazzdrive-session-vk.md) — queue_manual_upload() uses daemon threads; call upload_to_jazzdrive(Path(...), account_id=N, auto_delete=False) directly for blocking re-upload from Python scripts.
- [JazzDrive delete/trash quirks](jazzdrive-file-delete.md) — trash_files() is false-positive for both file-type AND video-type; always use delete_files_permanent()
- [JazzDrive duplicate upload guard](jd-dup-guard.md) — both upload paths (_upload_pending + upload_to_jazzdrive) now have JD-side pre-check; guard logic and line numbers
- [JazzDrive file listing](jd-file-listing.md) — /media/video blind to mediatype=file items; use /media/file?action=get + list_all_files_in_folder() for non-video files
