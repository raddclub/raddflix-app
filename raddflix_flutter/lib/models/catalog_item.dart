/// Normalise raw media_type strings from server/TMDB to the two canonical
/// values the app understands: 'movie' or 'show'.
String _normalizeMediaType(String? raw) {
  switch ((raw ?? '').toLowerCase().trim()) {
    case 'tv':
    case 'series':
    case 'show':
      return 'show';
    default:
      return 'movie';
  }
}

class CatalogItem {
  final int id;
  final String title;
  final int? year;
  final String mediaType;
  final String? description;
  final double? rating;
  final String? genres;
  final String? posterUrl;
  final bool isFree;
  final int dbVersion;
  final List<Map<String, dynamic>> episodes;
  final String? fileId;
  final String? shareUrl;
  final String? posterPath;
  final String? language;
  final bool? isNew;
  final double? watchProgress;
  final bool? isUploading;
  final String? status;
  final bool? isOngoing;
  /// Number of episodes added since user last viewed this show.
  /// null = not computed. 0 = nothing new. >0 = badge shown.
  final int? newEpisodeCount;
  /// Total episode count from Oracle catalog (may exceed locally-available count).
  /// Used to show "Coming Soon" banner when episodes haven't been uploaded yet.
  final int? episodeCount;

  const CatalogItem({
    required this.id,
    required this.title,
    this.year,
    required this.mediaType,
    this.description,
    this.rating,
    this.genres,
    this.posterUrl,
    this.isFree = false,
    this.dbVersion = 0,
    this.episodes = const [],
    this.fileId,
    this.shareUrl,
    this.posterPath,
    this.language,
    this.isNew,
    this.watchProgress,
    this.isUploading,
    this.status,
    this.isOngoing,
    this.newEpisodeCount,
    this.episodeCount,
  });

  bool get isMovie      => mediaType == 'movie';
  bool get isShow       => mediaType == 'show';
  bool get isOngoingNow => isOngoing == true || status == 'ongoing';
  bool get isCompleted  => status == 'completed';

  String get statusLabel {
    switch (status) {
      case 'ongoing':   return 'ONGOING';
      case 'completed': return 'COMPLETED';
      case 'cancelled': return 'CANCELLED';
      default:          return '';
    }
  }

  String get displayYear   => year != null ? year.toString() : '';
  String get displayRating => rating != null ? rating!.toStringAsFixed(1) : '';

  factory CatalogItem.fromJson(Map<String, dynamic> json) {
    final episodesRaw = json['episodes'] as List<dynamic>? ?? [];
    return CatalogItem(
      id:          (json['id'] as int? ?? (int.tryParse(json['id']?.toString() ?? '') ?? 0)), // FIX-ID-CAST: safe cast — null id defaults to 0 instead of TypeError crash
      title:       json['title'] as String? ?? '',
      year:        json['year'] == null ? null : int.tryParse(json['year'].toString()),
      mediaType:   _normalizeMediaType(json['media_type']?.toString()),
      description: json['description'] as String? ?? json['plot'] as String?,
      rating:      (json['rating'] as num?)?.toDouble(),
      genres:      json['genres'] is String
          ? json['genres'] as String
          : (json['genres'] is List ? (json['genres'] as List).map((e) => e.toString()).join(', ') : json['genres']?.toString()),  // FIX BUG-010
      posterUrl:   json['poster'] as String? ?? json['poster_url'] as String?,
      isFree:      json['is_free'] == 1 || json['is_free'] == true || json['is_free'] == '1' || json['is_free'] == 'true',
      dbVersion:   json['db_version'] as int? ?? 0,
      episodes:    episodesRaw.cast<Map<String, dynamic>>(),
      fileId:      json['file_id']?.toString(),
      shareUrl:    json['share_url'] as String?,
      posterPath:  null,  // local only — set by LocalDb
      language:    json['language'] as String?,
      isNew:       json['is_new'] == true || json['is_new'] == 1, // E2 fix: tolerant parse; 'as bool?' throws TypeError when server sends int 1/0
      watchProgress: (json['watch_progress'] as num?)?.toDouble(),
      isUploading: json['is_uploading'] as bool?,
      status:      json['status'] as String?,
      isOngoing:   (json['is_ongoing'] == 1 || json['is_ongoing'] == true || json['status'] == 'ongoing'),
      episodeCount: json['episode_count'] as int?,
    );
  }

  CatalogItem copyWith({
    double? watchProgress,
    bool? isUploading,
    String? status,
    bool? isOngoing,
    String? shareUrl,
    String? posterPath,
    int? newEpisodeCount,
  }) => CatalogItem(
    id: id, title: title, year: year, mediaType: mediaType,
    description: description, rating: rating, genres: genres,
    posterUrl: posterUrl, isFree: isFree, dbVersion: dbVersion,
    episodes: episodes, fileId: fileId, language: language, isNew: isNew,
    shareUrl: shareUrl ?? this.shareUrl,
    posterPath: posterPath ?? this.posterPath,
    watchProgress: watchProgress ?? this.watchProgress,
    isUploading: isUploading ?? this.isUploading,
    status: status ?? this.status,
    isOngoing: isOngoing ?? this.isOngoing,
    newEpisodeCount: newEpisodeCount ?? this.newEpisodeCount,
    episodeCount: episodeCount,
  );

  CatalogItem copyWithEpisodes(List<Map<String, dynamic>> eps) => CatalogItem(
    id: id, title: title, year: year, mediaType: mediaType,
    description: description, rating: rating, genres: genres,
    posterUrl: posterUrl, isFree: isFree, dbVersion: dbVersion,
    episodes: eps, fileId: fileId, shareUrl: shareUrl, posterPath: posterPath,
    language: language, isNew: isNew,
    watchProgress: watchProgress,
    isUploading: isUploading,
    status: status,
    isOngoing: isOngoing,
    newEpisodeCount: newEpisodeCount,
    episodeCount: episodeCount,
  );
}
