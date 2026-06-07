// ═══════════════════════════════════════════════════════════════════════════════
// Smart Enhance preset definitions — shared between the sheet UI and the
// player's _buildVfString() filter builder.
// ═══════════════════════════════════════════════════════════════════════════════

/// One Smart Enhance content mode — maps to a set of video filter deltas.
class SmartEnhancePreset {
  final String id;
  final String label;
  final String emoji;
  final String description;
  /// Delta added to user's brightness (−1..+1 MPV eq scale).
  final double brightness;
  /// Delta added to user's contrast (−2..+2 MPV eq scale).
  final double contrast;
  /// Delta added to user's saturation (−3..+3 MPV eq scale).
  final double saturation;
  /// Degrees to shift hue (added to user's hue).
  final double hue;
  /// Additional unsharp amount (0.0–1.0). Stacked with user's sharpness.
  final double sharpness;
  /// Whether to add hqdn3d noise reduction filter.
  final bool   noiseReduce;
  /// UI color (hex string, no #) for the mode card.
  final String colorHex;

  const SmartEnhancePreset({
    required this.id,
    required this.label,
    required this.emoji,
    required this.description,
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.hue,
    required this.sharpness,
    required this.noiseReduce,
    required this.colorHex,
  });
}

const kSmartEnhancePresets = <SmartEnhancePreset>[
  SmartEnhancePreset(
    id: 'standard',    label: 'Standard',    emoji: '📺',
    description: 'Subtle all-round boost for any content',
    brightness: 0.02, contrast: 0.08, saturation: 0.12, hue: 0,
    sharpness: 0.18, noiseReduce: false, colorHex: '60A5FA',
  ),
  SmartEnhancePreset(
    id: 'movie',       label: 'Movie',       emoji: '🎬',
    description: 'Cinematic warmth, rich shadows & depth',
    brightness: -0.02, contrast: 0.16, saturation: 0.08, hue: 4,
    sharpness: 0.14, noiseReduce: false, colorHex: 'F59E0B',
  ),
  SmartEnhancePreset(
    id: 'sports',      label: 'Sports',      emoji: '⚽',
    description: 'Vivid colours & razor-sharp motion',
    brightness: 0.0, contrast: 0.22, saturation: 0.32, hue: 0,
    sharpness: 0.38, noiseReduce: false, colorHex: '10B981',
  ),
  SmartEnhancePreset(
    id: 'anime',       label: 'Anime',       emoji: '🎌',
    description: 'Bold palette, clean linework & pop',
    brightness: 0.0, contrast: 0.10, saturation: 0.42, hue: 0,
    sharpness: 0.10, noiseReduce: false, colorHex: 'EC4899',
  ),
  SmartEnhancePreset(
    id: 'low_light',   label: 'Low Light',   emoji: '🌙',
    description: 'Lifts dark scenes, reduces noise',
    brightness: 0.15, contrast: 0.05, saturation: 0.05, hue: 0,
    sharpness: 0.04, noiseReduce: true, colorHex: '8B5CF6',
  ),
  SmartEnhancePreset(
    id: 'amoled',      label: 'AMOLED',      emoji: '📱',
    description: 'Deep crushed blacks, vivid punch',
    brightness: -0.10, contrast: 0.32, saturation: 0.20, hue: 0,
    sharpness: 0.25, noiseReduce: false, colorHex: '6366F1',
  ),
  SmartEnhancePreset(
    id: 'drama',       label: 'Drama',       emoji: '🎭',
    description: 'Warm amber tones & enhanced mood',
    brightness: -0.02, contrast: 0.12, saturation: 0.05, hue: 7,
    sharpness: 0.10, noiseReduce: false, colorHex: 'EF4444',
  ),
  SmartEnhancePreset(
    id: 'documentary', label: 'Documentary', emoji: '🎥',
    description: 'Natural, neutral & highly detailed',
    brightness: 0.05, contrast: 0.12, saturation: 0.08, hue: 0,
    sharpness: 0.22, noiseReduce: false, colorHex: '14B8A6',
  ),
];

/// Returns the preset for [id], or the 'standard' preset as fallback.
SmartEnhancePreset getSmartEnhancePreset(String id) =>
    kSmartEnhancePresets.firstWhere((p) => p.id == id,
        orElse: () => kSmartEnhancePresets.first);
