// lib/data/live_channels.dart
//
// LiveChannel model + category constants.
//
// Data is served from local SQLite (populated by LiveChannelNotifier on first
// launch and refreshed every hour from Oracle /api/live/channels).
// The old hardcoded kAllLiveChannels list has been removed — the provider is
// the single source of truth.

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

  const LiveChannel({
    required this.id,
    required this.name,
    required this.genre,
    required this.cat,
    required this.logoUrl,
    required this.streamUrl,
    this.backdropColor = '#1A1A2E',
    this.isFeatured    = false,
    this.isFree        = true,  // all Oracle channels are free by default
  });

  // ── Deserialise from Oracle API response ────────────────────────────────

  factory LiveChannel.fromJson(Map<String, dynamic> j) => LiveChannel(
    id:            j['channel_id']    as String? ?? '',
    name:          j['name']          as String? ?? '',
    genre:         j['genre_label']   as String? ?? '',
    cat:           j['category']      as String? ?? 'entertainment',
    logoUrl:       j['logo_url']      as String? ?? '',
    streamUrl:     j['stream_url']    as String? ?? '',
    backdropColor: j['backdrop_color'] as String? ?? '#1A1A2E',
    isFeatured:    j['is_featured'] == true || j['is_featured'] == 1,
    isFree:        !(j['is_free'] == false || j['is_free'] == 0),
  );

  // ── Serialise/deserialise for local SQLite ──────────────────────────────

  factory LiveChannel.fromRow(Map<String, dynamic> r) => LiveChannel(
    id:            r['channel_id']    as String? ?? '',
    name:          r['name']          as String? ?? '',
    genre:         r['genre_label']   as String? ?? '',
    cat:           r['category']      as String? ?? 'entertainment',
    logoUrl:       r['logo_url']      as String? ?? '',
    streamUrl:     r['stream_url']    as String? ?? '',
    backdropColor: r['backdrop_color'] as String? ?? '#1A1A2E',
    isFeatured:    (r['is_featured']  as int? ?? 0) == 1,
    isFree:        (r['is_free']      as int? ?? 1) == 1,
  );

  Map<String, dynamic> toRow() => {
    'channel_id':     id,
    'name':           name,
    'genre_label':    genre,
    'category':       cat,
    'logo_url':       logoUrl,
    'stream_url':     streamUrl,
    'backdrop_color': backdropColor,
    'is_featured':    isFeatured ? 1 : 0,
    'is_free':        isFree    ? 1 : 0,
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
