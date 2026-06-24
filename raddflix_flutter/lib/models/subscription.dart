bool _parseBool(dynamic val) {
  if (val == null) return false;
  if (val is bool) return val;
  if (val is int) return val == 1;
  return false;
}

String? _parseExpiry(dynamic val) {
  if (val == null) return null;
  if (val is int && val > 0) {
    return DateTime.fromMillisecondsSinceEpoch(val * 1000).toIso8601String();
  }
  if (val is String && val.isNotEmpty) return val;
  return null;
}

/// A subscription plan fetched dynamically from the server.
/// Admin can add/edit/disable plans from radd-hub without any APK update.
class SubscriptionPlan {
  final String id;
  final String name;
  final int priceMonthly;       // PKR
  final double dataGb;          // Monthly GB limit (e.g. 30.0)
  final int maxDevices;
  final int durationDays;
  final String description;
  final List<String> features;
  final String color;
  final String jazzSavingsMsg;

  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.priceMonthly,
    required this.dataGb,
    required this.maxDevices,
    required this.durationDays,
    required this.description,
    required this.features,
    required this.color,
    required this.jazzSavingsMsg,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    final gb = json['data_gb'] ?? json['monthly_limit_gb'] ?? 0;
    return SubscriptionPlan(
      id:             json['id']?.toString() ?? '',
      name:           json['name'] as String? ?? '',
      priceMonthly:   (json['price_monthly'] ?? json['price_pkr'] ?? json['price'] ?? 0) as int,
      dataGb:         gb is double ? gb : (gb as num).toDouble(),
      maxDevices:     json['max_devices'] as int? ?? 1,
      durationDays:   json['duration_days'] as int? ?? 30,
      description:    json['description'] as String? ?? '',
      features:       (json['features'] as List<dynamic>? ?? [])
                        .map((e) => e.toString()).toList(),
      color:          json['color'] as String? ?? '#E8002D',
      jazzSavingsMsg: json['jazz_savings_msg'] as String? ?? '',
    );
  }

  String get displayPrice => priceMonthly == 0 ? 'Free' : 'Rs. $priceMonthly';
  String get displayData  => '${dataGb.toInt()} GB';

  /// Approx streaming hours at 720p (~495 MB/hr average)
  int get approxStreamHours {
    if (dataGb <= 0) return 0;
    return ((dataGb * 1024) / 495).round();
  }

  String get approxLabel =>
      approxStreamHours > 0 ? '~$approxStreamHours hrs of streaming' : '';

  /// Price-per-GB label to show value
  String get pricePerGb {
    if (dataGb <= 0 || priceMonthly <= 0) return '';
    final ppg = (priceMonthly / dataGb).round();
    return 'Rs. $ppg/GB';
  }
}

/// The current user's live subscription + quota state.
class SubscriptionStatus {
  final String plan;
  final String planName;
  final bool isActive;
  final String? expiresAt;

  // GB tracking fields (from server quota)
  final double monthlyUsedGb;
  final double monthlyLimitGb;
  final double monthlyRemainingGb;
  final bool isQuotaExceeded;
  final String? quotaReason;

  const SubscriptionStatus({
    required this.plan,
    required this.planName,
    required this.isActive,
    this.expiresAt,
    this.monthlyUsedGb      = 0.0,
    this.monthlyLimitGb     = 0.0,
    this.monthlyRemainingGb = 0.0,
    this.isQuotaExceeded    = false,
    this.quotaReason,
  });

  /// 0.0–1.0 fraction for progress bars
  double get usagePercent =>
      monthlyLimitGb > 0
          ? (monthlyUsedGb / monthlyLimitGb).clamp(0.0, 1.0)
          : 0.0;

  /// GB remaining, floored to 2 decimal places
  String get remainingLabel {
    if (monthlyLimitGb <= 0) return 'Unlimited';
    return '${monthlyRemainingGb.toStringAsFixed(1)} GB left';
  }

  /// Days until plan expires (null if no expiry or already expired)
  int? get daysUntilExpiry {
    if (expiresAt == null) return null;
    try {
      final dt = DateTime.parse(expiresAt!);
      final d = dt.difference(DateTime.now()).inDays;
      return d >= 0 ? d : 0;
    } catch (_) { return null; }
  }

  /// Human-readable expiry, e.g. "Jan 31, 2027"
  String? get expiryLabel {
    if (expiresAt == null) return null;
    try {
      final dt = DateTime.parse(expiresAt!);
      const m = ['Jan','Feb','Mar','Apr','May','Jun',
                  'Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) { return null; }
  }

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    final sub   = json['subscription'] as Map<String, dynamic>? ?? json;
    final quota = json['quota']        as Map<String, dynamic>? ?? {};

    double toGb(dynamic v) {
      if (v == null) return 0.0;
      if (v is double) return v;
      return (v as num).toDouble();
    }

    final limit     = toGb(quota['monthly_limit_gb'] ?? sub['monthly_limit_gb']);
    final used      = toGb(quota['monthly_used_gb']);
    final remaining = toGb(quota['monthly_remaining_gb'] ??
        (limit > 0 ? limit - used : 0.0));

    final planStr = sub['plan'] as String? ?? 'free';

    return SubscriptionStatus(
      plan:               planStr,
      planName:           sub['plan_name'] as String?
                          ?? quota['plan_name'] as String?
                          ?? _capitalize(planStr),
      isActive:           _parseBool(sub['is_active']),
      expiresAt:          _parseExpiry(
                            sub['expires_at'] ?? sub['sub_expires_at']),
      monthlyUsedGb:      used,
      monthlyLimitGb:     limit,
      monthlyRemainingGb: remaining.clamp(0.0, limit > 0 ? limit : remaining),
      isQuotaExceeded:    quota['allowed'] == false ||
                          quota['is_exceeded'] == true,
      quotaReason:        quota['reason'] as String?,
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
