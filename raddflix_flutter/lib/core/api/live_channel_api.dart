// lib/core/api/live_channel_api.dart
//
// Oracle → Flutter live-channel fetch.
// The only network entry point for live channel data; all callers go through
// LiveChannelNotifier (live_channel_provider.dart) which handles local caching.

import '../constants.dart';
import 'api_client.dart';
import '../../data/live_channels.dart';

class LiveChannelApi {
  static final _client = ApiClient.instance;

  /// Fetch the active channel list from Oracle (/api/live/channels).
  ///
  /// The server returns only channels where is_active = 1, ordered by
  /// sort_order ASC. Channels with an empty stream_url or channel_id are
  /// dropped on the client side as a safety guard.
  ///
  /// Throws on network/parse error — LiveChannelNotifier handles the catch.
  static Future<LiveChannelResult> fetchChannels() async {
    final resp = await _client.get(ApiPaths.liveChannels);
    final data = resp.data as Map<String, dynamic>;
    final raw  = (data['channels'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final channels = raw
        .map(LiveChannel.fromJson)
        .where((c) => c.id.isNotEmpty && c.streamUrl.isNotEmpty)
        .toList();
    return LiveChannelResult(
      channels:  channels,
      serverTs:  data['server_ts'] as int? ?? 0,
    );
  }
}

class LiveChannelResult {
  final List<LiveChannel> channels;
  final int serverTs; // UTC unix seconds from Oracle
  const LiveChannelResult({required this.channels, required this.serverTs});
}
