import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/subscription_api.dart';
import '../models/subscription.dart';

class SubscriptionState {
  final List<SubscriptionPlan> plans;
  final SubscriptionStatus? status;
  final bool loading;
  final String? error;
  final bool tidSubmitted;

  const SubscriptionState({
    this.plans       = const [],
    this.status,
    this.loading     = false,
    this.error,
    this.tidSubmitted = false,
  });

  SubscriptionState copyWith({
    List<SubscriptionPlan>? plans,
    SubscriptionStatus? status,
    bool? loading,
    String? error,
    bool? tidSubmitted,
    bool clearError = false,
  }) {
    return SubscriptionState(
      plans:        plans        ?? this.plans,
      status:       status       ?? this.status,
      loading:      loading      ?? this.loading,
      error:        clearError ? null : (error ?? this.error),
      tidSubmitted: tidSubmitted ?? this.tidSubmitted,
    );
  }
}

class SubscriptionNotifier extends StateNotifier<SubscriptionState> {
  SubscriptionNotifier() : super(const SubscriptionState());

  Future<void> loadPlans() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final plans = await SubscriptionApi.getPlans();
      state = state.copyWith(plans: plans, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> loadStatus() async {
    // BUG-M04 fix: set loading:true so UI can show a spinner while status is being fetched
    state = state.copyWith(loading: true, clearError: true);
    try {
      final status = await SubscriptionApi.getStatus();
      state = state.copyWith(status: status, loading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), loading: false);
    }
  }

  /// Re-fetch just the live GB quota and merge into status.
  /// Call this after flushing usage, or when user pulls to refresh.
  Future<void> refreshQuota() async {
    try {
      final quota = await SubscriptionApi.getQuota();
      if (quota == null) return;
      final current = state.status;
      if (current == null) return;
      // Merge fresh quota data into existing status
      final merged = SubscriptionStatus.fromJson({
        'subscription': {
          'plan':       current.plan,
          'plan_name':  current.planName,
          'is_active':  current.isActive ? 1 : 0,
          'expires_at': current.expiresAt,
        },
        'quota': quota,
      });
      state = state.copyWith(status: merged);
    } catch (e) {
      // BUG-M03 fix: surface error in state so UI can react (e.g. show retry button)
      state = state.copyWith(error: e.toString());
    }
  }

  /// Submit TID. Works for new subscriptions, renewals, and upgrades.
  Future<bool> submitTid({
    required String phone,
    required String tid,
    required String plan,
    required String paymentMethod,
  }) async {
    state = state.copyWith(loading: true, clearError: true, tidSubmitted: false);
    try {
      await SubscriptionApi.submitTid(
        phone: phone,
        tid: tid,
        plan: plan,
        paymentMethod: paymentMethod,
      );
      state = state.copyWith(loading: false, tidSubmitted: true);
      return true;
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
      return false;
    }
  }

  void resetTidSubmitted() {
    state = state.copyWith(tidSubmitted: false);
  }
}

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionState>(
  (ref) => SubscriptionNotifier(),
);
