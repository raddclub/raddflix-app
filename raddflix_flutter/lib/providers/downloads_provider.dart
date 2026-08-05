import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/db/local_db.dart';
import '../core/download/download_service.dart';
import 'package:disk_space_plus/disk_space_plus.dart';

// ── State ─────────────────────────────────────────────────────────────────

class DownloadsState {
  final List<Map<String, dynamic>> downloads;
  final bool loading;
  final Map<String, double> activeProgress;
  final String? quotaError;
  // Phase-40 additions
  final Map<String, String> speedLabels;    // "1.2 MB/s"
  final Map<String, String> etaLabels;      // "3m 12s left"
  final List<String> recentlyCompleted;     // titles for completion SnackBar
  // DL-K6: tracks which fileIds are currently in the "paused" UI state
  // (awaiting user's Resume tap). Separate from DB status='paused' so the
  // UI can optimistically hide the progress row before the cancel propagates.
  final Set<String> pausedIds;

  const DownloadsState({
    this.downloads = const [],
    this.loading = false,
    this.activeProgress = const {},
    this.quotaError,
    this.speedLabels = const {},
    this.etaLabels = const {},
    this.recentlyCompleted = const [],
    this.pausedIds = const {},
  });

  DownloadsState copyWith({
    List<Map<String, dynamic>>? downloads,
    bool? loading,
    Map<String, double>? activeProgress,
    String? quotaError,
    bool clearQuotaError = false,
    Map<String, String>? speedLabels,
    Map<String, String>? etaLabels,
    List<String>? recentlyCompleted,
    bool clearRecentlyCompleted = false,
    Set<String>? pausedIds,
  }) {
    return DownloadsState(
      downloads: downloads ?? this.downloads,
      loading: loading ?? this.loading,
      activeProgress: activeProgress ?? this.activeProgress,
      quotaError: clearQuotaError ? null : (quotaError ?? this.quotaError),
      speedLabels: speedLabels ?? this.speedLabels,
      etaLabels: etaLabels ?? this.etaLabels,
      recentlyCompleted: clearRecentlyCompleted
          ? const []
          : (recentlyCompleted ?? this.recentlyCompleted),
      pausedIds: pausedIds ?? this.pausedIds,
    );
  }

  bool   isDownloading(String fileId) => activeProgress.containsKey(fileId);
  double progressOf(String fileId)    => activeProgress[fileId] ?? 0.0;
  String speedOf(String fileId)       => speedLabels[fileId] ?? '';
  String etaOf(String fileId)         => etaLabels[fileId] ?? '';

  bool isDownloaded(String fileId) => downloads.any(
        (d) => d['file_id'] == fileId && d['status'] == 'completed' &&
               (d['local_path'] as String?)?.isNotEmpty == true);

  String? getLocalPath(String fileId) {
    try {
      final match = downloads.firstWhere(
        (d) => d['file_id'] == fileId && d['status'] == 'completed' &&
               (d['local_path'] as String?)?.isNotEmpty == true,
      );
      return match['local_path'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// 1-based queue position for [fileId]; 0 if not currently downloading.
  /// Map preserves insertion order, so position reflects queueing order.
  int queuePositionOf(String fileId) {
    final keys = activeProgress.keys.toList();
    final idx  = keys.indexOf(fileId);
    return idx < 0 ? 0 : idx + 1;
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────

class DownloadsNotifier extends StateNotifier<DownloadsState> {
  DownloadsNotifier() : super(const DownloadsState());

  // Speed tracking instance vars — not in state to avoid per-chunk rebuilds.
  final _downloadStartMs = <String, int>{};   // fileId → epoch_ms at download start
  final _lastUiUpdateMs  = <String, int>{};   // fileId → epoch_ms at last UI refresh

  // ── Formatters ────────────────────────────────────────────────────────────

  static String _fmtSpeed(double bps) {
    if (bps <= 0)              return '';
    if (bps < 1024)            return '${bps.toStringAsFixed(0)} B/s';
    if (bps < 1024 * 1024)    return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  static String _fmtEta(double seconds) {
    if (seconds <= 0 || seconds.isInfinite || seconds.isNaN) return '';
    if (seconds < 60)   return '${seconds.toInt()}s left';
    if (seconds < 3600) {
      final m = (seconds / 60).floor();
      final s = (seconds % 60).floor();
      return '${m}m ${s}s left';
    }
    final h = (seconds / 3600).floor();
    final m = ((seconds % 3600) / 60).floor();
    return '${h}h ${m}m left';
  }

  // ── Internal speed update (throttled to 1×/500ms per download) ────────────

  void _updateSpeed(String fileId, int received, int total) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - (_lastUiUpdateMs[fileId] ?? 0) < 500) return;
    _lastUiUpdateMs[fileId] = now;

    final elapsedMs = now - (_downloadStartMs[fileId] ?? now);
    if (elapsedMs <= 0 || received <= 0) return;

    final bps       = (received * 1000.0) / elapsedMs;
    final speedLbl  = _fmtSpeed(bps);
    final remaining = total > 0 ? total - received : 0;
    final etaLbl    = (bps > 0 && remaining > 0) ? _fmtEta(remaining / bps) : '';

    final updSpeed = Map<String, String>.from(state.speedLabels)..[fileId] = speedLbl;
    final updEta   = Map<String, String>.from(state.etaLabels)..[fileId]   = etaLbl;
    state = state.copyWith(speedLabels: updSpeed, etaLabels: updEta);
  }

  // ── Public API ────────────────────────────────────────────────────────────

  Future<void> loadDownloads() async {
    state = state.copyWith(loading: true);
    final list = await LocalDb.getDownloads();
    state = state.copyWith(downloads: list, loading: false);
  }

  void clearQuotaError()        => state = state.copyWith(clearQuotaError: true);
  void clearRecentlyCompleted() => state = state.copyWith(clearRecentlyCompleted: true);

  /// Start downloading a file.
  ///
  /// Includes: duplicate guard, disk-space pre-check (requires ≥ 200 MB free),
  /// average-speed + ETA tracking throttled to 500ms UI refresh, and a single
  /// auto-retry on [SocketException] (network blip) after 4 seconds.
  Future<void> startDownload({
    required String fileId,
    required String titleText,
    required String streamUrl,
    String? posterUrl,
    String? targetFilename,
    int remoteId = 0,
    String? contentType,
  }) async {
    // Guard: never start a concurrent download for the same fileId.
    if (state.isDownloading(fileId) || state.isDownloaded(fileId)) return;

    // Pre-flight: abort early if device storage is critically low.
    try {
      final freeMB = await DiskSpacePlus.getFreeDiskSpace ?? 999.0;
      if (freeMB < 200) {
        state = state.copyWith(
          quotaError: 'Low storage: only ${freeMB.toStringAsFixed(0)} MB free. '
              'Delete some downloads to make space.',
        );
        return;
      }
    } catch (_) { /* allow download if the check itself fails */ }

    // Register in activeProgress and start the speed timer.
    final prog0 = Map<String, double>.from(state.activeProgress)..[fileId] = 0.0;
    state = state.copyWith(activeProgress: prog0, clearQuotaError: true);
    _downloadStartMs[fileId] = DateTime.now().millisecondsSinceEpoch;
    HapticFeedback.lightImpact(); // Phase 50: download start feedback

    bool succeeded = false;

    Future<void> doDownload() => DownloadService.downloadFile(
      fileId:         fileId,
      titleText:      titleText,
      streamUrl:      streamUrl,
      posterUrl:      posterUrl,
      targetFilename: targetFilename,
      remoteId:       remoteId,
      contentType:    contentType,
      onProgress: (p, received, total) {
        final upd = Map<String, double>.from(state.activeProgress)..[fileId] = p;
        state = state.copyWith(activeProgress: upd);
        _updateSpeed(fileId, received, total);
      },
    );

    try {
      await doDownload();
      succeeded = true;
    } on DownloadQuotaException catch (e) {
      state = state.copyWith(quotaError: e.userMessage);
      rethrow;
    } on SocketException {
      // Single auto-retry after 4 s on transient network loss.
      await Future.delayed(const Duration(seconds: 4));
      try {
        _downloadStartMs[fileId] = DateTime.now().millisecondsSinceEpoch;
        await doDownload();
        succeeded = true;
      } catch (e2) {
        state = state.copyWith(quotaError: 'Download failed after connection error. Please try again.');
        rethrow;
      }
    } catch (e) {
      state = state.copyWith(quotaError: 'Download failed. Please try again.');
      rethrow;
    } finally {
      _downloadStartMs.remove(fileId);
      _lastUiUpdateMs.remove(fileId);
      final updProg  = Map<String, double>.from(state.activeProgress)..remove(fileId);
      final updSpeed = Map<String, String>.from(state.speedLabels)..remove(fileId);
      final updEta   = Map<String, String>.from(state.etaLabels)..remove(fileId);
      state = state.copyWith(activeProgress: updProg, speedLabels: updSpeed, etaLabels: updEta);
      await loadDownloads();
    }

    // Notify the UI via recentlyCompleted (triggers SnackBar in DownloadsScreen).
    if (succeeded) {
      HapticFeedback.mediumImpact(); // Phase 50: download complete feedback
      state = state.copyWith(recentlyCompleted: [...state.recentlyCompleted, titleText]);
    }
  }

  /// Retry a failed download in-place.
  ///
  /// Looks up the original stream URL from the local SQLite catalog.
  /// If not found (e.g. offline catalog not synced), surfaces a message
  /// asking the user to navigate to the content page instead.
  Future<void> retryDownload({
    required String fileId,
    required String titleText,
    String? posterUrl,
    String? contentType,
  }) async {
    final info        = await LocalDb.getFileInfo(fileId);
    final rawShareUrl = info?['share_url'] as String? ?? '';
    if (rawShareUrl.isEmpty) {
      state = state.copyWith(
        quotaError: 'Cannot auto-retry — go to the content page and tap Download.',
      );
      return;
    }
    // BUG-DL-RETRY-01: getFileInfo returns the raw XOR-encoded share_url stored in
    // SQLite.  Decode it before passing as streamUrl so that if downloadFile's Path B
    // (JazzDrive resolution) fails, the fallback URL is usable rather than corrupt.
    final shareUrl = (await LocalDb.decodeShareUrl(rawShareUrl)) ?? rawShareUrl;
    // Remove failed record so startDownload's isDownloaded() guard passes.
    await LocalDb.deleteDownload(fileId);
    await loadDownloads();
    await startDownload(
      fileId:         fileId,
      titleText:      titleText,
      streamUrl:      shareUrl,
      posterUrl:      posterUrl,
      targetFilename: info!['filename'] as String?,
      remoteId:       info['remote_id'] as int? ?? 0,
      contentType:    contentType,
    );
  }

  Future<void> cancelDownload(String fileId) async {
    DownloadService.cancelDownload(fileId);
    _downloadStartMs.remove(fileId);
    _lastUiUpdateMs.remove(fileId);
    final updProg  = Map<String, double>.from(state.activeProgress)..remove(fileId);
    final updSpeed = Map<String, String>.from(state.speedLabels)..remove(fileId);
    final updEta   = Map<String, String>.from(state.etaLabels)..remove(fileId);
    final updPaused = Set<String>.from(state.pausedIds)..remove(fileId);
    state = state.copyWith(
        activeProgress: updProg, speedLabels: updSpeed, etaLabels: updEta,
        pausedIds: updPaused);
    await loadDownloads();
  }

  /// DL-K6: Pause an in-progress download. Keeps the partial file on disk
  /// and sets DB status to 'paused'. The item stays in the downloads list
  /// with a Resume button.
  Future<void> pauseDownload(String fileId) async {
    if (!state.isDownloading(fileId)) return;
    DownloadService.pauseDownload(fileId);
    _downloadStartMs.remove(fileId);
    _lastUiUpdateMs.remove(fileId);
    final updProg   = Map<String, double>.from(state.activeProgress)..remove(fileId);
    final updSpeed  = Map<String, String>.from(state.speedLabels)..remove(fileId);
    final updEta    = Map<String, String>.from(state.etaLabels)..remove(fileId);
    final updPaused = Set<String>.from(state.pausedIds)..add(fileId);
    state = state.copyWith(
        activeProgress: updProg, speedLabels: updSpeed, etaLabels: updEta,
        pausedIds: updPaused);
    // Brief delay so the service's cancel/pause handler has time to write
    // 'paused' to the DB before we refresh the list.
    await Future.delayed(const Duration(milliseconds: 300));
    await loadDownloads();
  }

  /// DL-K6: Resume a paused download. Re-looks up stream URL from local DB
  /// and restarts from the beginning (current partial file is overwritten).
  Future<void> resumeDownload({
    required String fileId,
    required String titleText,
    String? posterUrl,
    String? contentType,
  }) async {
    final updPaused = Set<String>.from(state.pausedIds)..remove(fileId);
    state = state.copyWith(pausedIds: updPaused);
    // retryDownload already handles: DB lookup, decode, delete old row, restart.
    await retryDownload(
      fileId: fileId,
      titleText: titleText,
      posterUrl: posterUrl,
      contentType: contentType,
    );
  }

  Future<void> deleteDownload(String fileId) async {
    await cancelDownload(fileId);
    await DownloadService.deleteDownload(fileId);
    await loadDownloads();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────

final downloadsProvider =
    StateNotifierProvider<DownloadsNotifier, DownloadsState>(
  (ref) => DownloadsNotifier(),
);
