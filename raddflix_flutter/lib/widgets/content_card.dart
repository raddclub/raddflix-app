import 'dart:io';
import 'package:flutter/material.dart';
import '../core/theme/radd_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../core/constants.dart';
import '../models/catalog_item.dart';

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
      onLongPress: onLongPress ?? () => _showQuickView(context),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          boxShadow: AppShadows.soft,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
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
                      style: const TextStyle(color: Colors.white, fontSize: 11,
                          fontWeight: FontWeight.w600,
                          shadows: [Shadow(color: Colors.black, blurRadius: 8)])),
                  if (showProgress && progress != null) ...[
                    const SizedBox(height: 4),
                    LinearProgressIndicator(value: progress,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                        minHeight: 2),
                  ],
                ]),
              )),
            // Top badges
            Positioned(top: 6, left: 6, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (item.isFree) _Badge(label: 'FREE', color: AppColors.success),
              if (item.isNew == true) ...[
                const SizedBox(height: 4),
                _Badge(label: 'NEW', color: AppColors.primary),
              ],
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
                    const Icon(Icons.star_rounded, color: Colors.amber, size: 10),
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
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Shimmer.fromColors(
        baseColor: t.surface,
        highlightColor: t.surfaceHigh,
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
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      child: Text(label, style: const TextStyle(
          color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
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
            item.isShow ? Icons.tv_outlined : Icons.movie_outlined,
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
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: t.border),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 16),
            decoration: BoxDecoration(color: t.textMuted.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2))),
        Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Mini poster
            if (item.posterUrl != null)
              ClipRRect(borderRadius: BorderRadius.circular(AppRadius.sm),
                child: SizedBox(width: 64, height: 96,
                  child: CachedNetworkImage(imageUrl: item.posterUrl!, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(color: t.card)))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title, style: TextStyle(color: t.textPrimary,
                  fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
              const SizedBox(height: 6),
              Row(children: [
                if (item.displayYear.isNotEmpty)
                  Text(item.displayYear, style: TextStyle(color: t.textMuted, fontSize: 13)),
                if (item.displayYear.isNotEmpty && item.displayRating.isNotEmpty)
                  Text(' · ', style: TextStyle(color: t.textMuted)),
                if (item.displayRating.isNotEmpty)
                  Row(children: [
                    const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                    Text(item.displayRating, style: TextStyle(color: t.textMuted, fontSize: 13)),
                  ]),
              ]),
              const SizedBox(height: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(item.isShow ? 'TV Show' : 'Movie',
                    style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600))),
            ])),
          ]),
          if (item.description != null && item.description!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(item.description!, maxLines: 4, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.6)),
          ],
          const SizedBox(height: 20),
          Container(height: 50,
            decoration: BoxDecoration(gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(AppRadius.md), boxShadow: AppShadows.primary),
            child: Material(color: Colors.transparent,
              child: InkWell(borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: item.fileId != null ? () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.player,
                      arguments: {'file_id': item.fileId!, 'title': item.title});
                } : null,
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 6),
                  Text('Watch Now', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                ])))),
        ]),
        ),
      ]),
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
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(3),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4,
            offset: Offset(0, 1))],
      ),
      child: Text(
        '+$count EP',
        style: const TextStyle(
          color: Colors.white, fontSize: 8,
          fontWeight: FontWeight.w800, letterSpacing: 0.3),
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
  final VoidCallback? onLongPress;
  const _PressableCard({required this.child, this.onTap, this.onLongPress});
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
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: RepaintBoundary(child: widget.child),
      ),
    );
  }
}
