import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/db/sync_service.dart';
import 'auth_provider.dart';
import 'catalog_provider.dart';

/// E1 (TEN_POINT_PLAN Phase E): extracted from CatalogNotifier.syncFromServer().
/// Owns server-sync execution and status, decoupled from catalog display state
/// so each can be watched/rebuilt independently and sync logic is testable on
/// its own. CatalogNotifier.syncFromServer() is kept as a thin delegate to
/// sync() below so no external call site needs to change.
enum SyncStatus { idle, syncing, error }

class SyncState {
  final SyncStatus status;
  final DateTime? lastSyncAt;
  final String? error;

  const SyncState({
    this.status = SyncStatus.idle,
    this.lastSyncAt,
    this.error,
  });

  SyncState copyWith({
    SyncStatus? status,
    DateTime? lastSyncAt,
    String? error,
  }) {
    return SyncState(
      status: status ?? this.status,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      error: error,
    );
  }

  bool get isSyncing => status == SyncStatus.syncing;
}

class SyncNotifier extends StateNotifier<SyncState> {
  SyncNotifier(this._ref) : super(const SyncState());
  final Ref _ref;

  /// Runs a server sync and reports the outcome back to CatalogNotifier.
  ///
  /// Note: SyncService.sync() already internally chooses between a full sync
  /// (first run / admin force-bump) and a delta sync based on server vs local
  /// catalog version (see sync_service.dart's class doc) — there is no
  /// separate public syncFull()/syncDelta() entry point at that layer to wrap
  /// here without adding dead API surface, so sync() is the one method every
  /// real call site needs.
  Future<void> sync() async {
    if (state.isSyncing) return; // replaces the old CatalogState.status == syncing guards
    state = state.copyWith(status: SyncStatus.syncing, error: null);
    final result = await SyncService.sync();
    if (!mounted) return; // provider may have been disposed while awaiting
    state = state.copyWith(lastSyncAt: DateTime.now());

    final catalogNotifier = _ref.read(catalogProvider.notifier);
    if (result.success) {
      state = state.copyWith(status: SyncStatus.idle, error: null);
      await catalogNotifier.onSyncComplete(itemsSynced: result.itemsSynced);
      // Refresh subscription / plan silently after every successful sync so
      // plan upgrades, quota changes, and is_free changes reach the user
      // instantly without manual re-login.
      _ref.read(authProvider.notifier).silentRefresh().ignore();
    } else {
      if (!mounted) return;
      state = state.copyWith(
        status: SyncStatus.error,
        error: result.itemsSynced == 0 ? result.message : null,
      );
      await catalogNotifier.onSyncComplete(itemsSynced: 0, failed: true);
    }
  }
}

final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>(
  (ref) => SyncNotifier(ref),
);
