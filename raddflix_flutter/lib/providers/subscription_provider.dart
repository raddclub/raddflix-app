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
    this.plans = const [],
    this.status,
    this.loading = false,
    this.error,
    this.tidSubmitted = false,
  });

  SubscriptionState copyWith({
    List<SubscriptionPlan>? plans,
    SubscriptionStatus? status,
    bool? loading,
    String? error,
    bool? tidSubmitted,
  }) {
    return SubscriptionState(
      plans: plans ?? this.plans,
      status: status ?? this.status,
      loading: loading ?? this.loading,
      error: error,
      tidSubmitted: tidSubmitted ?? this.tidSubmitted,
    );
  }
}

class SubscriptionNotifier extends StateNotifier<SubscriptionState> {
  SubscriptionNotifier() : super(const SubscriptionState());

  Future<void> loadPlans() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final plans = await SubscriptionApi.getPlans();
      state = state.copyWith(plans: plans, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> loadStatus() async {
    // M-11: empty catch swallowed all errors, leaving status silently null.
    // Now exposes the error so the subscription screen can show a retry prompt.
    try {
      final status = await SubscriptionApi.getStatus();
      state = state.copyWith(status: status);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<bool> submitTid({
    required String phone,
    required String tid,
    required String plan,
    required String paymentMethod,
  }) async {
    state = state.copyWith(loading: true, error: null, tidSubmitted: false);
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
}

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionState>(
  (ref) => SubscriptionNotifier(),
);
