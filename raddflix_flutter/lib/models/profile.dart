/// A single "Who's Watching" profile under one RaddFlix account/device.
///
/// Profiles are stored locally (SQLCipher-encrypted SQLite) and are scoped to
/// the device, not synced to the backend — they're a convenience layer for
/// households sharing one subscription, mirroring how Netflix/Disney+/Prime
/// let one login have multiple separate watchlists/histories.
class Profile {
  final int id;
  final String name;
  final String avatarColor;
  final String avatarEmoji;
  final bool isKids;
  final String maxRating; // reserved for future content-rating filtering
  final String? pin; // 4-digit PIN; null/empty = no lock
  final int sortOrder;

  const Profile({
    required this.id,
    required this.name,
    this.avatarColor = '#8B002D',
    this.avatarEmoji = '',
    this.isKids = false,
    this.maxRating = 'nc17',
    this.pin,
    this.sortOrder = 0,
  });

  bool get isLocked => pin != null && pin!.trim().isNotEmpty;

  /// Single character shown inside the avatar circle when no emoji is set.
  String get avatarInitial => name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'P';

  Profile copyWith({
    String? name,
    String? avatarColor,
    String? avatarEmoji,
    bool? isKids,
    String? maxRating,
    String? pin,
    int? sortOrder,
  }) {
    return Profile(
      id: id,
      name: name ?? this.name,
      avatarColor: avatarColor ?? this.avatarColor,
      avatarEmoji: avatarEmoji ?? this.avatarEmoji,
      isKids: isKids ?? this.isKids,
      maxRating: maxRating ?? this.maxRating,
      pin: pin ?? this.pin,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  factory Profile.fromRow(Map<String, dynamic> row) {
    return Profile(
      id: row['id'] as int,
      name: (row['name'] as String?)?.trim().isNotEmpty == true
          ? row['name'] as String : 'Profile',
      avatarColor: row['avatar_color'] as String? ?? '#8B002D',
      avatarEmoji: row['avatar_emoji'] as String? ?? '',
      isKids: (row['is_kids'] as int? ?? 0) == 1,
      maxRating: row['max_rating'] as String? ?? 'nc17',
      pin: row['pin'] as String?,
      sortOrder: row['sort_order'] as int? ?? 0,
    );
  }
}
