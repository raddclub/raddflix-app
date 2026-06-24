import '../constants.dart';
import 'api_client.dart';
import '../../models/subscription.dart';

class SubscriptionApi {
  static final _client = ApiClient.instance;

  /// List all available subscription plans with GB limits and prices.
  static Future<List<SubscriptionPlan>> getPlans() async {
    final response = await _client.get(ApiPaths.plans);
    final data = response.data as Map<String, dynamic>;
    final plans = data['plans'] as List<dynamic>? ?? [];
    return plans
        .map((e) => SubscriptionPlan.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Get the current user's subscription status + live GB quota.
  static Future<SubscriptionStatus> getStatus() async {
    final response = await _client.get(ApiPaths.subscriptionStatus);
    return SubscriptionStatus.fromJson(response.data as Map<String, dynamic>);
  }

  /// Fetch live GB quota from server (enriched with used/remaining/resets_at).
  static Future<Map<String, dynamic>?> getQuota() async {
    try {
      final response = await _client.get(ApiPaths.quota);
      final data = response.data as Map<String, dynamic>? ?? {};
      return data['quota'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Submit a TID (Transaction ID) for payment verification.
  ///
  /// Works for all cases:
  ///  - New subscriber: pick plan + submit TID
  ///  - Renew same plan: submit same plan TID again
  ///  - Upgrade: pick higher plan + submit TID
  ///
  /// Admin verifies in radd-hub → subscription is activated/extended.
  static Future<Map<String, dynamic>> submitTid({
    required String phone,
    required String tid,
    required String plan,
    required String paymentMethod, // 'jazzcash' or 'easypaisa'
  }) async {
    final response = await _client.post(
      ApiPaths.tidSubmit,
      data: {
        'phone': phone,
        'tid': tid,
        'plan': plan,
        'payment_method': paymentMethod,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  /// Check status of all submitted TID payments for this user.
  static Future<Map<String, dynamic>> getTidStatus() async {
    final response = await _client.get(ApiPaths.tidStatus);
    return response.data as Map<String, dynamic>;
  }
}
