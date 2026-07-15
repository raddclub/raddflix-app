// J3-part: Audio & settings panel classes extracted from player_screen.dart (Phase J)
// ignore_for_file: unused_import
part of '../player_screen.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  AUDIO TRACK PANEL
// ═════════════════════════════════════════════════════════════════════════════

class _AudioTrackPanel extends StatefulWidget {
  final List<AudioTrack> tracks;
  final AudioTrack? selectedTrack;
  final double audioSync;
  final bool useSWDecoder;
  final void Function(AudioTrack?) onTrackSelected;
  final void Function(double) onSyncChanged;
  final void Function(bool) onSWDecoderChanged;
  final void Function(String) onChannelModeChanged;
  final int initialChannelModeIdx;
  final bool isPlaying; // P57-04: disable SW decoder toggle during playback
  final String? currentCodec; // P57-06: show codec badge on active track
  final VoidCallback? onClose;
  final bool isDubMode;        // P60: dub active indicator
  final String dubActiveLang;  // P60: 'ur-PK' or 'hi-IN'
  final VoidCallback? onRemoveDub; // P60: tap to disable dub

  const _AudioTrackPanel({
    required this.tracks,
    required this.selectedTrack,
    required this.audioSync,
    required this.useSWDecoder,
    required this.onTrackSelected,
    required this.onSyncChanged,
    required this.onSWDecoderChanged,
    required this.onChannelModeChanged,
    this.initialChannelModeIdx = 0,
    this.isPlaying = false,
    this.currentCodec,
    this.onClose,
    this.isDubMode = false,
    this.dubActiveLang = 'ur-PK',
    this.onRemoveDub,
  });

  @override
  State<_AudioTrackPanel> createState() => _AudioTrackPanelState();
}

// ═════════════════════════════════════════════════════════════════════════════
//  AUDIO EFFECT PANEL
// ═════════════════════════════════════════════════════════════════════════════

class _AudioEffectPanel extends StatefulWidget {
  final int selectedPreset;
  final List<double> eqBands;
  final bool eqEnabled;
  final void Function(int) onPresetSelected;
  final void Function(int, double) onEqBandChanged;
  final void Function(bool) onEqEnabledChanged;
  final void Function(String?) onReverbChanged;
  final void Function(String) onLabAfChanged;
  final void Function(bool vocal, bool dialogue, bool norm, bool bass, double bassLevel, bool dialogueOnly, bool compress, bool stereoWide, bool noise) onLabStateChanged;
  final double audioBalance;
  final void Function(double) onBalanceChanged;
  // Lab initial state (persisted across panel reopens)
  final bool labVocal;
  final bool labDialogue;
  final bool labNorm;
  final bool labBass;
  final double labBassLevel;
  final bool labDialogueOnly;
  final bool labCompress;
  final bool labStereoWide;
  final bool labNoise;
  final String initialReverbPreset;

  const _AudioEffectPanel({
    required this.selectedPreset,
    required this.eqBands,
    required this.eqEnabled,
    required this.onPresetSelected,
    required this.onEqBandChanged,
    required this.onEqEnabledChanged,
    required this.onReverbChanged,
    required this.onLabAfChanged,
    required this.onLabStateChanged,
    required this.audioBalance,
    required this.onBalanceChanged,
    this.labVocal = false,
    this.labDialogue = false,
    this.labNorm = false,
    this.labBass = false,
    this.labBassLevel = 0.5,
    this.labDialogueOnly = false,
    this.labCompress = false,
    this.labStereoWide = false,
    this.labNoise = false,
    this.initialReverbPreset = 'None',
  });

  @override
  State<_AudioEffectPanel> createState() => _AudioEffectPanelState();
}

class _AudioEffectPanelState extends State<_AudioEffectPanel> {
  int _tab = 0; // 0=Presets 1=Equalizer 2=Lab
  late List<double> _bands;
  late int _preset;
  late bool _eqEnabled;
  // P8: Lab state (initialized from widget props in initState)
  late bool _labVocal;
  late bool _labDialogue;
  late bool _labNorm;
  late bool _labBass;
  late double _labBassLevel;
  late bool _labDialogueOnly;
  late bool _labCompress;
  late bool _labStereoWide;
  late bool _labNoise;

  void _applyLabAf() {
    final parts = <String>[];
    // Vocal remover: phase-cancel center channel (works on stereo content)
    // A4: Scale by 0.5 to prevent 2x amplitude clipping when channels are subtracted.
    if (_labVocal) parts.add('pan=stereo|c0=0.5*c0-0.5*c1|c1=0.5*c1-0.5*c0');
    // Dialogue boost: 10-band equalizer boosting speech-clarity range 2-5kHz
    // MPV equalizer filter syntax: gain values for each of 10 bands
    if (_labDialogue) parts.add('equalizer=0:0:0:0:0:0:3:4:2:0');
    // Audio normalization: dynamic audio normalizer
    if (_labNorm) parts.add('dynaudnorm=f=150:g=15');
    // Bass boost: lavfi low-shelf filter (correct MPV af syntax)
    if (_labBass) {
      final db = (_labBassLevel * 12).round().clamp(1, 12);
      // lavfi aecho for bass: use low-shelf equalizer — 10-band equalizer
      // boosting the low bands (31Hz, 62Hz) by db amount
      parts.add('equalizer=$db:$db:0:0:0:0:0:0:0:0');
    }
    // I1: Dialogue Only — keep centre-channel sum (L+R), mutes music/SFX in stereo field
    if (_labDialogueOnly) parts.add('pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1');
    // I1: Night Audio — soft compressor tames explosions for late-night watching
    if (_labCompress) parts.add('acompressor=threshold=0.089:ratio=9:attack=200:release=1000');
    // I1: Stereo Widener — enhance stereo separation (best with headphones)
    if (_labStereoWide) parts.add('extrastereo=m=2.5');
    // I1: Noise Reduction — spectral denoising for old films / noisy streams
    if (_labNoise) parts.add('afftdn=nf=-25');
    widget.onLabAfChanged(parts.isEmpty ? '' : parts.join(','));
    widget.onLabStateChanged(_labVocal, _labDialogue, _labNorm, _labBass, _labBassLevel,
        _labDialogueOnly, _labCompress, _labStereoWide, _labNoise);
  }

  static const _presetNames = ['Original', 'Treble Boost', 'Bass Boost', 'Clarity', 'Movie', 'Music'];
  static const _presetIcons = [
    Icons.music_note_rounded,
    Icons.arrow_upward_rounded,
    Icons.arrow_downward_rounded,
    Icons.wb_sunny_rounded,
    Icons.local_movies_rounded,
    Icons.library_music_rounded,
  ];

  @override
  void initState() {
    super.initState();
    _bands = List.from(widget.eqBands);
    _preset = widget.selectedPreset;
    _eqEnabled = widget.eqEnabled;
    _labVocal = widget.labVocal;
    _labDialogue = widget.labDialogue;
    _labNorm = widget.labNorm;
    _labBass = widget.labBass;
    _labBassLevel = widget.labBassLevel;
    _labDialogueOnly = widget.labDialogueOnly;
    _labCompress = widget.labCompress;
    _labStereoWide = widget.labStereoWide;
    _labNoise = widget.labNoise;
    // A5: Force MPV to re-apply the full filter chain when the panel opens so
    // MPV live state matches whatever the UI sliders are showing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onEqEnabledChanged(widget.eqEnabled);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab row (title provided by RaddSheet)
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 6, top: 4),
          child: Row(
            children: [
              for (final entry in [
                (label: 'Presets', idx: 0),
                (label: 'Equalizer', idx: 1),
                (label: 'Lab', idx: 2),
              ])
                GestureDetector(
                  onTap: () => setState(() => _tab = entry.idx),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 20, top: 4, bottom: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.label,
                            style: TextStyle(
                              color: _tab == entry.idx ? Colors.white : Colors.white54,
                              fontSize: 13,
                              fontWeight: _tab == entry.idx ? FontWeight.bold : FontWeight.normal,
                            )),
                        const SizedBox(height: RaddSpace.xs),
                        if (_tab == entry.idx)
                          Container(height: 2, width: 32, color: Colors.white),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        const Divider(color: Colors.white12, height: 1),

        if (_tab == 0)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(RaddSpace.md),
              child: GridView.count(
                crossAxisCount: 3,
                childAspectRatio: 1.8,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                children: [
                  for (int i = 0; i < _presetNames.length; i++)
                    GestureDetector(
                      onTap: () {
                        setState(() => _preset = i);
                        widget.onPresetSelected(i);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: _preset == i
                              ? const Color(0xFF3A6ECC).withOpacity(0.6)
                              : const Color(0xFF2A2A2A),
                          borderRadius: RaddRadius.smRadius,
                          border: Border.all(
                            color: _preset == i ? const Color(0xFF4A7EDD) : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_presetIcons[i], color: Colors.white70, size: 18),
                            const SizedBox(width: 6),
                            Text(_presetNames[i],
                                style: TextStyle(
                                  color: _preset == i ? Colors.white : Colors.white70,
                                  fontSize: 12,
                                  fontWeight: _preset == i ? FontWeight.bold : FontWeight.normal,
                                )),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

        // P8: Lab tab content
        if (_tab == 2)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                const Text('Audio Lab', style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 10),
                _LabToggleRow(
                  icon: Icons.mic_off_rounded,
                  title: 'Vocal Remover',
                  subtitle: 'Phase-cancel centre-channel vocals',
                  enabled: _labVocal,
                  onChanged: (v) { setState(() => _labVocal = v); _applyLabAf(); },
                ),
                _LabToggleRow(
                  icon: Icons.record_voice_over_rounded,
                  title: 'Dialogue Boost',
                  subtitle: 'Boosts 2–5 kHz speech clarity',
                  enabled: _labDialogue,
                  onChanged: (v) { setState(() => _labDialogue = v); _applyLabAf(); },
                ),
                _LabToggleRow(
                  icon: Icons.graphic_eq_rounded,
                  title: 'Audio Normalization',
                  subtitle: 'Dynamic normalize — evens loud/quiet scenes',
                  enabled: _labNorm,
                  onChanged: (v) { setState(() => _labNorm = v); _applyLabAf(); },
                ),
                _LabToggleRow(
                  icon: Icons.speaker_rounded,
                  title: 'Bass Boost',
                  subtitle: 'Enhances low-frequency response',
                  enabled: _labBass,
                  onChanged: (v) { setState(() => _labBass = v); _applyLabAf(); },
                ),
                if (_labBass) ...[
                  const SizedBox(height: RaddSpace.xs),
                  Padding(
                    padding: const EdgeInsets.only(left: 52),
                    child: Row(children: [
                      const Icon(Icons.volume_down_rounded, color: Colors.white38, size: 16),
                      Expanded(child: Slider(
                        value: _labBassLevel,
                        min: 0, max: 1, divisions: 10,
                        activeColor: const Color(0xFFE8950A),
                        inactiveColor: Colors.white12,
                        onChanged: (v) { setState(() => _labBassLevel = v); _applyLabAf(); },
                      )),
                      const Icon(Icons.volume_up_rounded, color: Colors.white70, size: 16),
                      SizedBox(width: 36, child: Text(
                        '${(_labBassLevel * 100).toInt()}%',
                        style: const TextStyle(color: Colors.white60, fontSize: 11),
                        textAlign: TextAlign.right,
                      )),
                    ]),
                  ),
                ],
                _LabToggleRow(
                  icon: Icons.hearing_rounded,
                  title: 'Dialogue Only',
                  subtitle: 'Isolates centre-channel speech — mutes music & SFX',
                  enabled: _labDialogueOnly,
                  onChanged: (v) { setState(() => _labDialogueOnly = v); _applyLabAf(); },
                ),
                _LabToggleRow(
                  icon: Icons.nightlight_round,
                  title: 'Night Audio',
                  subtitle: 'Soft compressor — tames explosions for late-night',
                  enabled: _labCompress,
                  onChanged: (v) { setState(() => _labCompress = v); _applyLabAf(); },
                ),
                _LabToggleRow(
                  icon: Icons.spatial_audio_rounded,
                  title: 'Stereo Widener',
                  subtitle: 'Expands stereo image — best with headphones',
                  enabled: _labStereoWide,
                  onChanged: (v) { setState(() => _labStereoWide = v); _applyLabAf(); },
                ),
                _LabToggleRow(
                  icon: Icons.noise_aware_rounded,
                  title: 'Noise Reduction',
                  subtitle: 'Spectral denoising — cleans up old films & noisy streams',
                  enabled: _labNoise,
                  onChanged: (v) { setState(() => _labNoise = v); _applyLabAf(); },
                ),
                const SizedBox(height: 12),
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.orange.withOpacity(0.12),
                    borderRadius: RaddRadius.smRadius,
                    border: Border.all(color: AppColors.orange.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: AppColors.orange, size: 14),
                      SizedBox(width: RaddSpace.sm),
                      Expanded(
                        child: Text(
                          'Lab, EQ and Reverb now stack — all active together.',
                          style: TextStyle(color: AppColors.orange, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                const Divider(color: Colors.white12),
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4, left: 2),
                  child: Text('L / R Balance',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ),
                Row(children: [
                  const Text('L', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  Expanded(child: Slider(
                    value: widget.audioBalance,
                    min: -1.0, max: 1.0, divisions: 20,
                    activeColor: Colors.white, inactiveColor: Colors.white24,
                    onChanged: widget.onBalanceChanged,
                  )),
                  const Text('R', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ]),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: RaddSpace.md),
                    Text(
                      widget.audioBalance.abs() < 0.02
                          ? 'Center'
                          : widget.audioBalance < 0
                              ? 'Left ${(-widget.audioBalance * 100).round()}%'
                              : 'Right ${(widget.audioBalance * 100).round()}%',
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    TextButton(
                      onPressed: () => widget.onBalanceChanged(0.0),
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.white38,
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: const Text('Reset', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ],
            ),
          ),

        if (_tab == 1)
          Expanded(
            child: Column(
              children: [
                // EQ on/off toggle
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      const Text('Equalizer', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const Spacer(),
                      Switch(
                        value: _eqEnabled,
                        onChanged: (v) {
                          setState(() => _eqEnabled = v);
                          widget.onEqEnabledChanged(v);
                        },
                        activeColor: Colors.white,
                      ),
                    ],
                  ),
                ),
                // EQ band sliders
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (int i = 0; i < 5; i++)
                          Expanded(
                            child: Column(
                              children: [
                                Expanded(
                                  child: RotatedBox(
                                    quarterTurns: -1,
                                    child: Slider(
                                      value: _bands[i],
                                      min: -10, max: 10,
                                      divisions: 20,
                                      activeColor: Colors.white,
                                      inactiveColor: Colors.white24,
                                      onChanged: (v) {
                                        setState(() => _bands[i] = v);
                                        widget.onEqBandChanged(i, v);
                                      },
                                    ),
                                  ),
                                ),
                                Text(
                                  ['60Hz', '230Hz', '910Hz', '3.6k', '14k'][i],
                                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                                ),
                                const SizedBox(height: RaddSpace.xs),
                                Text(
                                  '${_bands[i] >= 0 ? '+' : ''}${_bands[i].round()}',
                                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                                ),
                                const SizedBox(height: RaddSpace.sm),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

              // Reverb — real selector
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: _ReverbSelector(onChanged: widget.onReverbChanged, initialPreset: widget.initialReverbPreset),
              ),
              ],
            ),
          ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  QUICK SHORTCUTS PANEL
// ═════════════════════════════════════════════════════════════════════════════

class _QuickShortcutsPanel extends StatefulWidget {
  final bool isLocked;
  final bool isMuted;
  final bool loopEnabled;
  final bool smartEnhanceEnabled;
  final bool isOneHanded;
  final int? sleepTimerMinutes;
  final DateTime? sleepTimerEnd;
  final double speed;
  final Duration? abA;
  final Duration? abB;
  final bool abActive;
  final bool isRotateLocked;
  final VoidCallback onRotate;
  final VoidCallback onLockToggle;
  final VoidCallback onMuteToggle;
  final VoidCallback onLoopToggle;
  final VoidCallback onSmartEnhanceToggle;
  final VoidCallback onOneHandedToggle;
  final void Function(int?) onSleepTimer;
  final void Function(double) onSpeedSelected;
  final VoidCallback onAudioEffect;
  final VoidCallback onSettingsOpen;
  final VoidCallback onAbSet;
  final VoidCallback onFrameStep;
  final VoidCallback? onClose;
  // Extended shortcuts
  final VoidCallback onJumpTo;
  final VoidCallback onSpeedPresets;
  final VoidCallback onEndAction;
  final VoidCallback onScreenshot;
  final VoidCallback? onScreenshotWithSubtitles;
  final VoidCallback onWatchParty;
  final VoidCallback onSilenceSkip;
  final VoidCallback onZoomCrop;
  final VoidCallback onGestureMap;
  final VoidCallback onSkipEditor;
  final VoidCallback onLayoutDesigner;
  final bool silenceSkipEnabled;
  final String endAction;
  final VoidCallback onPiP;
  final VoidCallback onSidebarEdit;

  const _QuickShortcutsPanel({
    required this.isLocked,
    required this.isMuted,
    required this.loopEnabled,
    required this.smartEnhanceEnabled,
    required this.isOneHanded,
    required this.sleepTimerMinutes,
    required this.sleepTimerEnd,
    required this.speed,
    required this.abA,
    required this.abB,
    required this.abActive,
    required this.isRotateLocked,
    required this.onRotate,
    required this.onLockToggle,
    required this.onMuteToggle,
    required this.onLoopToggle,
    required this.onSmartEnhanceToggle,
    required this.onOneHandedToggle,
    required this.onSleepTimer,
    required this.onSpeedSelected,
    required this.onAudioEffect,
    required this.onSettingsOpen,
    required this.onAbSet,
    required this.onFrameStep,
    this.onClose,
    required this.onJumpTo,
    required this.onSpeedPresets,
    required this.onEndAction,
    required this.onScreenshot,
    this.onScreenshotWithSubtitles,
    required this.onWatchParty,
    required this.onSilenceSkip,
    required this.onZoomCrop,
    required this.onGestureMap,
    required this.onSkipEditor,
    required this.onLayoutDesigner,
    required this.silenceSkipEnabled,
    required this.endAction,
    required this.onPiP,
    required this.onSidebarEdit,
  });

  @override
  State<_QuickShortcutsPanel> createState() => _QuickShortcutsPanelState();
}

class _QuickShortcutsPanelState extends State<_QuickShortcutsPanel> {
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    // Refresh every 10s so sleep-timer countdown ticks live (Rule 19: ≤10s)
    _countdownTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final abA = widget.abA; final abB = widget.abB;
    final abActive = widget.abActive;
    final sleepTimerEnd = widget.sleepTimerEnd;
    final speed = widget.speed;
    final isLocked = widget.isLocked;
    final isMuted = widget.isMuted;
    final loopEnabled = widget.loopEnabled;
    final isRotateLocked = widget.isRotateLocked;
    final sleepTimerMinutes = widget.sleepTimerMinutes;
    final smartEnhanceEnabled = widget.smartEnhanceEnabled;
    final isOneHanded = widget.isOneHanded;

    String abLabel = 'A-B';
    if (abA != null && abB == null) abLabel = 'A-B (A set)';
    if (abActive) abLabel = 'A-B ●';

    String sleepLabel = 'Sleep';
    if (sleepTimerEnd != null) {
      final remaining = sleepTimerEnd.difference(DateTime.now());
      if (remaining.isNegative) {
        sleepLabel = 'Sleep';
      } else {
        sleepLabel = 'Sleep ${remaining.inMinutes}m';
      }
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      shrinkWrap: true,
      children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8, top: 4),
                child: Text('Quick Shortcuts', style: TextStyle(color: Colors.white54, fontSize: 12)),
              ),

              // Row 1 of shortcuts
              _ShortcutGrid(
                items: [
                  _ShortcutItem(Icons.screen_rotation_rounded, 'Rotate', isRotateLocked, widget.onRotate),
                  _ShortcutItem(isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded, 'Mute', isMuted, widget.onMuteToggle),
                  _ShortcutItem(Icons.equalizer_rounded, 'Equalizer', false, widget.onAudioEffect),
                  _ShortcutItem(Icons.timer_rounded, sleepLabel, sleepTimerMinutes != null, () {
                    _showSleepTimerDialog(context);
                  }),
                ],
              ),

              const SizedBox(height: RaddSpace.sm),

              // Row 2 of shortcuts
              _ShortcutGrid(
                items: [
                  _ShortcutItem(
                      Icons.speed_rounded,
                      '${speed == speed.roundToDouble() ? speed.toInt() : speed.toStringAsFixed(2)}×',
                      speed != 1.0,
                      () { _showSpeedDialog(context); }),
                  _ShortcutItem(Icons.loop_rounded, 'Loop', loopEnabled, widget.onLoopToggle),
                  _ShortcutItem(Icons.repeat_one_rounded, abLabel, abActive, widget.onAbSet),
                  _ShortcutItem(Icons.lock_rounded, 'Lock', isLocked, widget.onLockToggle),
                ],
              ),

              const SizedBox(height: RaddSpace.sm),

              // Row 3 — advanced
              _ShortcutGrid(
                items: [
                  _ShortcutItem(Icons.skip_next_rounded, 'Frame Step', false, widget.onFrameStep),
                  _ShortcutItem(Icons.smart_display_rounded, 'Smart View', smartEnhanceEnabled, widget.onSmartEnhanceToggle),
                  _ShortcutItem(Icons.settings_rounded, 'Settings', false, widget.onSettingsOpen),
                  _ShortcutItem(Icons.pan_tool_alt_rounded, '1-Hand', isOneHanded, widget.onOneHandedToggle),
                ],
              ),

              const SizedBox(height: RaddSpace.sm),
              const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 6),
                child: Text('Features', style: TextStyle(color: Colors.white54, fontSize: 12)),
              ),

              // Row 4 — navigation features
              _ShortcutGrid(
                items: [
                  _ShortcutItem(Icons.access_time_rounded, 'Jump To', false, widget.onJumpTo),
                  _ShortcutItem(Icons.speed_outlined, 'Speed List', false, widget.onSpeedPresets),
                  _ShortcutItem(Icons.last_page_rounded, 'End Action', widget.endAction != 'play_next', widget.onEndAction),
                  _ShortcutItem(Icons.camera_alt_rounded, 'Screenshot', false, widget.onScreenshot,
                      widget.onScreenshotWithSubtitles),
                ],
              ),

              const SizedBox(height: RaddSpace.sm),

              // Row 5 — audio & silence
              _ShortcutGrid(
                items: [
                  _ShortcutItem(Icons.people_rounded, 'Watch Party', false, widget.onWatchParty),
                  _ShortcutItem(Icons.volume_off_outlined, 'Silence Skip', widget.silenceSkipEnabled, widget.onSilenceSkip),
                  _ShortcutItem(Icons.touch_app_rounded, 'Gestures', false, widget.onGestureMap),
                  _ShortcutItem(Icons.content_cut_rounded, 'Skip Editor', false, widget.onSkipEditor),
                ],
              ),

              const SizedBox(height: RaddSpace.sm),

              // Row 6 — video & layout
              _ShortcutGrid(
                items: [
                  _ShortcutItem(Icons.crop_rounded, 'Zoom & Crop', false, widget.onZoomCrop),
                  _ShortcutItem(Icons.dashboard_customize_rounded, 'Layout', false, widget.onLayoutDesigner),
                  _ShortcutItem(Icons.picture_in_picture_alt_rounded, 'PiP', false, widget.onPiP),
                  _ShortcutItem(Icons.tune_rounded, 'Sidebar', false, widget.onSidebarEdit),
                ],
              ),

            ],
    );
  }

  void _showSleepTimerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        title: const Text('Sleep Timer', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mins in [15, 30, 45, 60, 90, null])
              ListTile(
                title: Text(
                  mins == null ? 'Disable' : '$mins minutes',
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: widget.sleepTimerMinutes == mins
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : null,
                onTap: () {
                  Navigator.of(ctx).pop();
                  widget.onSleepTimer(mins);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showSpeedDialog(BuildContext context) {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        title: const Text('Playback Speed', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in speeds)
              ListTile(
                title: Text('${s == s.roundToDouble() ? s.toInt() : s}×', style: const TextStyle(color: Colors.white)),
                trailing: widget.speed == s ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                onTap: () {
                  Navigator.of(ctx).pop();
                  widget.onSpeedSelected(s);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutItem {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  _ShortcutItem(this.icon, this.label, this.active, this.onTap, [this.onLongPress]);
}

class _ShortcutGrid extends StatelessWidget {
  final List<_ShortcutItem> items;
  const _ShortcutGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: items.map((item) => Expanded(
        child: GestureDetector(
          onTap: item.onTap,
          onLongPress: item.onLongPress,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: item.active ? Colors.white.withOpacity(0.15) : const Color(0xFF2A2A2A),
              borderRadius: RaddRadius.smRadius,
            ),
            child: Column(
              children: [
                Icon(item.icon, color: Colors.white, size: 20),
                const SizedBox(height: RaddSpace.xs),
                Text(item.label, style: const TextStyle(color: Colors.white70, fontSize: 10),
                    textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      )).toList(),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  SETTINGS PANEL
// ═════════════════════════════════════════════════════════════════════════════

class _SettingsPanel extends StatefulWidget {
  final bool showRemainingTime;
  final bool keepScreenOn;
  final int skipInterval;
  final void Function(bool) onShowRemainingChanged;
  final void Function(bool) onKeepScreenChanged;
  final void Function(int) onSkipIntervalChanged;
  final double seekSwipeSec;
  final void Function(double) onSeekSwipeSpeedChanged;
  // P14: accent color + progress bar style
  final int accentColorIdx;
  final int progressBarStyle;
  final void Function(int) onAccentColorChanged;
  final void Function(int) onProgressBarStyleChanged;
  // P12: background audio
  final bool backgroundAudio;
  final void Function(bool) onBackgroundAudioChanged;
  // Night mode + clock
  final bool nightModeEnabled;
  final double nightWarmth;
  final void Function(bool) onNightModeToggle;
  final void Function(double) onNightWarmthChanged;
  final bool showClockInTitle;
  final void Function(bool) onClockToggle;
  // Clock format: 0=Auto (follow device) 1=12-hour 2=24-hour
  final int clockFormat;
  final void Function(int) onClockFormatChanged;
  // Battery HUD
  final bool showBatteryInTitle;
  final void Function(bool) onBatteryToggle;
  final bool batteryChargeAnim;
  final void Function(bool) onBatteryAnimToggle;
  final double initialBrightness;
  final void Function(bool) onShowSkipBtnsChanged;
  final void Function(bool) onShowPrevNextBtnsChanged;
  final void Function(bool) onShowSeekPositionChanged;
  // Initial values for navigation toggles
  final bool showSkipBtns;
  final bool showPrevNextBtns;
  final bool showSeekPosition;
  // Video rotate shortcut
  final VoidCallback onRotateVideo;
  // Gesture toggles
  final bool doubleTapSeekEnabled;
  final bool longPressSpeedEnabled;
  final bool swipeSeekEnabled;
  final bool swipeBVEnabled;
  final void Function(bool) onDoubleTapSeekChanged;
  final void Function(bool) onLongPressSpeedChanged;
  final void Function(bool) onSwipeSeekChanged;
  final void Function(bool) onSwipeBVChanged;
  // Voice commands
  final bool voiceCommandsEnabled;
  final void Function(bool) onVoiceCommandsChanged;
  // Video info (optional — shows in Style tab)
  final VoidCallback? onVideoInfo;

  const _SettingsPanel({
    required this.showRemainingTime,
    required this.keepScreenOn,
    required this.skipInterval,
    required this.onShowRemainingChanged,
    required this.onKeepScreenChanged,
    required this.onSkipIntervalChanged,
    required this.seekSwipeSec,
    required this.onSeekSwipeSpeedChanged,
    required this.accentColorIdx,
    required this.progressBarStyle,
    required this.onAccentColorChanged,
    required this.onProgressBarStyleChanged,
    required this.backgroundAudio,
    required this.onBackgroundAudioChanged,
    required this.nightModeEnabled,
    required this.nightWarmth,
    required this.onNightModeToggle,
    required this.onNightWarmthChanged,
    required this.showClockInTitle,
    required this.onClockToggle,
    required this.clockFormat,
    required this.onClockFormatChanged,
    required this.showBatteryInTitle,
    required this.onBatteryToggle,
    required this.batteryChargeAnim,
    required this.onBatteryAnimToggle,
    required this.initialBrightness,
    required this.onShowSkipBtnsChanged,
    required this.onShowPrevNextBtnsChanged,
    required this.onShowSeekPositionChanged,
    required this.showSkipBtns,
    required this.showPrevNextBtns,
    required this.showSeekPosition,
    required this.onRotateVideo,
    required this.doubleTapSeekEnabled,
    required this.longPressSpeedEnabled,
    required this.swipeSeekEnabled,
    required this.swipeBVEnabled,
    required this.onDoubleTapSeekChanged,
    required this.onLongPressSpeedChanged,
    required this.onSwipeSeekChanged,
    required this.onSwipeBVChanged,
    required this.voiceCommandsEnabled,
    required this.onVoiceCommandsChanged,
    this.onVideoInfo,
  });

  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<_SettingsPanel> {
  int _tab = 0; // 0=Style 1=Screen 2=Controls 3=Navigation
  late bool _showRemaining;
  late bool _keepScreenOn;
  late int _skipInterval;
  late double _seekSwipeSec;
  late int _accentIdx;
  late int _pbStyle;
  late bool _backgroundAudio;
  // Navigation tab real toggles (initialized from widget props in initState)
  late bool _showSkipBtns;
  late bool _showPrevNextBtns;
  late bool _showSeekPosition;
  // Screen tab brightness
  double _screenBrightness = 0.5;

  @override
  void initState() {
    super.initState();
    _showRemaining = widget.showRemainingTime;
    _keepScreenOn = widget.keepScreenOn;
    _skipInterval = widget.skipInterval;
    _seekSwipeSec = widget.seekSwipeSec;
    _accentIdx = widget.accentColorIdx;
    _pbStyle = widget.progressBarStyle;
    _backgroundAudio = widget.backgroundAudio;
    _screenBrightness = widget.initialBrightness;
    _showSkipBtns = widget.showSkipBtns;
    _showPrevNextBtns = widget.showPrevNextBtns;
    _showSeekPosition = widget.showSeekPosition;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab bar (title provided by RaddSheet)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              for (final tab in ['Style', 'Screen', 'Controls', 'Navigation'])
                GestureDetector(
                  onTap: () => setState(() => _tab = ['Style', 'Screen', 'Controls', 'Navigation'].indexOf(tab)),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16, top: 8, bottom: 0),
                    child: Column(
                      children: [
                        Text(tab,
                            style: TextStyle(
                              color: _tab == ['Style', 'Screen', 'Controls', 'Navigation'].indexOf(tab)
                                  ? Colors.white
                                  : Colors.white54,
                              fontSize: 13,
                              fontWeight: _tab == ['Style', 'Screen', 'Controls', 'Navigation'].indexOf(tab)
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            )),
                        const SizedBox(height: 6),
                        if (_tab == ['Style', 'Screen', 'Controls', 'Navigation'].indexOf(tab))
                          Container(height: 2, width: 40, color: Colors.white),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        const Divider(color: Colors.white12, height: 1),

        Expanded(
          child: _tab == 0 ? _buildStyleTab() :
                 _tab == 1 ? _buildScreenTab() :
                 _tab == 2 ? _buildControlsTab() :
                 _buildNavigationTab(),
        ),
      ],
    );
  }

  Widget _buildStyleTab() {
    const accentColors = [Color(0xFFE8950A), Color(0xFF3A8EF5), Color(0xFF34C759), Color(0xFFFF2D55)];
    const accentNames = ['Orange', 'Blue', 'Green', 'Pink'];
    const pbStyles = [
      'Slim', 'Thick', 'Accent',          // 0-2  classic built-in
      'Gradient', 'Bold', 'Waveform',      // 3-5  SeekBarPainter
      'Neon', 'Filmstrip', 'Chapters',     // 6-8
      'Dots', 'Minimal',                   // 9-10
    ];
    return ListView(
      padding: const EdgeInsets.all(RaddSpace.md),
      children: [
        // Video info shortcut (replaces the old top-bar info button)
        if (widget.onVideoInfo != null) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: RaddRadius.smRadius,
              ),
              child: const Icon(Icons.info_outline_rounded, color: Colors.white70, size: 20),
            ),
            title: const Text('Video information',
                style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: const Text('Resolution, codec, stream details',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
            onTap: widget.onVideoInfo,
          ),
          const Divider(color: Colors.white12),
          const SizedBox(height: RaddSpace.sm),
        ],
        // P14: Accent colour picker
        const Text('Accent colour', style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            for (int i = 0; i < accentColors.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GestureDetector(
                  onTap: () {
                    setState(() => _accentIdx = i);
                    widget.onAccentColorChanged(i);
                  },
                  child: Column(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: accentColors[i],
                          shape: BoxShape.circle,
                          border: _accentIdx == i
                              ? Border.all(color: Colors.white, width: 2)
                              : null,
                        ),
                      ),
                      const SizedBox(height: RaddSpace.xs),
                      Text(accentNames[i],
                          style: TextStyle(
                              color: _accentIdx == i ? Colors.white : Colors.white38,
                              fontSize: 10)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        // P14: Progress bar style
        const Text('Progress bar style', style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: RaddSpace.sm),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: List.generate(pbStyles.length, (i) => GestureDetector(
            onTap: () { setState(() => _pbStyle = i); widget.onProgressBarStyleChanged(i); HapticFeedback.selectionClick(); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _pbStyle == i ? Colors.white.withOpacity(0.20) : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _pbStyle == i ? Colors.white60 : Colors.white12,
                  width: _pbStyle == i ? 1.5 : 1,
                ),
              ),
              child: Text(pbStyles[i], style: TextStyle(
                color: _pbStyle == i ? Colors.white : Colors.white54,
                fontSize: 12,
                fontWeight: _pbStyle == i ? FontWeight.w600 : FontWeight.normal,
              )),
            ),
          )),
        ),
      ],
    );
  }

  Widget _buildScreenTab() {
    return ListView(
      padding: const EdgeInsets.all(RaddSpace.md),
      children: [
        const Text('Display', style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: RaddSpace.sm),

        SwitchListTile(
          title: const Text('Show Remaining Time', style: TextStyle(color: Colors.white, fontSize: 14)),
          value: _showRemaining,
          onChanged: (v) {
            setState(() => _showRemaining = v);
            widget.onShowRemainingChanged(v);
          },
          activeColor: Colors.white,
          contentPadding: EdgeInsets.zero,
        ),

        SwitchListTile(
          title: const Text('Keep Screen On', style: TextStyle(color: Colors.white, fontSize: 14)),
          value: _keepScreenOn,
          onChanged: (v) {
            setState(() => _keepScreenOn = v);
            widget.onKeepScreenChanged(v);
          },
          activeColor: Colors.white,
          contentPadding: EdgeInsets.zero,
        ),

        const Divider(color: Colors.white12),
        const SizedBox(height: RaddSpace.sm),
        const Text('Status bar in player', style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: RaddSpace.xs),

        SwitchListTile(
          title: const Text('Show clock / time', style: TextStyle(color: Colors.white, fontSize: 14)),
          value: widget.showClockInTitle,
          onChanged: widget.onClockToggle,
          activeColor: Colors.white,
          contentPadding: EdgeInsets.zero,
        ),
        if (widget.showClockInTitle)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Text('Format', style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(width: 12),
                Expanded(
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Auto')),
                      ButtonSegment(value: 1, label: Text('12h')),
                      ButtonSegment(value: 2, label: Text('24h')),
                    ],
                    selected: {widget.clockFormat},
                    onSelectionChanged: (s) => widget.onClockFormatChanged(s.first),
                    style: SegmentedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.06),
                      selectedBackgroundColor: Colors.white.withOpacity(0.18),
                      foregroundColor: Colors.white54,
                      selectedForegroundColor: Colors.white,
                      textStyle: const TextStyle(fontSize: 12),
                      side: const BorderSide(color: Colors.white12),
                    ),
                  ),
                ),
              ],
            ),
          ),

        SwitchListTile(
          title: const Text('Show battery %', style: TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: const Text('Battery icon + percentage in the top bar', style: TextStyle(color: Colors.white38, fontSize: 11)),
          value: widget.showBatteryInTitle,
          onChanged: widget.onBatteryToggle,
          activeColor: Colors.white,
          contentPadding: EdgeInsets.zero,
        ),
        if (widget.showBatteryInTitle)
          SwitchListTile(
            title: const Text('Charging animation', style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: const Text('Pulsing bolt icon while plugged in', style: TextStyle(color: Colors.white38, fontSize: 11)),
            value: widget.batteryChargeAnim,
            onChanged: widget.onBatteryAnimToggle,
            activeColor: Colors.white,
            contentPadding: EdgeInsets.zero,
          ),
        const Divider(color: Colors.white12),
        const SizedBox(height: RaddSpace.sm),
        const Text('Screen brightness', style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: RaddSpace.xs),
        Row(
          children: [
            const Icon(Icons.brightness_low_rounded, color: Colors.white38, size: 18),
            Expanded(
              child: Slider(
                value: _screenBrightness,
                min: 0.05, max: 1.0,
                activeColor: Colors.white,
                inactiveColor: Colors.white24,
                onChanged: (v) async {
                  setState(() => _screenBrightness = v);
                  await ScreenBrightness().setScreenBrightness(v);
                },
              ),
            ),
            const Icon(Icons.brightness_high_rounded, color: Colors.white, size: 18),
            SizedBox(
              width: 36,
              child: Text(
                '${(_screenBrightness * 100).round()}%',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),

        const Divider(color: Colors.white12),

        SwitchListTile(
          title: const Text('Night mode (eye comfort)', style: TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: const Text('Warm filter — reduces blue light', style: TextStyle(color: Colors.white38, fontSize: 11)),
          value: widget.nightModeEnabled,
          onChanged: widget.onNightModeToggle,
          activeColor: AppColors.orange,
        ),
        if (widget.nightModeEnabled) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Warmth', style: TextStyle(color: Colors.white54, fontSize: 12)),
                Row(children: [
                  const Icon(Icons.wb_sunny_outlined, color: Colors.white38, size: 16),
                  Expanded(child: Slider(
                    value: widget.nightWarmth, min: 0.1, max: 1.0, divisions: 9,
                    activeColor: AppColors.orange, inactiveColor: Colors.white24,
                    onChanged: widget.onNightWarmthChanged,
                  )),
                  const Icon(Icons.wb_sunny_rounded, color: AppColors.orange, size: 16),
                ]),
              ],
            ),
          ),
        ],

        const Divider(color: Colors.white12),

        ListTile(
          title: const Text('Rotate video', style: TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: const Text('Cycles 0° → 90° → 180° → 270°', style: TextStyle(color: Colors.white38, fontSize: 11)),
          trailing: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white24),
            ),
            onPressed: widget.onRotateVideo,
            child: const Text('Rotate'),
          ),
        ),

      ],
    );
  }

  Widget _buildControlsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
      children: [
        _stgSection('Background', items: [
          _stgSwitch(Icons.headphones_rounded,       'Continue audio in background',
              'Audio plays when app is minimised',    _backgroundAudio,
              (v) { setState(() => _backgroundAudio = v); widget.onBackgroundAudioChanged(v); }),
        ]),
        const SizedBox(height: 10),
        _stgSection('Gestures', items: [
          _stgSwitch(Icons.touch_app_rounded,         'Double-tap seek',
              'Double-tap left/right to rewind/forward', widget.doubleTapSeekEnabled,
              widget.onDoubleTapSeekChanged),
          _stgSwitch(Icons.speed_rounded,             'Long press speed boost',
              'Hold to play at 2× speed',             widget.longPressSpeedEnabled,
              widget.onLongPressSpeedChanged),
          _stgSwitch(Icons.swipe_rounded,             'Swipe to seek',
              'Horizontal swipe jumps through video', widget.swipeSeekEnabled,
              widget.onSwipeSeekChanged),
          _stgSwitch(Icons.tune_rounded,              'Swipe brightness / volume',
              'Left edge: brightness  •  Right edge: volume', widget.swipeBVEnabled,
              widget.onSwipeBVChanged),
        ]),
        const SizedBox(height: 10),
        _stgSection('Voice', items: [
          _stgSwitch(Icons.mic_rounded,               'Voice commands',
              'Say "Pause", "Play", "Forward 30" hands-free', widget.voiceCommandsEnabled,
              widget.onVoiceCommandsChanged),
        ]),
      ],
    );
  }

  Widget _buildNavigationTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
      children: [
        _stgSection('Seek', items: [
          _stgSliderRow('Swipe seek range', '${_seekSwipeSec.round()}s',
              _seekSwipeSec.clamp(30.0, 300.0), 30, 300, 9,
              (v) { setState(() => _seekSwipeSec = v); widget.onSeekSwipeSpeedChanged(v); }),
          _stgSliderRow('Skip interval', '${_skipInterval}s',
              _skipInterval.toDouble(), 5, 60, 11,
              (v) { setState(() => _skipInterval = v.round()); widget.onSkipIntervalChanged(v.round()); }),
        ]),
        const SizedBox(height: 10),
        _stgSection('Controls Visibility', items: [
          _stgSwitch(Icons.skip_next_rounded,         'Forward / backward buttons',
              'Show ±skip buttons in centre controls', _showSkipBtns,
              (v) { setState(() => _showSkipBtns = v); widget.onShowSkipBtnsChanged(v); }),
          _stgSwitch(Icons.queue_play_next_rounded,   'Previous / next episode',
              'Episode navigation arrows',             _showPrevNextBtns,
              (v) { setState(() => _showPrevNextBtns = v); widget.onShowPrevNextBtnsChanged(v); }),
          _stgSwitch(Icons.access_time_rounded,       'Seek position label',
              'Timestamp shown above bar while dragging', _showSeekPosition,
              (v) { setState(() => _showSeekPosition = v); widget.onShowSeekPositionChanged(v); }),
        ]),
      ],
    );
  }

  // ── Section / row helpers ──────────────────────────────────────────────────
  static Widget _stgSection(String label, {required List<Widget> items}) => Container(
    margin: const EdgeInsets.only(bottom: 4),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.04),
      borderRadius: RaddRadius.mdRadius,
      border: Border.all(color: Colors.white10),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Text(label, style: const TextStyle(
          color: Colors.white38, fontSize: 11,
          fontWeight: FontWeight.w700, letterSpacing: 0.6)),
      ),
      ...items,
      const SizedBox(height: RaddSpace.xs),
    ]),
  );

  Widget _stgSwitch(IconData icon, String title, String subtitle, bool value,
      ValueChanged<bool> onChanged) =>
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07), borderRadius: BorderRadius.circular(7)),
          child: Icon(icon, color: Colors.white54, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 13)),
          Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ])),
        Switch(value: value, onChanged: onChanged, activeColor: Colors.white,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      ]),
    );

  Widget _stgSliderRow(String label, String valueStr, double value,
      double min, double max, int divisions, ValueChanged<double> onChanged) =>
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const Spacer(),
          Text(valueStr, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2.5,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(value: value, min: min, max: max, divisions: divisions,
              activeColor: Colors.white, inactiveColor: Colors.white24,
              onChanged: onChanged),
        ),
      ]),
    );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Shared small widgets
// ═════════════════════════════════════════════════════════════════════════════

class _SyncBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SyncBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _AudioTrackPanelState extends State<_AudioTrackPanel> {
  late double _sync;
  late bool _useSW;
  late int _chIdx;

  @override
  void initState() {
    super.initState();
    _sync = widget.audioSync;
    _useSW = widget.useSWDecoder;
    _chIdx = widget.initialChannelModeIdx;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      children: [
              // P60: Dub active indicator + one-tap remove
              if (widget.isDubMode)
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D2B0D),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF00C853).withOpacity(0.55)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.record_voice_over_rounded,
                          color: Color(0xFF00C853), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Dub Active',
                                style: TextStyle(
                                    color: Color(0xFF00C853),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                            Text(
                              widget.dubActiveLang == 'ur-PK'
                                  ? '🇵🇰 Urdu dub is playing'
                                  : '🇮🇳 Hindi dub is playing',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: widget.onRemoveDub,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Remove',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              // Track list
              if (widget.tracks.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(RaddSpace.md),
                  child: Text('No audio tracks found.', style: TextStyle(color: Colors.white54)),
                ),

              // Select by index rather than by AudioTrack `==` — media_kit can
              // emit new track-list instances across updates, so comparing
              // object equality directly was unreliable and left the "active"
              // radio dot unlit even when a track really was selected. Index
              // matched by track id is robust regardless of instance identity.
              Builder(builder: (_) {
                final selectedIdx = widget.selectedTrack?.id == null
                    ? -1
                    : widget.tracks.indexWhere((t) => t.id == widget.selectedTrack!.id);
                return Column(children: [
                  for (int i = 0; i < widget.tracks.length; i++)
                    RadioListTile<int>(
                      value: i,
                      groupValue: selectedIdx,
                      onChanged: (v) => v != null ? widget.onTrackSelected(widget.tracks[v]) : null,
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              (widget.tracks[i].language != null && widget.tracks[i].title != null)
                                  ? '${widget.tracks[i].language} (${widget.tracks[i].title})'
                                  : widget.tracks[i].language ?? widget.tracks[i].title ?? 'Audio track ${i + 1}',
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                            ),
                          ),
                          // P57-06: codec badge on active track
                          if (i == selectedIdx && widget.currentCodec != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                widget.currentCodec!.toUpperCase(),
                                style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w600),
                              ),
                            ),
                        ],
                      ),
                      activeColor: Colors.white,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),

                  const Divider(color: Colors.white12),

                  // Disable
                  RadioListTile<int>(
                    value: -1,
                    groupValue: selectedIdx,
                    onChanged: (_) => widget.onTrackSelected(null),
                    title: const Text('Disable', style: TextStyle(color: Colors.white, fontSize: 14)),
                    activeColor: Colors.white,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ]);
              }),

              const Divider(color: Colors.white12),

              // SW decoder toggle — always enabled; handles DTS/EAC-3/TrueHD/MLP
              SwitchListTile(
                title: const Text('Use SW audio decoder', style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: Text(
                  widget.isPlaying
                      ? 'Seek forward to fully apply'
                      : 'Required for DTS, EAC-3, TrueHD, MLP',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                value: _useSW,
                onChanged: (v) {
                  setState(() => _useSW = v);
                  widget.onSWDecoderChanged(v);
                },
                activeColor: Colors.white,
              ),

              const Divider(color: Colors.white12),

              // Audio channel mode
              ListTile(
                title: const Text('Channel mode', style: TextStyle(color: Colors.white, fontSize: 14)),
                trailing: Text(
                  const ['Stereo', 'Mono', 'Left only', 'Right only'][_chIdx],
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                onTap: () {
                  const filters = ['', 'pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1', 'pan=stereo|c0=c0|c1=c0', 'pan=stereo|c0=c1|c1=c1'];
                  setState(() => _chIdx = (_chIdx + 1) % 4);
                  widget.onChannelModeChanged(filters[_chIdx]);
                },
              ),

              const Divider(color: Colors.white12),

              // AV Sync
              Padding(
                padding: const EdgeInsets.all(RaddSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Synchronization', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _SyncBtn(label: '−', onTap: () {
                          setState(() => _sync -= 0.1);
                          widget.onSyncChanged(-0.1);
                        }),
                        const SizedBox(width: RaddSpace.md),
                        Text('${_sync.toStringAsFixed(1)}s',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(width: RaddSpace.md),
                        _SyncBtn(label: '+', onTap: () {
                          setState(() => _sync += 0.1);
                          widget.onSyncChanged(0.1);
                        }),
                      ],
                    ),
                  ],
                ),
              ),
            ],
    );
  }
}
// ═════════════════════════════════════════════════════════════════════════════
//  _ReverbSelector — reverb room presets (Feature 23)
// ═════════════════════════════════════════════════════════════════════════════

class _ReverbSelector extends StatefulWidget {
  final void Function(String?) onChanged;
  final String initialPreset;
  const _ReverbSelector({required this.onChanged, this.initialPreset = 'None'});

  @override
  State<_ReverbSelector> createState() => _ReverbSelectorState();
}

// ═════════════════════════════════════════════════════════════════════════════
//  P8: _LabToggleRow — simple toggle row for Audio Lab tab
// ═════════════════════════════════════════════════════════════════════════════

class _LabToggleRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _LabToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: enabled ? Colors.white.withOpacity(0.14) : Colors.white.withOpacity(0.05),
              borderRadius: RaddRadius.smRadius,
            ),
            child: Icon(icon, color: enabled ? Colors.white : Colors.white38, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(
                    color: enabled ? Colors.white : Colors.white70,
                    fontSize: 13, fontWeight: FontWeight.w600)),
                Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 10)),
              ],
            ),
          ),
          Switch(value: enabled, onChanged: onChanged, activeColor: Colors.white),
        ],
      ),
    );
  }
}

class _ReverbSelectorState extends State<_ReverbSelector> {
  late String _selected;
  static const _presets = ['None', 'Small Room', 'Hall', 'Cathedral', 'Stadium'];

  @override
  void initState() {
    super.initState();
    _selected = widget.initialPreset;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('Reverb', style: TextStyle(color: Colors.white70, fontSize: 13)),
        const Spacer(),
        DropdownButton<String>(
          value: _selected,
          dropdownColor: const Color(0xFF2A2A2A),
          style: const TextStyle(color: Colors.white54, fontSize: 13),
          underline: const SizedBox.shrink(),
          icon: const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
          items: _presets.map((p) => DropdownMenuItem(
            value: p,
            child: Text(p, style: const TextStyle(color: Colors.white)),
          )).toList(),
          onChanged: (v) {
            setState(() => _selected = v ?? _selected);
            widget.onChanged(v == 'None' ? null : v);
          },
        ),
      ],
    );
  }

}

