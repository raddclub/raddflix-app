import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/db/local_db.dart';
import '../core/download/download_service.dart';

class DownloadsState {
  final List<Map<String, dynamic>> downloads;
  final bool loading;
  final Map<String, double> activeProgress;
  final String? quotaError;

  const DownloadsState({
    this.downloads = const [],
    this.loading = false,
    this.activeProgress = const {},
    this.quotaError,
  });

  DownloadsState copyWith({
    List<Map<String, dynamic>>? downloads,
    bool? loading,
    Map<String, double>? activeProgress,
    String? quotaError,
    bool clearQuotaError = false,
  }) {
    return DownloadsState(
      downloads: downloads ?? this.downloads,
      loading: loading ?? this.loading,
      activeProgress: activeProgress ?? this.activeProgress,
      quotaError: clearQuotaError ? null : (quotaError ?? this.quotaError),
    );
  }

  bool isDownloading(String fileId) => activeProgress.containsKey(fileId);
  double progressOf(String fileId) => activeProgress[fileId] ?? 0.0;

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
}

class DownloadsNotifier extends StateNotifier<DownloadsState> {
  DownloadsNotifier() : super(const DownloadsState());

  Future<void> loadDownloads() async {
    state = state.copyWith(loading: true);
    final list = await LocalDb.getDownloads();
    state = state.copyWith(downloads: list, loading: false);
  }

  /// Start downloading a file.
  ///
  /// [targetFilename] — pass the episode filename (from ep['filename']) for
  ///   folder-share episodes so the JazzDrive 3-pass matcher picks the correct
  ///   file instead of blindly returning records.first.
  /// [remoteId] — JazzDrive permanent numeric file ID (remote_id from SQLite).
  ///   Enables Pass 0 exact match; pass 0 if not available.
  Future<void> startDownload({
    required String fileId,
    required String titleText,
    required String streamUrl,
    String? posterUrl,
    String? targetFilename,
    int remoteId = 0,
    String? contentType,
  }) async {
    final progress = Map<String, double>.from(state.activeProgress);
    progress[fileId] = 0.0;
    state = state.copyWith(activeProgress: progress, clearQuotaError: true);

    try {
      await DownloadService.downloadFile(
        fileId: fileId,
        titleText: titleText,
        streamUrl: streamUrl,
        posterUrl: posterUrl,
        targetFilename: targetFilename,
        remoteId: remoteId,
        contentType: contentType,
        onProgress: (p) {
          final updated = Map<String, double>.from(state.activeProgress);
          updated[fileId] = p;
          state = state.copyWith(activeProgress: updated);
        },
      );
    } on DownloadQuotaException catch (e) {
      state = state.copyWith(quotaError: e.userMessage);
      rethrow;
    } finally {
      final updated = Map<String, double>.from(state.activeProgress);
      updated.remove(fileId);
      state = state.copyWith(activeProgress: updated);
      await loadDownloads();
    }
  }

  void clearQuotaError() => state = state.copyWith(clearQuotaError: true);

  /// Cancel an in-progress download. Stops the HTTP stream and removes from
  /// the active progress map so the UI reflects cancellation instantly.
  void cancelDownload(String fileId) {
    DownloadService.cancelDownload(fileId);
    final updated = Map<String, double>.from(state.activeProgress);
    updated.remove(fileId);
    state = state.copyWith(activeProgress: updated);
  }

  Future<void> deleteDownload(String fileId) async {
    cancelDownload(fileId); // stop HTTP stream if still active
    await DownloadService.deleteDownload(fileId);
    await loadDownloads();
  }
}

final downloadsProvider =
    StateNotifierProvider<DownloadsNotifier, DownloadsState>(
  (ref) => DownloadsNotifier(),
);
