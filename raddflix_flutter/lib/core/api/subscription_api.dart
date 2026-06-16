import '../constants.dart';
import 'api_client.dart';
import '../../models/subscription.dart';

class SubscriptionApi {
  static final _client = ApiClient.instance;

  /// List all available subscription plans with prices.
  static Future<List<SubscriptionPlan>> getPlans() async {
    final response = await _client.get(ApiPaths.plans);
    final data = response.data as Map<String, dynamic>;
    final plans = data['plans'] as List<dynamic>? ?? [];
    return plans
        .map((e) => SubscriptionPlan.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Get the current user's subscription status.
  static Future<SubscriptionStatus> getStatus() async {
    final response = await _client.get(ApiPaths.subscriptionStatus);
    return SubscriptionStatus.fromJson(response.data as Map<String, dynamic>);
  }

  /// Submit a TID (Transaction ID) for payment verification.
  /// User pays on Jazz app, gets TID, submits it here.
  /// Admin verifies in Radd Hub → subscription is activated.
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

  /// Check status of a submitted TID payment.
  static Future<Map<String, dynamic>> getTidStatus() async {
    final response = await _client.get(ApiPaths.tidStatus);
    return response.data as Map<String, dynamic>;
  }
}
