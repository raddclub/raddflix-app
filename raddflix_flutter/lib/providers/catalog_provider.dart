import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/db/local_db.dart';
import '../core/db/sync_service.dart';
import '../core/services/poster_service.dart';
import '../models/catalog_item.dart';
import '../core/api/catalog_api.dart';

enum CatalogStatus { idle, syncing, ready, error }

class CatalogState {
  final CatalogStatus status;
  final List<CatalogItem> movies;
  final List<CatalogItem> shows;
  final List<CatalogItem> recentlyWatched;
  final List<CatalogItem> trending;
  final List<Map<String, dynamic>> recommendations;
  final String? error;
  final int totalCount;

  const CatalogState({
    this.status = CatalogStatus.idle,
    this.movies = const [],
    this.shows = const [],
    this.recentlyWatched = const [],
    this.trending = const [],
    this.recommendations = const [],
    this.error,
    this.totalCount = 0,
  });

  CatalogState copyWith({
    CatalogStatus? status,
    List<CatalogItem>? movies,
    List<CatalogItem>? shows,
    List<CatalogItem>? recentlyWatched,
    List<CatalogItem>? trending,
    List<Map<String, dynamic>>? recommendations,
    String? error,
    int? totalCount,
  }) {
    return CatalogState(
      status: status ?? this.status,
      movies: movies ?? this.movies,
      shows: shows ?? this.shows,
      recentlyWatched: recentlyWatched ?? this.recentlyWatched,
      trending: trending ?? this.trending,
      recommendations: recommendations ?? this.recommendations,
      error: error,
      totalCount: totalCount ?? this.totalCount,
    );
  }

  bool get isEmpty => movies.isEmpty && shows.isEmpty;
  bool get isReady => status == CatalogStatus.ready;
}

class CatalogNotifier extends StateNotifier<CatalogState> {
  CatalogNotifier() : super(const CatalogState());

  Future<void> initialize() async {
    await _loadFromDb();
    await syncFromServer();
    // Load recommendations in background — non-blocking
    Future.microtask(loadRecommendations);
  }

  Future<void> _loadFromDb() async {
    try {
      final movies  = await LocalDb.getMovies();
      final rawShows = await LocalDb.getShows();
      // Embed episodes into each show so ShowDetailScreen has them on first open
      final shows = await Future.wait(rawShows.map((show) async {
        final eps = await LocalDb.getEpisodes(show.id);
        return show.copyWithEpisodes(eps);
      }));
      final count   = await LocalDb.getTotalCount();
      final recent   = await _loadRecentlyWatched(movies, shows);
      final trending = _computeTrending(movies, shows);
      // New-episode badge: compare episode counts vs last-seen counts per show
      final newEpCounts = await LocalDb.getNewEpisodeCounts();
      final showsWithBadge = shows.map((s) {
        final n = newEpCounts[s.id];
        return (n != null && n > 0) ? s.copyWith(newEpisodeCount: n) : s;
      }).toList();
      state = state.copyWith(
        status: CatalogStatus.ready,
        movies: movies,
        shows: showsWithBadge,
        recentlyWatched: recent,
        trending: trending,
        totalCount: count,
      );
      // Background: rebuild FTS search index with freshest data (fire-and-forget)
      LocalDb.rebuildFtsIndex();
      // Background poster download — runs silently after UI renders
      _schedulePosterSync(movies, shows);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  // BUG-A20: static guard — poster sync fires once per app lifecycle, not per catalog reload
  static bool _posterSyncDone = false;

  void _schedulePosterSync(
    List<CatalogItem> movies,
    List<CatalogItem> shows,
  ) {
    if (_posterSyncDone) return;
    _posterSyncDone = true;
    // Delay so UI is interactive first
    Future.delayed(const Duration(seconds: 3), () async {
      final all = [
        ...movies.map((i) => {'id': i.id, 'poster_url': i.posterUrl ?? ''}),
        ...shows.map((i) => {'id': i.id, 'poster_url': i.posterUrl ?? ''}),
      ];
      await PosterService.runBackgroundSync(all);
    });
  }

  /// Build the "Continue Watching" list from local watch_positions.
  ///
  /// Matches positions against:
  ///   1. Movies — by item.fileId
  ///   2. Shows  — by iterating each show's pre-loaded episodes list
  ///
  /// Shows are deduplicated: if multiple episodes of the same show were
  /// watched, only the most recently watched one appears (positions are
  /// already ordered by updated_at DESC from LocalDb.getWatchPositions).
  Future<List<CatalogItem>> _loadRecentlyWatched(
      List<CatalogItem> movies, List<CatalogItem> shows) async {
    try {
      final positions = await LocalDb.getWatchPositions();
      if (positions.isEmpty) return [];

      final result  = <CatalogItem>[];
      final seenIds = <int>{};   // Deduplicate by title id

      for (final pos in positions) {
        final fileId = pos['file_id'] as String? ?? '';
        final posMs  = pos['position_ms'] as int? ?? 0;
        final durMs  = pos['duration_ms'] as int? ?? 0;

        if (posMs < 3000) continue;                              // Skip barely-started
        final progress = durMs > 0 ? posMs / durMs : 0.0;
        if (progress > 0.95) continue;                           // Skip essentially-finished

        CatalogItem? match;

        // 1. Check movies (fileId is stored directly on the title row)
        for (final m in movies) {
          if (m.fileId == fileId) {
            match = m;
            break;
          }
        }

        // 2. If not a movie, search show episodes
        if (match == null) {
          outer:
          for (final show in shows) {
            if (seenIds.contains(show.id)) continue; // Already added this show
            for (final ep in show.episodes) {
              if (ep['file_id']?.toString() == fileId) {
                match = show;
                break outer;
              }
            }
          }
        }

        if (match != null && !seenIds.contains(match.id)) {
          seenIds.add(match.id);
          result.add(match.copyWith(watchProgress: progress));
        }

        if (result.length >= 10) break;
      }

      return result;
    } catch (_) {
      return [];
    }
  }

  List<CatalogItem> _computeTrending(
      List<CatalogItem> movies,
      List<CatalogItem> shows,
  ) {
    final all = [...movies, ...shows];
    // Sort by rating descending; items without a rating go to end
    all.sort((a, b) {
      final ra = a.rating ?? 0.0;
      final rb = b.rating ?? 0.0;
      return rb.compareTo(ra);
    });
    // Take top items that have a poster (so they look good in the row)
    return all.where((i) => (i.posterUrl ?? '').isNotEmpty).take(20).toList();
  }


  /// Remove a title from the Continue Watching row.
  /// Clears the watch position(s) from SQLite so the item no longer appears.
  /// For movies: clears by fileId. For shows: clears all episode positions.
  Future<void> removeFromContinueWatching(CatalogItem item) async {
    try {
      if (item.isMovie && item.fileId != null) {
        await LocalDb.clearPosition(item.fileId!);
      } else if (item.isShow) {
        for (final ep in item.episodes) {
          final fid = ep['file_id']?.toString();
          if (fid != null && fid.isNotEmpty) {
            await LocalDb.clearPosition(fid);
          }
        }
      }
      // Optimistically remove from state without full reload
      final updated = List<CatalogItem>.from(state.recentlyWatched)
        ..removeWhere((i) => i.id == item.id);
      state = state.copyWith(recentlyWatched: updated);
    } catch (_) {}
  }

  /// Load TMDB-seeded recommendations in the background.
  /// Results stored in CatalogState.recommendations.
  Future<void> loadRecommendations() async {
    try {
      final recs = await CatalogApi.fetchRecommendations(limit: 20);
      if (recs.isNotEmpty) {
        state = state.copyWith(recommendations: recs);
      }
    } catch (_) {}
  }

  Future<void> syncFromServer() async {
    state = state.copyWith(status: CatalogStatus.syncing, error: null);
    final result = await SyncService.sync();
    if (result.success) {
      await _loadFromDb();
    } else {
      state = state.copyWith(
        status: CatalogStatus.ready,
        error: result.itemsSynced == 0 ? result.message : null,
      );
    }
  }

  Future<List<CatalogItem>> search(String query) async {
    if (query.trim().isEmpty) return [];
    return LocalDb.searchTitles(query.trim());
  }
}

final catalogProvider = StateNotifierProvider<CatalogNotifier, CatalogState>(
  (ref) => CatalogNotifier(),
);
