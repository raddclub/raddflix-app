import 'dart:async';
import 'package:dio/dio.dart';
import '../constants.dart';
import '../api/api_client.dart';
import '../db/local_db.dart';
import '../debug/debug_logger.dart';

/// Phase 6 — Data Usage Tracking Service.
///
/// Tracks bytes consumed locally (SQLite), then flushes to the server
/// when internet is available. Uses optimistic flushing — if the server
/// call fails, the data stays in local DB for the next attempt.
///
/// Rules:
///   - Streaming non-free content → addWatchSession()
///   - Downloading a file        → addDownloadBytes()
///   - Playing a local/downloaded file → SKIP (already counted or not our content)
///   - Watching free content     → SKIP (free means free)
///   - Guest user                → SKIP (no account to track against)
///
/// Usage (from player or download service):
///   UsageService.addWatchSession(seconds: 120, quality: '720p');
///   UsageService.addDownloadBytes(bytes: 524288000);
///   UsageService.flushPending();  // called on app resume / sync / player close
class UsageService {
  UsageService._();

  static bool _flushing = false; // M-18: prevent concurrent flush calls

  // Quality → estimated bits per second
  static const Map<String, int> _bpsEstimate = {
    '1080p': 2200000,
    '720p':  1100000,
    '480p':   600000,
    '360p':   300000,
  };

  static int _estimateBytes({required int seconds, required String quality}) {
    final bps = _bpsEstimate[quality] ?? _bpsEstimate['720p']!;
    return (seconds * bps) ~/ 8; // bits → bytes
  }

  /// Called when a streaming watch session ends (player closes / next episode).
  /// [seconds] = wall-clock seconds player was running (not content position).
  /// [quality] = '720p', '1080p', etc.
  ///
  /// ONLY call this when _trackUsage = true in the player (non-local, non-free).
  static Future<void> addWatchSession({
    required int seconds,
    String quality = '720p',
    String? fileId,
  }) async {
    if (seconds <= 0) return;
    final bytes = _estimateBytes(seconds: seconds, quality: quality);
    await LocalDb.addPendingUsage(bytes: bytes);
    flushPending().ignore();
  }

  /// Called when a download completes successfully.
  /// Uses the actual file size (exact, not estimated).
  ///
  /// ONLY call after a completed RaddFlix download — not for user's own local files.
  static Future<void> addDownloadBytes({required int bytes}) async {
    if (bytes <= 0) return;
    await LocalDb.addPendingUsage(bytes: bytes);
    flushPending().ignore();
  }

  /// Flush all pending usage bytes to the server.
  /// Safe to call multiple times — idempotent, re-entrancy guarded.
  static Future<void> flushPending() async {
    if (_flushing) return;
    _flushing = true;
    try {
      await _doFlushPending();
    } finally {
      _flushing = false;
    }
  }

  static Future<void> _doFlushPending() async {
    final pending = await LocalDb.getPendingUsageBytes();
    if (pending <= 0) return;
    try {
      final resp = await ApiClient.instance.post(
        ApiPaths.usage,
        data: {'bytes_used': pending},
      );
      final data = resp.data as Map<String, dynamic>? ?? {};
      if (data['ok'] == true) {
        await LocalDb.clearPendingUsage();
        final quota = data['quota'] as Map<String, dynamic>?;
        if (quota != null) {
          await LocalDb.cacheQuota(quota);
        }
      }
    } on DioException catch (e) {
      DebugLogger.logWarn('USAGE', 'Flush failed (will retry): ${e.type}');
    } catch (e) {
      DebugLogger.logWarn('USAGE', 'Flush error: $e');
    }
  }

  /// Get locally cached quota (used offline / before first server sync).
  static Future<Map<String, dynamic>> getCachedQuota() async {
    return LocalDb.getCachedQuota();
  }

  /// Fetch fresh quota from server and update local cache.
  static Future<Map<String, dynamic>?> fetchQuota() async {
    try {
      final resp = await ApiClient.instance.get(ApiPaths.quota);
      final data = resp.data as Map<String, dynamic>? ?? {};
      if (data['ok'] == true) {
        final quota = data['quota'] as Map<String, dynamic>?;
        if (quota != null) {
          await LocalDb.cacheQuota(quota);
          return quota;
        }
      }
    } catch (e) { DebugLogger.logWarn('USAGE', 'fetchQuota error: $e'); }
    return null;
  }
}
