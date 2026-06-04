import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../constants.dart';

class AppNotification {
  final int id;
  final int? broadcastId;
  final String title;
  final String body;
  final String type;
  final bool isRead;
  final int createdAt;
  final String? imageUrl;

  const AppNotification({
    required this.id,
    this.broadcastId,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    required this.createdAt,
    this.imageUrl,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
    id:          j['id'] is int ? j['id'] as int : int.tryParse(j['id']?.toString() ?? '') ?? 0,
    broadcastId: j['broadcast_id'] as int?,
    title:       j['title'] as String? ?? '',
    body:        j['body'] as String? ?? '',
    type:        j['type'] as String? ?? 'info',
    isRead:      j['is_read'] == true,
    createdAt:   j['created_at'] as int? ?? 0,
    imageUrl:    j['image_url'] as String?,
  );

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id, broadcastId: broadcastId, title: title, body: body, type: type,
    isRead: isRead ?? this.isRead, createdAt: createdAt, imageUrl: imageUrl,
  );
}

class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;
  NotificationService._();

  List<AppNotification> _notifications = [];
  int _unreadCount = 0;
  bool _loading = false;

  List<AppNotification> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get loading => _loading;

  Future<void> fetch() async {
    _loading = true;
    notifyListeners();
    try {
      final res = await ApiClient.instance.get(ApiPaths.notifications);
      final data = res.data as Map<String, dynamic>;
      _notifications = (data['notifications'] as List? ?? [])
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList();
      _unreadCount = data['unread_count'] as int? ?? 0;
    } catch (_) {
      // Notifications are non-critical — fail silently
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> markAllRead() async {
    if (_unreadCount == 0) return;
    try {
      await ApiClient.instance.post(ApiPaths.notificationsRead, data: {'ids': []});
      _notifications = _notifications.map((n) => n.copyWith(isRead: true)).toList();
      _unreadCount = 0;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> markRead(List<int> ids) async {
    try {
      await ApiClient.instance.post(ApiPaths.notificationsRead, data: {'ids': ids});
      _notifications = _notifications
          .map((n) => ids.contains(n.id) ? n.copyWith(isRead: true) : n)
          .toList();
      _unreadCount = _notifications.where((n) => !n.isRead).length;
      notifyListeners();
    } catch (_) {}
  }
}
