/// Phase 54 — Global connectivity provider.
/// Single source of truth for "is the device online" — reused by the global
/// offline banner (see widgets/offline_banner.dart) so every screen shows a
/// consistent state instead of each screen probing connectivity_plus itself.
library connectivity_provider;

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConnectivityNotifier extends StateNotifier<bool> {
  StreamSubscription<List<ConnectivityResult>>? _sub;

  // Pessimistic default (online=true) avoids a banner flash on cold start
  // while the first probe resolves — matches ConnectivitySyncService's
  // "assume offline until proven otherwise" caution but flipped for UX:
  // showing a banner on every launch would be noisier than a brief false
  // negative if the device really is offline.
  ConnectivityNotifier() : super(true) {
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      state = results.any((r) => r != ConnectivityResult.none);
    });
    Connectivity().checkConnectivity().then((results) {
      state = results.any((r) => r != ConnectivityResult.none);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Watch anywhere: `final isOnline = ref.watch(isOnlineProvider);`
final isOnlineProvider = StateNotifierProvider<ConnectivityNotifier, bool>(
  (_) => ConnectivityNotifier(),
);
