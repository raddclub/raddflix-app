// lib/providers/live_channel_provider.dart
//
// Riverpod provider for the Live TV channel list + recently watched.
//
// Strategy (mirrors CatalogNotifier):
//   1. On init — serve local SQLite cache immediately (no spinner if cached).
//   2. Fetch from Oracle if cache is empty OR older than _kTtlSeconds (1 hour).
//   3. On success — persist to SQLite so next cold-start is instant.
//   4. On failure — keep stale cache if available; surface error only when empty.
//
// Recently watched: last 5 channel IDs stored in SharedPreferences.
// Call recordWatched(channelId) on every channel tap; read recentChannels
// from the state to drive the "Recently Watched" row in live_tv_screen.
//
// Call liveChannelProvider.notifier.refresh() for pull-to-refresh.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api/live_channel_api.dart';
import '../core/db/local_db.dart';
import '../core/debug/debug_logger.dart';
import '../data/live_channels.dart';

const _kTtlSeconds  = 3600; // 1 hour
const _kRecentKey   = 'live_recently_watched';
const _kMaxRecent   = 5;

// ── State ─────────────────────────────────────────────────────────────────────

enum LiveChannelStatus { idle, loading, ready, error }

class LiveChannelState {
  final LiveChannelStatus status;
  final List<LiveChannel> channels;
  final List<String>      recentIds; // ordered newest-first
  final String?           error;

  const LiveChannelState({
    this.status    = LiveChannelStatus.idle,
    this.channels  = const [],
    this.recentIds = const [],
    this.error,
  });

  LiveChannelState copyWith({
    LiveChannelStatus? status,
    List<LiveChannel>? channels,
    List<String>?      recentIds,
    String?            error,
  }) =>
      LiveChannelState(
        status:    status    ?? this.status,
        channels:  channels  ?? this.channels,
        recentIds: recentIds ?? this.recentIds,
        error:     error,              // null clears the error
      );

  bool get isLoading => status == LiveChannelStatus.loading;
  bool get hasError  => status == LiveChannelStatus.error;
  bool get isEmpty   => channels.isEmpty;

  /// Channels corresponding to recentIds, in order, filtered to those still
  /// present in the loaded channel list.
  List<LiveChannel> get recentChannels => recentIds
      .map((id) => channels.where((c) => c.id == id).firstOrNull)
      .whereType<LiveChannel>()
      .toList();
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class LiveChannelNotifier extends StateNotifier<LiveChannelState> {
  LiveChannelNotifier() : super(const LiveChannelState()) {
    _init();
  }

  Future<void> _init() async {
    // 1. Serve cache immediately so the UI is not blank on warm launch.
    final cached = await LocalDb.getLiveChannels();
    if (!mounted) return;
    if (cached.isNotEmpty) {
      state = state.copyWith(status: LiveChannelStatus.ready, channels: cached);
    } else {
      state = state.copyWith(status: LiveChannelStatus.loading);
    }

    // 2. Load recently watched IDs from SharedPrefs (fast, local).
    await _loadRecentIds();

    // 3. Refresh from API if stale or empty.
    final ts  = await LocalDb.getLiveChannelsTimestamp();
    final age = DateTime.now().millisecondsSinceEpoch ~/ 1000 - ts;
    if (cached.isEmpty || age > _kTtlSeconds) {
      await _fetchFromApi(silentFail: cached.isNotEmpty);
    }
  }

  /// Called by pull-to-refresh. Always shows loading state first.
  Future<void> refresh() async {
    state = state.copyWith(status: LiveChannelStatus.loading, error: null);
    await _fetchFromApi(silentFail: false);
  }

  /// Record a channel tap for the "Recently Watched" row.
  /// Prepends the channel ID, deduplicates, and keeps the last [_kMaxRecent].
  Future<void> recordWatched(String channelId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = [channelId, ...state.recentIds.where((id) => id != channelId)]
        .take(_kMaxRecent)
        .toList();
    await prefs.setStringList(_kRecentKey, ids);
    if (!mounted) return;
    state = state.copyWith(recentIds: ids);
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _loadRecentIds() async {
    final prefs = await SharedPreferences.getInstance();
    final ids   = prefs.getStringList(_kRecentKey) ?? [];
    if (!mounted) return;
    state = state.copyWith(recentIds: ids);
  }

  Future<void> _fetchFromApi({required bool silentFail}) async {
    try {
      final result = await LiveChannelApi.fetchChannels();
      if (!mounted) return;

      if (result.channels.isNotEmpty) {
        await LocalDb.saveLiveChannels(result.channels);
        if (!mounted) return;
        state = state.copyWith(
          status:   LiveChannelStatus.ready,
          channels: result.channels,
          error:    null,
        );
        DebugLogger.log('LIVE', 'Fetched ${result.channels.length} channels from Oracle');
      } else {
        // Server returned empty list — keep existing cache.
        if (!mounted) return;
        if (state.channels.isEmpty) {
          state = state.copyWith(
            status: LiveChannelStatus.error,
            error:  'No channels available right now.',
          );
        } else {
          state = state.copyWith(status: LiveChannelStatus.ready, error: null);
        }
      }
    } catch (e) {
      if (!mounted) return;
      DebugLogger.logError('LIVE', 'Failed to fetch live channels', e);
      if (silentFail && state.channels.isNotEmpty) {
        // Background refresh failed — keep stale data silently.
        state = state.copyWith(status: LiveChannelStatus.ready, error: null);
      } else {
        // Nothing cached — must surface the error so user can retry.
        state = state.copyWith(
          status: LiveChannelStatus.error,
          error:  'Could not load channels. Check your connection.',
        );
      }
    }
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final liveChannelProvider =
    StateNotifierProvider<LiveChannelNotifier, LiveChannelState>(
  (_) => LiveChannelNotifier(),
);
