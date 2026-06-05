---
## Session: 2026-06-04 — Bug Investigation and Fixes

BUG #4 FIXED: Screen goes black after 2-3s of local video playback
  Root cause: _checkQuota() was checking sub_expires_at for ALL localPath cases
  including user-owned local folder files (fileId empty). Stale quota cache
  fired pushReplacementNamed(planExpired) 1-3s in, killing the player screen.
  Fix: added widget.fileId.isNotEmpty guard. Commit: 6808fc1

BUG #3 FIXED: Initial 1-2s black screen on local video
  Root cause: androidAttachSurfaceAfterVideoParameters:false attaches surface
  before first frame is decoded. Buffering spinner showed but video was black.
  Fix: wrapped Video in AnimatedOpacity that starts at 0.0 and fades in at 400ms
  once _playing becomes true. Commit: 6808fc1

BUG #2 DATA ISSUE: Missing episodes All Of Us Are Dead
  Oracle DB has S01E01,E02,E06,E07,E08,E10,E11,E12 — NO E03,E04,E05,E09
  Need to upload those 4 episodes to JazzDrive and sync to DB.

BUG #1 NETWORK ISSUE: JazzDrive fails without Jazz SIM
  cloud.jazzdrive.com.pk requires Jazz SIM. Code is correct.

Rules confirmed: androidAttachSurfaceAfterVideoParameters stays false,
sqflite_sqlcipher stays at 3.1.0+1, Oracle via SSH tunnel only.
