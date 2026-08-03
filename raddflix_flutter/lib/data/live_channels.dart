// lib/data/live_channels.dart
//
// LiveChannel model + category constants.
//
// Data is served from local SQLite (populated by LiveChannelNotifier on first
// launch and refreshed every hour from Oracle /api/live/channels).
// The old hardcoded kAllLiveChannels list has been removed — the provider is
// the single source of truth.

import 'dart:ui';

class LiveChannel {
  final String id;            // channel_id from Oracle
  final String name;
  final String genre;         // genre_label (e.g. '📰 News')
  final String cat;           // category key (e.g. 'news')
  final String logoUrl;
  final String streamUrl;
  final String backdropColor; // hex string, e.g. '#42A5F5'
  final bool   isFeatured;
  final bool   isFree;        // false = paywalled channel
  final bool   hasDvr;        // true = stream supports DVR timeshift
  final int    dvrWindowSeconds; // max DVR window in seconds (0 if no DVR)
  /// On-device path of the permanently cached logo image.
  /// Null until PosterService has downloaded the logo at least once.
  final String? logoPath;

  const LiveChannel({
    required this.id,
    required this.name,
    required this.genre,
    required this.cat,
    required this.logoUrl,
    required this.streamUrl,
    this.backdropColor    = '#1A1A2E',
    this.isFeatured       = false,
    this.isFree           = true,  // all Oracle channels are free by default
    this.hasDvr           = false,
    this.dvrWindowSeconds = 0,
    this.logoPath,
  });

  /// Parsed backdrop colour — safe fallback to deep navy.
  Color get hexColor {
    final h = backdropColor.replaceAll('#', '');
    if (h.length == 6) {
      return Color(int.parse('FF$h', radix: 16));
    }
    return const Color(0xFF1A1A2E);
  }

  // ── Deserialise from Oracle API response ────────────────────────────────

  factory LiveChannel.fromJson(Map<String, dynamic> j) => LiveChannel(
    id:               j['channel_id']        as String? ?? '',
    name:             j['name']              as String? ?? '',
    genre:            j['genre_label']       as String? ?? '',
    cat:              j['category']          as String? ?? 'entertainment',
    logoUrl:          j['logo_url']          as String? ?? '',
    streamUrl:        j['stream_url']        as String? ?? '',
    backdropColor:    j['backdrop_color']    as String? ?? '#1A1A2E',
    isFeatured:       j['is_featured'] == true || j['is_featured'] == 1,
    isFree:           !(j['is_free'] == false || j['is_free'] == 0),
    hasDvr:           j['has_dvr'] == true || j['has_dvr'] == 1,
    dvrWindowSeconds: j['dvr_window_seconds'] as int? ?? 0,
  );

  // ── Serialise/deserialise for local SQLite ──────────────────────────────

  factory LiveChannel.fromRow(Map<String, dynamic> r) {
    final lp = r['logo_path'] as String? ?? '';
    return LiveChannel(
      id:               r['channel_id']        as String? ?? '',
      name:             r['name']              as String? ?? '',
      genre:            r['genre_label']       as String? ?? '',
      cat:              r['category']          as String? ?? 'entertainment',
      logoUrl:          r['logo_url']          as String? ?? '',
      streamUrl:        r['stream_url']        as String? ?? '',
      backdropColor:    r['backdrop_color']    as String? ?? '#1A1A2E',
      isFeatured:       (r['is_featured']      as int? ?? 0) == 1,
      isFree:           (r['is_free']          as int? ?? 1) == 1,
      hasDvr:           (r['has_dvr']          as int? ?? 0) == 1,
      dvrWindowSeconds: r['dvr_window_seconds'] as int? ?? 0,
      logoPath:         lp.isNotEmpty ? lp : null,
    );
  }

  Map<String, dynamic> toRow() => {
    'channel_id':          id,
    'name':                name,
    'genre_label':         genre,
    'category':            cat,
    'logo_url':            logoUrl,
    'stream_url':          streamUrl,
    'backdrop_color':      backdropColor,
    'is_featured':         isFeatured ? 1 : 0,
    'is_free':             isFree     ? 1 : 0,
    'has_dvr':             hasDvr     ? 1 : 0,
    'dvr_window_seconds':  dvrWindowSeconds,
    // logo_path is NOT written by toRow — it is managed exclusively by
    // PosterService and updated via LocalDb.saveChannelLogoPath().
    // Writing it here would overwrite the cached path on every saveLiveChannels() call.
  };
}

// ── Category constants ────────────────────────────────────────────────────────

class LiveCategory {
  final String id;
  final String label;
  const LiveCategory(this.id, this.label);
}

const kLiveCategories = <LiveCategory>[
  LiveCategory('all',           'All'),
  LiveCategory('sports',        '🏏 Sports'),
  LiveCategory('religious',     '🕌 Islamic'),
  LiveCategory('news',          '📰 News'),
  LiveCategory('entertainment', '🎭 Drama'),
  LiveCategory('kids',          '🧸 Kids'),
  LiveCategory('movies',        '🎬 Movies'),
  LiveCategory('docs',          '🌿 Lifestyle'),
];
