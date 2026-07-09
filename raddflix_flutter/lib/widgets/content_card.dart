import 'dart:io';
import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/radd_theme.dart';
import '../design_system/radius/radd_radius.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../core/constants.dart';
import '../core/constants.dart' show AppRoutes;
import '../models/catalog_item.dart';
import '../providers/watchlist_provider.dart';

class ContentCard extends StatelessWidget {
  final CatalogItem item;
  final VoidCallback? onTap;
  final bool showProgress;
  final double? progress;
  final VoidCallback? onLongPress;

  const ContentCard({super.key, required this.item, this.onTap, this.onLongPress,
    this.showProgress = false, this.progress});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return _PressableCard(
      onTap: onTap ?? () => _onTap(context),
      onLongPressStart: onLongPress != null
          ? (_) => onLongPress!()
          : (details) => _showQuickActions(context, details.globalPosition),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: RaddRadius.smRadius,
          boxShadow: AppShadows.soft,
        ),
        child: ClipRRect(
          borderRadius: RaddRadius.smRadius,
          child: Stack(fit: StackFit.expand, children: [
            // Poster
            _buildPoster(context),
            // Gradient overlay
            Positioned(bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 32, 8, 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xDD000000)],
                    stops: [0.0, 1.0],
                  ),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 12,
                            fontWeight: FontWeight.w700, height: 1.25,
                            shadows: [Shadow(color: Colors.black54, blurRadius: 6)])),
                  if (showProgress && progress != null) ...[
                    const SizedBox(height: 4),
                    const SizedBox(height: 3),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                        minHeight: 3,
                      ),
                    ),
                  ],
                ]),
              )),
            // Top badges
            Positioned(top: 6, left: 6, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // FIX-13: show only one badge at a time — FREE takes priority over NEW
              if (item.isFree)
                _Badge(label: 'FREE', color: AppColors.success)
              else if (item.isNew == true)
                _Badge(label: 'NEW', color: AppColors.primary),
              if (item.isUploading == true) ...[
                const SizedBox(height: 4),
                _UploadingBadge(),
              ],
              if (item.isOngoingNow) ...[
                const SizedBox(height: 4),
                _StatusBadge(label: 'ONGOING', color: const Color(0xFF22C55E)),
              ] else if (item.isCompleted && !item.isMovie) ...[
                const SizedBox(height: 4),
                _StatusBadge(label: 'COMPLETED', color: const Color(0xFF3B82F6)),
              ],
            ])),
            // Language badge (bottom-left, above title text)
            if (item.language != null && item.language!.isNotEmpty)
              Positioned(bottom: 28, left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: Colors.white24, width: 0.5),
                  ),
                  child: Text(
                    _langLabel(item.language!),
                    style: const TextStyle(
                      color: Colors.white70, fontSize: 8,
                      fontWeight: FontWeight.w600, letterSpacing: 0.3),
                  ),
                )),
            // New-episode badge — bottom-right, symmetric to language badge
            if (item.isShow &&
                item.newEpisodeCount != null &&
                item.newEpisodeCount! > 0)
              Positioned(
                bottom: 28, right: 6,
                child: _NewEpBadge(count: item.newEpisodeCount!),
              ),
            if (item.rating != null && item.rating! > 0)
              Positioned(top: 6, right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black54,
                      borderRadius: BorderRadius.circular(4)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(AppIcons.starFill, color: Colors.amber, size: 10),
                    const SizedBox(width: 2),
                    Text(item.displayRating,
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
                  ]),
                )),
          ]),
        ),
      ),
    );
  }

  Widget _buildPoster(BuildContext context) {
    // Prefer local cached poster (works offline/zero-rated)
    if (item.posterPath != null && item.posterPath!.isNotEmpty) {
      final f = File(item.posterPath!);
      return Image.file(f, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildNetworkPoster(context));
    }
    return _buildNetworkPoster(context);
  }

  Widget _buildNetworkPoster(BuildContext context) {
    final t = RaddTheme.of(context);
    if (item.posterUrl != null && item.posterUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: item.posterUrl!,
        fit: BoxFit.cover,
        placeholder: (_, __) => Shimmer.fromColors(
          baseColor: t.card,
          highlightColor: t.surfaceHigh,
          child: Container(color: t.card),
        ),
        errorWidget: (_, __, ___) => _Fallback(item: item),
      );
    }
    return _Fallback(item: item);
  }

  void _showQuickView(BuildContext context) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _DetailSheet(item: item),
      );
    }

    // Phase 55: long-press card context menu — compact quick-action popup
    // anchored to the press point (Play / Watchlist toggle / More Info),
    // instead of jumping straight to the full quick-view sheet.
    void _showQuickActions(BuildContext context, Offset globalPosition) {
      HapticFeedback.mediumImpact();
      final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
      final screenSize = overlay.size;
      final consumerContainer = ProviderScope.containerOf(context, listen: false);
      final isInWatchlist = consumerContainer.read(watchlistProvider).isInWatchlist(item.id);

      showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(
          globalPosition.dx, globalPosition.dy,
          screenSize.width - globalPosition.dx,
          screenSize.height - globalPosition.dy,
        ),
        color: RaddTheme.of(context).surface,
        shape: RoundedRectangleBorder(
          borderRadius: RaddRadius.mdRadius,
          side: BorderSide(color: RaddTheme.of(context).border),
        ),
        elevation: 12,
        items: [
          _quickActionItem('play', AppIcons.play, 'Play', context),
          _quickActionItem(
            'watchlist',
            isInWatchlist ? AppIcons.bookmarkFill : AppIcons.bookmark,
            isInWatchlist ? 'Remove from Watchlist' : 'Add to Watchlist',
            context,
          ),
          _quickActionItem('info', AppIcons.info, 'More Info', context),
        ],
      ).then((action) {
        if (action == null) return;
        HapticFeedback.selectionClick();
        switch (action) {
          case 'play':
            _onTap(context);
            break;
          case 'watchlist':
            consumerContainer.read(watchlistProvider.notifier).toggle(item);
            break;
          case 'info':
            _showQuickView(context);
            break;
        }
      });
    }

    PopupMenuItem<String> _quickActionItem(
        String value, IconData icon, String label, BuildContext context) {
      final t = RaddTheme.of(context);
      return PopupMenuItem<String>(
        value: value,
        height: 44,
        child: Row(children: [
          Icon(icon, size: 18, color: t.textPrimary),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(
              color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      );
    }

    void _onTap(BuildContext context) {
    // Always navigate to ShowDetailScreen — it handles both movies and shows
    Navigator.of(context).pushNamed(AppRoutes.showDetail, arguments: item);
  }
}

// ── Shimmer Placeholder Card ──────────────────────────────────────────────────
class ShimmerCard extends StatelessWidget {
  const ShimmerCard({super.key});
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return ClipRRect(
      borderRadius: RaddRadius.smRadius,
      child: Shimmer.fromColors(
        baseColor:      t.shimmerBase,
        highlightColor: t.shimmerHighlight,
        child: Stack(fit: StackFit.expand, children: [
          Container(color: t.surface),
          // Subtle gradient sheen at the bottom
          Positioned(bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, t.card],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(height: 8, width: double.infinity,
                      decoration: BoxDecoration(color: t.surfaceHigh,
                          borderRadius: BorderRadius.circular(4))),
                  const SizedBox(height: 4),
                  Container(height: 6, width: 50,
                      decoration: BoxDecoration(color: t.surfaceHigh,
                          borderRadius: BorderRadius.circular(3))),
                ],
              ),
            )),
        ]),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0,1))],
      ),
      child: Text(label, style: const TextStyle(
          color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
    );
  }
}

class _Fallback extends StatelessWidget {
  final CatalogItem item;
  const _Fallback({required this.item});
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [t.card, t.surface],
        ),
      ),
      child: Stack(fit: StackFit.expand, children: [
        Center(
          child: Icon(
            item.isShow ? AppIcons.tv : AppIcons.movie,
            color: t.textMuted.withOpacity(0.4), size: 30),
        ),
        Positioned(bottom: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 18, 6, 8),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xD0000000)],
              ),
            ),
            child: Text(item.title,
                textAlign: TextAlign.center, maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 10,
                    fontWeight: FontWeight.w500)),
          ),
        ),
      ]),
    );
  }
}

class _DetailSheet extends StatelessWidget {
  final CatalogItem item;
  const _DetailSheet({required this.item});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final isShow = item.isShow;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.border.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.55), blurRadius: 32, spreadRadius: 2),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ── Hero banner ──────────────────────────────────────────────
        SizedBox(
          height: 185,
          child: Stack(fit: StackFit.expand, children: [
            // Backdrop poster (local first, then network)
            _SheetPoster(item: item, theme: t),
            // Gradient: transparent → surface colour
            DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.transparent,
                  t.surface.withOpacity(0.75),
                  t.surface,
                ],
                stops: const [0.0, 0.3, 0.7, 1.0],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            )),
            // Drag handle
            Positioned(top: 10, left: 0, right: 0,
              child: Center(
                child: Container(width: 40, height: 4,
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(2))))),
            // Type chip (top-right)
            Positioned(top: 14, right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 6)],
                ),
                child: Text(isShow ? 'TV Show' : 'Movie',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 10,
                        fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              )),
            // Title + meta (bottom)
            Positioned(left: 14, right: 14, bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white, fontSize: 20,
                      fontWeight: FontWeight.w800, letterSpacing: -0.5,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 10,
                          offset: Offset(0, 1))],
                    )),
                  const SizedBox(height: 5),
                  Row(children: [
                    if (item.displayYear.isNotEmpty) ...[
                      Icon(AppIcons.calendar,
                          size: 11, color: Colors.white.withOpacity(0.7)),
                      const SizedBox(width: 4),
                      Text(item.displayYear,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.82),
                              fontSize: 12, fontWeight: FontWeight.w500)),
                    ],
                    if (item.displayYear.isNotEmpty &&
                        item.displayRating.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        child: Text('•',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 12)),
                      ),
                    if (item.displayRating.isNotEmpty) ...[
                      Icon(AppIcons.starFill, color: Colors.amber, size: 13),
                      const SizedBox(width: 3),
                      Text(item.displayRating,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.88),
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ]),
                ],
              )),
          ]),
        ),

        // ── Body ─────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.description != null &&
                  item.description!.isNotEmpty) ...[
                Text(item.description!,
                    maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 13, height: 1.6)),
                const SizedBox(height: 14),
              ] else
                const SizedBox(height: 4),

              // Action buttons
              Row(children: [
                Expanded(
                  flex: 3,
                  child: _SheetBtn(
                    label: isShow ? 'Browse Episodes' : 'Watch Now',
                    icon: isShow
                        ? AppIcons.videoLibrary
                        : AppIcons.play,
                    useGradient: true,
                    onTap: () {
                      Navigator.pop(context);
                      if (isShow) {
                        Navigator.of(context).pushNamed(
                            AppRoutes.showDetail, arguments: item);
                      } else if (item.fileId != null) {
                        // BUG-10 fix: pass is_free, stream_url, content_type so the
                        // player's _isFree/_trackUsage flags are set correctly.
                        // Without is_free, free movies were treated as paid and the
                        // subscription gate blocked guests and free users.
                        Navigator.of(context).pushNamed(AppRoutes.player,
                            arguments: {
                              'file_id':      item.fileId!,
                              'title':        item.title,
                              'stream_url':   item.shareUrl,
                              'is_free':      item.isFree,
                              'content_type': item.mediaType,
                            });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _SheetBtn(
                    label: 'Details',
                    icon: AppIcons.info,
                    useGradient: false,
                    theme: t,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).pushNamed(
                          AppRoutes.showDetail, arguments: item);
                    },
                  ),
                ),
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}

/// Poster widget for the detail sheet hero — local file first, then network.
class _SheetPoster extends StatelessWidget {
  final CatalogItem item;
  final dynamic theme;
  const _SheetPoster({required this.item, required this.theme});

  @override
  Widget build(BuildContext context) {
    if (item.posterPath != null && item.posterPath!.isNotEmpty) {
      final f = File(item.posterPath!);
      if (f.existsSync()) {
        return Image.file(f, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _netPoster(context));
      }
    }
    return _netPoster(context);
  }

  Widget _netPoster(BuildContext context) {
    if (item.posterUrl != null && item.posterUrl!.isNotEmpty) {
      return CachedNetworkImage(
          imageUrl: item.posterUrl!, fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _fallback());
    }
    return _fallback();
  }

  Widget _fallback() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.card, AppColors.surface],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      );
}

/// Reusable action button for the detail sheet.
class _SheetBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool useGradient;
  final dynamic theme;
  final VoidCallback? onTap;

  const _SheetBtn({
    required this.label,
    required this.icon,
    required this.useGradient,
    this.theme,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = theme ?? RaddTheme.of(context);
    return Container(
      height: 46,
      decoration: BoxDecoration(
        gradient: useGradient ? AppColors.primaryGradient : null,
        color: useGradient ? null : t.card,
        borderRadius: RaddRadius.mdRadius,
        border: useGradient ? null : Border.all(color: t.border, width: 1.5),
        boxShadow: useGradient ? AppShadows.primary : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: RaddRadius.mdRadius,
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  color: useGradient ? Colors.white : t.textSecondary,
                  size: 18),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: useGradient ? Colors.white : t.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small badge shown on show cards when new episodes were added since last view.
class _NewEpBadge extends StatelessWidget {
  final int count;
  const _NewEpBadge({required this.count});
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 5,
            offset: Offset(0, 1))],
      ),
      child: Text(
        count > 99 ? '99+ EP' : '+$count EP',
        style: const TextStyle(
          color: Colors.white, fontSize: 8,
          fontWeight: FontWeight.w900, letterSpacing: 0.4),
      ),
    );
  }
}

/// Capitalise first letter of each word, max 12 chars.
String _langLabel(String lang) {
  final words = lang.trim().split(RegExp(r'[_\s]+'));
  final label = words.map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}').join(' ');
  return label.length > 12 ? label.substring(0, 12) : label;
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label,
        style: const TextStyle(color: Colors.white, fontSize: 7,
            fontWeight: FontWeight.w800, letterSpacing: 0.3)),
    );
  }
}

class _UploadingBadge extends StatefulWidget {
  const _UploadingBadge();
  @override
  State<_UploadingBadge> createState() => _UploadingBadgeState();
}

class _UploadingBadgeState extends State<_UploadingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1.0).animate(
          CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.orange,
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Text('⬆ UPLOADING',
          style: TextStyle(color: Colors.white, fontSize: 7,
              fontWeight: FontWeight.w800, letterSpacing: 0.4)),
      ),
    );
  }
}

// ── Pressable card wrapper: scale on press + haptic tap feedback ──────────────
class _PressableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final void Function(LongPressStartDetails)? onLongPressStart;
  const _PressableCard({required this.child, this.onTap, this.onLongPressStart});
  @override
  State<_PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<_PressableCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap?.call();
      },
      onLongPressStart: widget.onLongPressStart,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: RepaintBoundary(child: widget.child),
      ),
    );
  }
}

