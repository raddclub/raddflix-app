// Safely parse a bool/int/null value from JSON.
bool _parseBool(dynamic val) {
  if (val == null) return false;
  if (val is bool) return val;
  if (val is int) return val == 1;
  return false;
}

// Parse expires_at which server sends as Unix int seconds or null.
String? _parseExpiry(dynamic val) {
  if (val == null) return null;
  if (val is int && val > 0) {
    return DateTime.fromMillisecondsSinceEpoch(val * 1000).toIso8601String();
  }
  if (val is String && val.isNotEmpty) return val;
  return null;
}

class SubscriptionPlan {
  final String id;
  final String name;
  final int priceMonthly; // PKR
  final String description;
  final int downloadsPerDay;
  final bool hdAccess;
  final List<String> features;

  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.priceMonthly,
    required this.description,
    required this.downloadsPerDay,
    required this.hdAccess,
    required this.features,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    final featuresRaw = json['features'] as List<dynamic>? ?? [];
    return SubscriptionPlan(
      id: json['id'] as String? ?? json['plan_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      priceMonthly: json['price_pkr'] as int? ?? json['price'] as int? ?? json['price_monthly'] as int? ?? 0,
      description: json['description'] as String? ?? '',
      downloadsPerDay: json['downloads_per_day'] as int? ?? 0,
      hdAccess: (json['hd_access'] as int? ?? 0) == 1,
      features: featuresRaw.cast<String>(),
    );
  }

  String get displayPrice =>
      priceMonthly == 0 ? 'Free' : 'PKR $priceMonthly/month';
}

class SubscriptionStatus {
  final String plan;
  final bool isActive;
  final String? expiresAt;
  final int downloadsUsedToday;
  final int downloadsLimit;

  const SubscriptionStatus({
    required this.plan,
    required this.isActive,
    this.expiresAt,
    this.downloadsUsedToday = 0,
    this.downloadsLimit = 0,
  });

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    final sub = json['subscription'] as Map<String, dynamic>? ?? json;
    return SubscriptionStatus(
      plan: sub['plan'] as String? ?? 'free',
      isActive: _parseBool(sub['is_active']),
      expiresAt: _parseExpiry(sub['expires_at']),
      downloadsUsedToday: sub['downloads_used_today'] as int? ?? 0,
      downloadsLimit: sub['downloads_limit'] as int? ?? 1,
    );
  }
}
