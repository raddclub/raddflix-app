// lib/providers/live_channel_provider.dart
//
// Riverpod provider for the Live TV channel list.
//
// Strategy (mirrors CatalogNotifier):
//   1. On init — serve local SQLite cache immediately (no spinner if cached).
//   2. Fetch from Oracle if cache is empty OR older than _kTtlSeconds (1 hour).
//   3. On success — persist to SQLite so next cold-start is instant.
//   4. On failure — keep stale cache if available; surface error only when empty.
//
// Call liveChannelProvider.notifier.refresh() for pull-to-refresh.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/live_channel_api.dart';
import '../core/db/local_db.dart';
import '../core/debug/debug_logger.dart';
import '../data/live_channels.dart';

const _kTtlSeconds = 3600; // 1 hour

// ── State ─────────────────────────────────────────────────────────────────────

enum LiveChannelStatus { idle, loading, ready, error }

class LiveChannelState {
  final LiveChannelStatus status;
  final List<LiveChannel> channels;
  final String? error;

  const LiveChannelState({
    this.status  = LiveChannelStatus.idle,
    this.channels = const [],
    this.error,
  });

  LiveChannelState copyWith({
    LiveChannelStatus? status,
    List<LiveChannel>? channels,
    String? error,
  }) =>
      LiveChannelState(
        status:   status   ?? this.status,
        channels: channels ?? this.channels,
        error:    error,            // null clears the error
      );

  bool get isLoading => status == LiveChannelStatus.loading;
  bool get hasError  => status == LiveChannelStatus.error;
  bool get isEmpty   => channels.isEmpty;
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

    // 2. Refresh from API if stale or empty.
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
