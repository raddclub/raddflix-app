/// Phase 54 — Global connectivity provider.
/// Single source of truth for "is the device online" — reused by the global
/// offline banner (see widgets/offline_banner.dart) so every screen shows a
/// consistent state instead of each screen probing connectivity_plus itself.
library connectivity_provider;

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
// Timer used for offline-transition debounce below.
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConnectivityNotifier extends StateNotifier<bool> {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _offlineDebounce;

  // Pessimistic default (online=true) avoids a banner flash on cold start
  // while the first probe resolves — matches ConnectivitySyncService's
  // "assume offline until proven otherwise" caution but flipped for UX:
  // showing a banner on every launch would be noisier than a brief false
  // negative if the device really is offline.
  ConnectivityNotifier() : super(true) {
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      _applyDebounced(results.any((r) => r != ConnectivityResult.none));
    });
    Connectivity().checkConnectivity().then((results) {
      state = results.any((r) => r != ConnectivityResult.none);
    }).catchError((_) {});
  }

  // Radio handoffs (e.g. WiFi <-> mobile) can report a brief `none` blip
  // that resolves within a second. Debounce ONLY the "going offline"
  // transition so the banner doesn't flash on/off — coming back online is
  // applied immediately since there's no downside to clearing it fast.
  void _applyDebounced(bool online) {
    _offlineDebounce?.cancel();
    if (online) {
      state = true;
      return;
    }
    _offlineDebounce = Timer(const Duration(milliseconds: 800), () => state = false);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _offlineDebounce?.cancel();
    super.dispose();
  }
}

/// Watch anywhere: `final isOnline = ref.watch(isOnlineProvider);`
final isOnlineProvider = StateNotifierProvider<ConnectivityNotifier, bool>(
  (_) => ConnectivityNotifier(),
);
