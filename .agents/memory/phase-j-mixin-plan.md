---
name: Phase J mixin plan
description: Precise J2–J5 mixin extraction plan for player_screen.dart after J-prep part-file split.
---

## Context
After J-prep (panel classes extracted to part files), player_screen.dart is 6,198 lines.
The `_PlayerScreenState` class body contains tightly-coupled method clusters that need
mixin extraction (J2–J5). Cannot use StateNotifier/ChangeNotifier — methods use
`ref`, `context`, `setState()` directly. Correct pattern: `mixin _Foo on ConsumerState<PlayerScreen>`.

## J2: _PlayerPlaybackMixin — abstract declarations needed

The PlaybackMixin calls these methods that STAY in _PlayerScreenState (or future mixins).
Declare them `abstract` in the mixin; the concrete impl is satisfied by _PlayerScreenState.

```
void _applyCompanionSub(String? subPath);     // subtitle cluster (line 1434)
void _scheduleHide();                          // UI cluster (line 1415)
void _startSavePositionTimer();                // prefs cluster (line 1568)
Future<void> _restoreWatchPos();               // position cluster (line 1374)
Future<void> _saveWatchPos();                  // position cluster (line 1351)
void _startAutoRetry();                        // error cluster (line 1777)
void _cancelAutoRetry();                       // error cluster (line 1791)
void _applyAutoOrientation();                  // orientation cluster (line 1822)
void _showInfoSnackbar(String msg);            // UI cluster (line 5736)
void _checkSkipEditor();                       // skip-editor cluster
void _loadSkipEditorPrefs();                   // prefs cluster
void _showEndActionDialog();                   // UI cluster (line 1311)
```

Cross-cluster state var accessors (abstract get/set):
```
bool get _silenceInPipeline;                   // audio-lab var (line 345)
double get _silenceSkipThreshold;              // prefs var (line 312)
String? get _prefSubLang; String? get _prefAudioLang;  // prefs (171-172)
SubtitleTrack? get _selectedSubtitle; set _selectedSubtitle(SubtitleTrack? v);
AudioTrack? get _selectedAudio; set _selectedAudio(AudioTrack? v);
String? get _currentSubFile;                   // subtitle var (line 239)
bool get _backgroundAudio;                     // prefs var (line 381)
WatchPartyRoom? get _watchPartyRoom;           // watch-party var (line 333)
```

## State vars that MOVE to PlaybackMixin (remove from _PlayerScreenState)
Lines ~109-127: _player, _videoCtrl, _np getter, _videoOpened, _playing, _position,
_duration, _buffering, _buffered, _bufferedFraction, _ended, _streamError, _isLinkLoading
Lines ~130-132: _currentEpIdx, _currentFileId, _currentTitle
Line 140: _speed; lines 142-143: _longPressFast, _currentFramedrop
Lines 220-223: _isLocal, _isFree, _trackUsage, _usageTimer
Lines 288-289: _loopEnabled, _isMuted
Lines 293-295: _abA, _abB, _abActive
Lines 301-304: prefetch vars (_prefetchedFileId, _prefetchedStreamUrl, _prefetchInFlight, _prefetchTriggeredForEp)
Line 308: _endAction
Lines 365-366: final List<StreamSubscription> _subs
Lines 368-372: _orientMode, _videoWidth, _videoHeight
Line 375: _posTimer
Lines 397-399: _autoRetryTimer, _autoRetryCountdown
Lines 404-405: _lastPositionMs
Lines 960-962: _eps getter, _hasPrev getter, _hasNext getter

## Methods that MOVE to PlaybackMixin
_startUsageTimer (line 571), _stopUsageTimer (583),
_initPlayer (592–790), _openMedia (796–944), _friendlyError (946),
_playEpisodeAt (964+), _syncNativeAbLoop, _prefetchNextEpisode, _openMediaForEpisode (~1042-1150),
_onVideoCompleted (1271), _setSpeed (~1523),
_saveCurrentPosition, _clearSavedPosition (~1558-1566),
_startAutoRetry (1777), _cancelAutoRetry (1791),
_toggleMute, _toggleLoop (~1796-1814),
_notifyBgState (2057), _setSleepTimer (2071)

## Implementation notes
- Mixin file goes in `lib/screens/player/_ps_playback_mixin.dart` with `part of '../player_screen.dart';`
- Add `part 'player/_ps_playback_mixin.dart';` to player_screen.dart after existing part directives
- Change class declaration to add `, _PlayerPlaybackMixin` to the `with` clause
- SKIP_PREFLIGHT=1 required (same false-positive as panel files)
- Commit build-apk CI must pass before declaring done (Rule 50)

**Why:** Abstract declarations in the mixin are satisfied by _PlayerScreenState's own methods
(the cross-cluster methods haven't been extracted yet). This is the correct incremental approach —
extract one cluster at a time; each cluster's abstract declarations become concrete as other
mixins are added in J3-J5.
