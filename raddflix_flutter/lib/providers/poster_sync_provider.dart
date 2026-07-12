import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/poster_service.dart';
import '../models/catalog_item.dart';

/// E2 (TEN_POINT_PLAN Phase E): extracted from CatalogNotifier's
/// `_schedulePosterSync`/`_posterSyncDone`/`resetPosterSyncFlag`. Poster
/// downloading is a background job queue unrelated to catalog display state —
/// pulling it out means catalog rebuilds no longer carry poster-sync fields,
/// and poster-sync progress can be watched independently.
enum PosterSyncStatus { idle, running, done }

class PosterSyncState {
  final PosterSyncStatus status;
  final int pendingCount;

  const PosterSyncState({
    this.status = PosterSyncStatus.idle,
    this.pendingCount = 0,
  });

  PosterSyncState copyWith({PosterSyncStatus? status, int? pendingCount}) {
    return PosterSyncState(
      status: status ?? this.status,
      pendingCount: pendingCount ?? this.pendingCount,
    );
  }
}

class PosterSyncNotifier extends StateNotifier<PosterSyncState> {
  PosterSyncNotifier() : super(const PosterSyncState());

  // BUG-A20 (carried from CatalogNotifier): poster sync should fire once per
  // app lifecycle, not once per catalog reload — this flag enforces that.
  bool _done = false;
  Timer? _scheduled;

  /// BUG-F09 fix (carried from CatalogNotifier): allow the flag to be reset
  /// so delta-synced titles get posters downloaded on the next scheduleSync().
  void resetFlag() => _done = false;

  void scheduleSync(
    List<CatalogItem> movies,
    List<CatalogItem> shows, {
    bool forceReset = false,
  }) {
    if (forceReset) _done = false;
    if (_done) return;
    _done = true;

    final all = [
      ...movies.map((i) => {'id': i.id, 'poster_url': i.posterUrl ?? ''}),
      ...shows.map((i) => {'id': i.id, 'poster_url': i.posterUrl ?? ''}),
    ];
    state = state.copyWith(status: PosterSyncStatus.running, pendingCount: all.length);

    // Delay so UI is interactive first.
    _scheduled?.cancel();
    _scheduled = Timer(const Duration(seconds: 3), () async {
      await PosterService.runBackgroundSync(all);
      if (!mounted) return;
      state = state.copyWith(status: PosterSyncStatus.done, pendingCount: 0);
    });
  }

  void cancelSync() {
    _scheduled?.cancel();
    _scheduled = null;
    if (state.status == PosterSyncStatus.running) {
      state = state.copyWith(status: PosterSyncStatus.idle, pendingCount: 0);
    }
  }

  @override
  void dispose() {
    _scheduled?.cancel();
    super.dispose();
  }
}

final posterSyncProvider =
    StateNotifierProvider<PosterSyncNotifier, PosterSyncState>(
  (ref) => PosterSyncNotifier(),
);
