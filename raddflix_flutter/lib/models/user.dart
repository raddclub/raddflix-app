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

class AppUser {
  final int id;
  final String phone;
  final String? deviceId;
  final String? deviceName;
  final bool isActive;
  final bool isGuest;
  final bool isAdmin;
  final String? createdAt;
  final String? lastLoginAt;
  final UserSubscription? subscription;
  final String? displayName;
  final String? email;
  final String avatarColor;
  final String avatarEmoji;

  const AppUser({
    required this.id,
    required this.phone,
    this.deviceId,
    this.deviceName,
    this.isActive = true,
    this.isGuest = false,
    this.isAdmin = false,
    this.createdAt,
    this.lastLoginAt,
    this.subscription,
    this.displayName,
    this.email,
    this.avatarColor = '#8B002D',
    this.avatarEmoji = '',
  });

  factory AppUser.guest() {
    return const AppUser(id: 0, phone: 'guest', isGuest: true, avatarColor: '#8B002D', avatarEmoji: '');
  }

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final userData = json['user'] as Map<String, dynamic>? ?? json;
    final subData = json['subscription'] as Map<String, dynamic>?;

    return AppUser(
      id: userData['id'] as int? ?? 0,
      phone: userData['phone'] as String? ?? '',
      deviceId: userData['device_id'] as String?,
      deviceName: userData['device_name'] as String?,
      // L-09: default to true when 'is_active' key is absent — existing accounts
      // pre-dating the field are all active; treating missing as false would lock
      // legitimate users out. Explicit servers always send the field.
      isActive: _parseBool(userData['is_active'] ?? true),
      isGuest: userData['is_guest'] as bool? ?? false,  // FIX BUG-011
      isAdmin: _parseBool(userData['is_admin']),
      createdAt: userData['created_at']?.toString(),
      lastLoginAt: userData['last_login_at']?.toString(),
      subscription: subData != null ? UserSubscription.fromJson(subData) : null,
      displayName: (userData['display_name'] as String?)?.trim().isEmpty == true
          ? null : userData['display_name'] as String?,
      email: (userData['email'] as String?)?.trim().isEmpty == true
          ? null : userData['email'] as String?,
      avatarColor: (userData['avatar_color'] as String?)?.isNotEmpty == true
          ? userData['avatar_color'] as String : '#8B002D',
      avatarEmoji: userData['avatar_emoji'] as String? ?? '',
    );
  }

  bool get hasActiveSubscription {
    if (subscription == null) return false;
    return subscription!.isActive;
  }

  String get planName => subscription?.plan ?? 'free';

  /// Display label: uses displayName if set, otherwise formats the phone number.
  String get displayLabel {
    if (isGuest) return 'Guest';
    if (displayName != null && displayName!.isNotEmpty) return displayName!;
    return phone;
  }

  /// The single character shown inside the avatar circle.
  String get avatarInitial {
    if (isGuest) return 'G';
    if (displayName != null && displayName!.isNotEmpty) return displayName![0].toUpperCase();
    return phone.isNotEmpty ? phone[0].toUpperCase() : 'U';
  }
}

class UserSubscription {
  final String plan; // 'free', 'basic', 'standard', 'premium'
  final String? expiresAt;
  final bool isActive;

  const UserSubscription({
    required this.plan,
    this.expiresAt,
    required this.isActive,
  });

  factory UserSubscription.fromJson(Map<String, dynamic> json) {
    final expiresAt = _parseExpiry(json['expires_at']);
    bool active = _parseBool(json['is_active']);

    // Also check expiry date
    if (active && expiresAt != null) {
      try {
        final expiry = DateTime.parse(expiresAt);
        active = expiry.isAfter(DateTime.now());
      } catch (_) {}
    }

    return UserSubscription(
      plan: json['plan'] as String? ?? 'free',
      expiresAt: expiresAt,
      isActive: active,
    );
  }

  String get displayName {
    switch (plan) {
      case 'basic': return 'Basic';
      case 'standard': return 'Standard';
      case 'premium': return 'Premium';
      default: return 'Free';
    }
  }
}
