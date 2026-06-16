import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/db/local_db.dart';
import '../models/catalog_item.dart';

class WatchlistState {
  final List<CatalogItem> items;
  final Set<int> ids;
  final bool loading;

  final String? error;

  const WatchlistState({
    this.items = const [],
    this.ids = const {},
    this.loading = false,
    this.error,
  });

  WatchlistState copyWith({
    List<CatalogItem>? items,
    Set<int>? ids,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return WatchlistState(
      items: items ?? this.items,
      ids: ids ?? this.ids,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  bool isInWatchlist(int id) => ids.contains(id);
}

class WatchlistNotifier extends StateNotifier<WatchlistState> {
  WatchlistNotifier() : super(const WatchlistState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true);
    try {
      final items = await LocalDb.getWatchlist();
      final idSet = items.map((i) => i.id).toSet();
      state = state.copyWith(items: items, ids: idSet, loading: false);
    } catch (e) {
      // M-11: surface load errors so caller / UI can react
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> toggle(CatalogItem item) async {
    if (state.isInWatchlist(item.id)) {
      // Optimistic update — UI responds instantly
      final updated = state.items.where((i) => i.id != item.id).toList();
      final updatedIds = Set<int>.from(state.ids)..remove(item.id);
      state = state.copyWith(items: updated, ids: updatedIds);
      await LocalDb.removeFromWatchlist(item.id);
    } else {
      // Optimistic update — UI responds instantly
      final updated = [item, ...state.items];
      final updatedIds = Set<int>.from(state.ids)..add(item.id);
      state = state.copyWith(items: updated, ids: updatedIds);
      await LocalDb.addToWatchlist(item);
    }
  }
}

final watchlistProvider =
    StateNotifierProvider<WatchlistNotifier, WatchlistState>(
  (_) => WatchlistNotifier(),
);
