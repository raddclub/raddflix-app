import 'package:flutter/material.dart';
import '../core/theme/radd_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/constants.dart';
import '../core/services/notification_service.dart';

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final t = RaddTheme.of(context);
    return ListenableBuilder(
      listenable: NotificationService.instance,
      builder: (context, _) {
        final count = NotificationService.instance.unreadCount;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined, size: 24),
              tooltip: 'Notifications',
              onPressed: () => _showNotificationSheet(context),
            ),
            if (count > 0)
              Positioned(
                right: 8, top: 8,
                child: Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _showNotificationSheet(BuildContext context) {
    // Mark all read after opening
    Future.delayed(const Duration(milliseconds: 500), () {
      NotificationService.instance.markAllRead();
    });
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NotificationSheet(),
    );
  }
}

class _NotificationSheet extends StatelessWidget {
  const _NotificationSheet();

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final t = RaddTheme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (_, ctrl) {
        return Container(
          decoration: const BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: t.textMuted.withOpacity(0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 12),
              child: Row(children: [
                const Icon(Icons.notifications_outlined, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                const Text('Notifications',
                    style: TextStyle(color: t.textPrimary,
                        fontWeight: FontWeight.w700, fontSize: 16)),
                const Spacer(),
                ListenableBuilder(
                  listenable: NotificationService.instance,
                  builder: (_, __) {
                    final count = NotificationService.instance.unreadCount;
                    if (count == 0) return const SizedBox.shrink();
                    return TextButton(
                      onPressed: NotificationService.instance.markAllRead,
                      child: const Text('Mark all read',
                          style: TextStyle(color: AppColors.primary, fontSize: 12)),
                    );
                  },
                ),
              ]),
            ),
            Divider(height: 1, color: t.divider),
            // Notification list
            Expanded(
              child: ListenableBuilder(
                listenable: NotificationService.instance,
                builder: (_, __) {
                  final notifs = NotificationService.instance.notifications;
                  if (notifs.isEmpty) {
                    return const Center(child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.notifications_none_rounded,
                            size: 48, color: t.textMuted),
                        SizedBox(height: 12),
                        Text('No notifications yet',
                            style: TextStyle(color: t.textMuted, fontSize: 14)),
                        SizedBox(height: 4),
                        Text('Check back later for updates',
                            style: TextStyle(color: t.textMuted, fontSize: 12)),
                      ],
                    ));
                  }
                  return ListView.separated(
                    controller: ctrl,
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: notifs.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, indent: 16, color: t.divider),
                    itemBuilder: (_, i) => _NotificationCard(notif: notifs[i]),
                  );
                },
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final AppNotification notif;
  const _NotificationCard({required this.notif});

  static const _icons = {
    'new_content':  (Icons.movie_outlined, AppColors.info),
    'promo':        (Icons.card_giftcard_outlined, AppColors.success),
    'renewal':      (Icons.timer_outlined, AppColors.warning),
    'maintenance':  (Icons.build_outlined, t.textMuted),
    'info':         (Icons.info_outline_rounded, AppColors.primary),
  };

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final t = RaddTheme.of(context);
    final (icon, iconColor) = _icons[notif.type] ?? _icons['info']!;
    final hasImage = notif.imageUrl != null && notif.imageUrl!.isNotEmpty;
    final imageFullUrl = hasImage
        ? '${AppConstants.apiBaseUrl}${notif.imageUrl}'
        : null;

    return Container(
      color: notif.isRead ? Colors.transparent : AppColors.primary.withOpacity(0.04),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Image banner (if any) — served from same IP = zero-rated
        if (hasImage && imageFullUrl != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(
              imageUrl: imageFullUrl,
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                height: 140,
                color: t.card,
                child: const Center(
                  child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 1.5,
                          valueColor: AlwaysStoppedAnimation(AppColors.primary)))),
              ),
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Type icon
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: iconColor.withOpacity(0.12),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(notif.title,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontWeight: notif.isRead ? FontWeight.w500 : FontWeight.w700,
                      fontSize: 14,
                    )),
              ),
              if (!notif.isRead)
                Container(
                  width: 6, height: 6, margin: const EdgeInsets.only(left: 8, top: 4),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: AppColors.primary),
                ),
            ]),
            const SizedBox(height: 4),
            Text(notif.body,
                style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.4)),
            const SizedBox(height: 6),
            Text(_timeAgo(notif.createdAt),
                style: TextStyle(color: t.textMuted, fontSize: 11)),
          ])),
        ]),
      ]),
    );
  }

  String _timeAgo(int ts) {
    if (ts == 0) return '';
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts * 1000));
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
