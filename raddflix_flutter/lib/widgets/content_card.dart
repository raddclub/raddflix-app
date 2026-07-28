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
          border: Border.all(color: t.cardBorder.withOpacity(0.22), width: 0.5),
        ),
        child: ClipRRect(
          borderRadius: RaddRadius.smRadius,
          child: Stack(fit: StackFit.expand, children: [
            // Poster
            _buildPoster(context),
            // ── Frosted base overlay — glass-tinted dark bottom ────────────
            Positioned(bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 44, 8, 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0x55000008), // blue-tinted semi-transparent mid
                      Color(0xF0000010), // near-opaque rich dark bottom
                    ],
                    stops: [0.0, 0.45, 1.0],
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
              if (!item.isFree && item.isNew != true && item.isOngoingNow)
                _StatusBadge(label: 'ONGOING', color: AppColors.success),
            ])),
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

    // UX4-12: replaced position-anchored showMenu with showModalBottomSheet —
    // consistent with every other action sheet in the app.
    void _showQuickActions(BuildContext context, Offset globalPosition) {
      HapticFeedback.mediumImpact();
      final container   = ProviderScope.containerOf(context, listen: false);
      final isInWatchlist = container.read(watchlistProvider).isInWatchlist(item.id);
      final t = RaddTheme.of(context);

      Widget sheetRow(IconData icon, String label, VoidCallback onTap) =>
          InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Icon(icon, size: 20, color: t.textPrimary),
                  const SizedBox(width: 14),
                  Text(label, style: TextStyle(
                      color: t.textPrimary, fontSize: 14,
                      fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          );

      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => Container(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 34),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Handle bar
            Center(child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: t.textMuted.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            sheetRow(AppIcons.play, 'Play', () {
              Navigator.pop(context);
              HapticFeedback.selectionClick();
              _onTap(context);
            }),
            Divider(height: 1, color: t.border),
            sheetRow(
              isInWatchlist ? AppIcons.bookmarkFill : AppIcons.bookmark,
              isInWatchlist ? 'Remove from Watchlist' : 'Add to Watchlist',
              () {
                Navigator.pop(context);
                HapticFeedback.selectionClick();
                container.read(watchlistProvider.notifier).toggle(item);
              },
            ),
            Divider(height: 1, color: t.border),
            sheetRow(AppIcons.info, 'More Info', () {
              Navigator.pop(context);
              HapticFeedback.selectionClick();
              _showQuickView(context);
            }),
          ]),
        ),
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
    // Wrap in same glass border treatment as ContentCard for visual consistency
    return Container(
      decoration: BoxDecoration(
        borderRadius: RaddRadius.smRadius,
        border: Border(
          top:    BorderSide(color: Colors.white.withOpacity(0.18), width: 0.8),
          left:   BorderSide(color: Colors.white.withOpacity(0.08), width: 0.5),
          right:  BorderSide(color: Colors.white.withOpacity(0.04), width: 0.5),
          bottom: BorderSide(color: t.cardBorder.withOpacity(0.30), width: 0.5),
        ),
      ),
      child: ClipRRect(
        borderRadius: RaddRadius.smRadius,
        child: Shimmer.fromColors(
          baseColor:      t.shimmerBase,
          highlightColor: t.shimmerHighlight,
          child: Stack(fit: StackFit.expand, children: [
            Container(color: t.surface),
            // Specular highlight — matches loaded ContentCard glass rim
            Positioned(top: 0, left: 0, right: 0,
              child: Container(
                height: 60,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Color(0x16FFFFFF), Colors.transparent],
                  ),
                ),
              ),
            ),
            // Frosted gradient sheen at the bottom
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
    ));
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
                              'poster_url':   item.posterUrl,
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

// ── Glint sweep overlay ───────────────────────────────────────────────────────
// A diagonal bright band that sweeps across the card once every ~4 seconds,
// simulating light moving across a glass surface.  Tier 1+ only (API 23+).
class _GlintOverlay extends StatefulWidget {
  const _GlintOverlay();
  @override
  State<_GlintOverlay> createState() => _GlintOverlayState();
}

class _GlintOverlayState extends State<_GlintOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    // Stagger first glint so not all cards fire simultaneously
    final delay = 600 + (hashCode.abs() % 3200);
    Future.delayed(Duration(milliseconds: delay), _fire);
  }

  void _fire() {
    if (!mounted) return;
    _ctrl.forward(from: 0).then((_) {
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 3600), _fire);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _anim,
          builder: (_, __) {
            // Sweep the bright centre from -0.2 → 1.2 so it starts and ends
            // fully off-screen, appearing as a clean diagonal flash.
            final c = -0.22 + _anim.value * 1.44;
            final stops = [
              (c - 0.22).clamp(0.0, 1.0),
              (c - 0.07).clamp(0.0, 1.0),
              c.clamp(0.0, 1.0),
              (c + 0.07).clamp(0.0, 1.0),
              (c + 0.22).clamp(0.0, 1.0),
            ];
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  // Diagonal top-left → bottom-right (matches specular angle)
                  begin: const Alignment(-0.6, -1.0),
                  end: const Alignment(0.6, 1.0),
                  colors: const [
                    Colors.transparent,
                    Color(0x0CFFFFFF), // 5% soft edge
                    Color(0x1EFFFFFF), // 12% peak — clearly visible glass flash
                    Color(0x0CFFFFFF), // 5% soft edge
                    Colors.transparent,
                  ],
                  stops: stops,
                ),
              ),
            );
          },
        ),
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

