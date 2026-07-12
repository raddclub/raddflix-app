import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/db/local_db.dart';
import '../models/catalog_item.dart';
import '../core/api/catalog_api.dart';
import 'auth_provider.dart';
import 'sync_provider.dart';
import 'poster_sync_provider.dart';

enum CatalogStatus { idle, syncing, ready, error }

class CatalogState {
  final CatalogStatus status;
  final List<CatalogItem> movies;
  final List<CatalogItem> shows;
  final List<CatalogItem> recentlyWatched;
  final List<CatalogItem> trending;
  final List<Map<String, dynamic>> recommendations;
  final List<CatalogItem> freeContent;
  final List<CatalogItem> ongoingShows;
  final List<CatalogItem> newlyAdded;
  final String? error;
  final int totalCount;

  const CatalogState({
    this.status = CatalogStatus.idle,
    this.movies = const [],
    this.shows = const [],
    this.recentlyWatched = const [],
    this.trending = const [],
    this.recommendations = const [],
    this.freeContent = const [],
    this.ongoingShows = const [],
    this.newlyAdded = const [],
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
    List<CatalogItem>? freeContent,
    List<CatalogItem>? ongoingShows,
    List<CatalogItem>? newlyAdded,
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
      freeContent:     freeContent  ?? this.freeContent,
      ongoingShows:    ongoingShows ?? this.ongoingShows,
      newlyAdded:      newlyAdded   ?? this.newlyAdded,
      error: error,
      totalCount: totalCount ?? this.totalCount,
    );
  }

  bool get isEmpty => movies.isEmpty && shows.isEmpty;
  bool get isReady => status == CatalogStatus.ready;
}

class CatalogNotifier extends StateNotifier<CatalogState>
    with WidgetsBindingObserver {
  CatalogNotifier(this._ref) : super(const CatalogState());
  final Ref _ref;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  DateTime? _lastSyncTime;
  bool _initialized = false; // BUG-SYNC-01: guard against multiple initialize() calls

  // ── Version-gate sync strategy ──────────────────────────────────────────────
  // SyncService.sync() always calls /api/catalog/version first — a ~200 byte
  // request that returns MAX(updated_at) across all published titles in Oracle.
  //
  // • If Oracle version == local version → returns immediately. Zero download.
  // • If Oracle version > local version  → runs delta sync to fetch new/changed
  //   titles and updates the local SQLite. UI rebuilds (FREE badges, new titles).
  //
  // No periodic timers, no WorkManager background tasks. Syncing only does real
  // work when the admin has actually changed something in the database.
  //
  // Triggers:
  //   1. Cold / warm start — syncFromServer() in initialize()
  //   2. App foreground    — WidgetsBindingObserver.didChangeAppLifecycleState
  //   3. Internet restored — Connectivity().onConnectivityChanged

  Future<void> initialize() async {
    // BUG-SYNC-01: guard — HomeScreen.initState() may fire more than once
    // when the widget is disposed/recreated, causing duplicate observer
    // registration and N x syncFromServer() calls per foreground resume.
    if (_initialized) return;
    _initialized = true;

    await _loadFromDb();
    // Force a full re-sync when the APK is updated so any data-parsing fixes
    // (e.g. is_free bool/int correction) are applied to existing SQLite rows.
    await _resetSyncIfNewBuild();
    await syncFromServer(); // delegates to SyncNotifier — version-gated: no-op if Oracle unchanged

    // Load recommendations in background — non-blocking
    Future.microtask(loadRecommendations);

    // Trigger 2: foreground resume — defensive removeObserver first to
    // prevent duplicate registration in case of a race.
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.addObserver(this);

    // Trigger 3: internet restored — catch changes that happened while offline
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasNet = results.isNotEmpty && results.first != ConnectivityResult.none;
      if (hasNet && !_ref.read(syncProvider).isSyncing) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) syncFromServer(); // version-gated: no-op if Oracle unchanged
        });
      }
    });
  }

  // Called when the app returns to the foreground.
  // Cost: one ~200-byte HTTP call. Skips all sync work when Oracle is unchanged.
  @override
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    if (appState == AppLifecycleState.resumed &&
        !_ref.read(syncProvider).isSyncing) {
      syncFromServer(); // version-gated: no-op if Oracle unchanged
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    super.dispose();
  }

  /// Resets sync metadata when the APK build number changes so SyncService
  /// treats the next launch as a first-run full sync. This is critical after
  /// any release that fixes data-parsing bugs (e.g. is_free boolean handling):
  /// the fix only applies to freshly-parsed API data, but SQLite can hold stale
  /// values from before the fix. Resetting forces a clean re-download.
  ///
  /// Uses SharedPreferences key 'raddflix_sync_reset_build' to detect changes.
  /// Safe to call on every initialize() — the check is a fast prefs read.
  Future<void> _resetSyncIfNewBuild() async {
    try {
      final info = await PackageInfo.fromPlatform();
      // Combine version + buildNumber so any change (patch, minor, major) triggers
      final currentBuild = '${info.version}+${info.buildNumber}';
      final prefs = await SharedPreferences.getInstance();
      const kKey = 'raddflix_sync_reset_build';
      final lastBuild = prefs.getString(kKey) ?? '';
      if (lastBuild != currentBuild) {
        // New APK detected — reset sync timestamps so the next syncFromServer()
        // runs a full sync and overwrites all stale is_free (and other) values.
        await LocalDb.setLastSyncTimestamp(0);
        await LocalDb.setLastSyncVersion(0);
        await prefs.setString(kKey, currentBuild);
      }
    } catch (_) {
      // Non-fatal: if PackageInfo fails the sync continues normally.
    }
  }

  Future<void> _loadFromDb() async {
    try {
      final movies  = await LocalDb.getMovies();
      final rawShows = await LocalDb.getShows();
      // B1: single batched query replaces N+1 (getEpisodes once-per-show) pattern.
      // On a 200-show catalog this reduces startup DB round-trips from 201 → 2.
      final episodeMap = await LocalDb.getEpisodesForIds(
          rawShows.map((s) => s.id).toList());
      final shows = rawShows
          .map((show) => show.copyWithEpisodes(episodeMap[show.id] ?? const []))
          .toList();
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
      // Load supplemental home sections
      final freeContent  = await LocalDb.getFreeContent();
      final ongoingShows = await LocalDb.getOngoingShows();
      final newlyAdded   = await LocalDb.getNewlyAdded();

      state = state.copyWith(
        freeContent:  freeContent,
        ongoingShows: ongoingShows,
        newlyAdded:   newlyAdded,
      );

      // Background: rebuild FTS search index with freshest data (fire-and-forget)
      LocalDb.rebuildFtsIndex();
      // Background poster download — runs silently after UI renders (E2: now
      // owned by PosterSyncNotifier, see poster_sync_provider.dart)
      _ref.read(posterSyncProvider.notifier).scheduleSync(movies, shows);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
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

  Future<void> clearAllContinueWatching() async {
    await LocalDb.clearAllPositions();
    state = state.copyWith(recentlyWatched: []);
  }

  /// Reload just the Continue Watching list from local DB.
  /// Called after HistoryApi.mergeServerHistory() to surface cross-device history.
  Future<void> reloadRecentlyWatched() async {
    try {
      final recent = await _loadRecentlyWatched(state.movies, state.shows);
      state = state.copyWith(recentlyWatched: recent);
    } catch (_) {}
  }

    Future<void> loadRecommendations() async {
    try {
      final recs = await CatalogApi.fetchRecommendations(limit: 20);
      if (recs.isNotEmpty) {
        state = state.copyWith(recommendations: recs);
      }
    } catch (_) {}
  }

  /// E1: thin delegate — all sync mechanics (calling SyncService.sync(),
  /// tracking SyncStatus/lastSyncAt/error, guarding against concurrent runs)
  /// now live in SyncNotifier (sync_provider.dart). Kept as a method here so
  /// every existing call site (settings_screen.dart, home_screen.dart, plus
  /// this file's own initialize()/lifecycle/connectivity triggers) needs no
  /// changes. SyncNotifier calls back into onSyncComplete() below once the
  /// server round-trip finishes, so this notifier still decides whether the
  /// local catalog needs reloading — that decision depends on catalog state
  /// (isEmpty), not sync state, so it belongs here.
  Future<void> syncFromServer() => _ref.read(syncProvider.notifier).sync();

  /// Called by SyncNotifier once a sync attempt (success or failure) has
  /// completed against the server. Decides whether the local catalog needs
  /// reloading and resets the poster-sync flag when new items arrived.
  Future<void> onSyncComplete({
    required int itemsSynced,
    bool failed = false,
  }) async {
    if (!mounted) return; // M-09: provider may have been disposed while awaiting
    _lastSyncTime = DateTime.now();
    if (!failed) {
      // FIX-POSTER-01: if new items were synced, reset the poster sync flag so
      // _schedulePosterSync() runs again and downloads posters for the new titles.
      // Without this reset, the static _posterSyncDone flag blocks poster downloads
      // for any titles added after the first app launch in the same session.
      if (itemsSynced > 0) _ref.read(posterSyncProvider.notifier).resetFlag();
      // BUG-SYNC-01: skip _loadFromDb() when nothing changed and catalog is
      // already populated — avoids full SQLite read + UI rebuild on every
      // app foreground when Oracle version matches (itemsSynced == 0).
      if (itemsSynced > 0 || state.isEmpty) {
        await _loadFromDb();
      } else {
        state = state.copyWith(status: CatalogStatus.ready);
      }
    } else {
      // Even on sync failure, reload DB so any stale catalog from a previous session is shown.
      // Without this, a temporary network failure shows a blank screen instead of cached content.
      await _loadFromDb();
    }
  }

  Future<List<CatalogItem>> search(String query) async {
    if (query.trim().isEmpty) return [];
    return LocalDb.searchTitles(query.trim());
  }
}

final catalogProvider = StateNotifierProvider<CatalogNotifier, CatalogState>(
  (ref) => CatalogNotifier(ref),
);
