import 'dart:io';
import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import '../core/theme/radd_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../models/catalog_item.dart';
import '../services/actor_service.dart';
import '../screens/actor_screen.dart';
import '../core/constants.dart';

/// Horizontal scrolling cast strip shown on the show detail screen.
/// Hidden automatically when cast data is unavailable or the actor list is empty.
class CastRail extends StatelessWidget {
  final CatalogItem item;
  const CastRail({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CastMember>>(
      future: ActorService.getCastForTitle(item),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _CastShimmer();
        }
        final cast = snap.data ?? [];
        if (cast.isEmpty) return const SizedBox.shrink();
        return _CastStrip(cast: cast);
      },
    );
  }
}

// ── Strip widget ────────────────────────────────────────────────────────────

class _CastStrip extends StatelessWidget {
  final List<CastMember> cast;
  const _CastStrip({required this.cast});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    // Show first 10 inline; "See All" available when more exist
    final visible = cast.take(10).toList();
    final hasMore = cast.length > 10;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header row: "Cast" label + count + See All
      Row(children: [
        Text('Cast',
            style: TextStyle(color: t.textPrimary, fontSize: 15,
                fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(AppRadius.round),
          ),
          child: Text('${cast.length}',
              style: const TextStyle(color: AppColors.primary,
                  fontSize: 10, fontWeight: FontWeight.w700)),
        ),
        const Spacer(),
        if (hasMore)
          GestureDetector(
            onTap: () => _showAllCast(context, cast),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(AppRadius.round),
                border: Border.all(color: t.border),
              ),
              child: const Text('See All',
                  style: TextStyle(color: AppColors.primary,
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
      ]),
      const SizedBox(height: 10),
      SizedBox(
        height: 150,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: visible.length,
          itemBuilder: (_, i) => _CastCard(member: visible[i]),
        ),
      ),
    ]);
  }

  void _showAllCast(BuildContext context, List<CastMember> cast) {
    final t = RaddTheme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (ctx, ctrl) => Container(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: t.border),
          ),
          child: Column(children: [
            // Handle
            Container(width: 36, height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                decoration: BoxDecoration(
                    color: t.textMuted.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(children: [
                Text('Full Cast',
                    style: TextStyle(color: t.textPrimary, fontSize: 17,
                        fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                Text('${cast.length} members',
                    style: TextStyle(color: t.textMuted, fontSize: 13)),
              ]),
            ),
            Expanded(
              child: GridView.builder(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio: 0.68,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 12,
                ),
                itemCount: cast.length,
                itemBuilder: (_, i) => _CastCard(member: cast[i], compact: true),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Single cast card ────────────────────────────────────────────────────────

class _CastCard extends StatelessWidget {
  final CastMember member;
  final bool compact;
  const _CastCard({required this.member, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final photoSize = compact ? 58.0 : 72.0;
    final cardWidth = compact ? 72.0 : 84.0;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ActorScreen(member: member)),
      ),
      child: Container(
        width: cardWidth,
        margin: const EdgeInsets.only(right: 10),
        child: Column(children: [
          // Photo
          Container(
            width: photoSize, height: photoSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: t.surface,
              border: Border.all(color: t.border, width: 1),
            ),
            child: ClipOval(child: _photo(t, photoSize)),
          ),
          const SizedBox(height: 6),
          // Name
          Text(
            member.name,
            style: TextStyle(color: t.textPrimary, fontSize: 11,
                fontWeight: FontWeight.w600, height: 1.2),
            maxLines: 2, overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          if (member.character != null && member.character!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              member.character!,
              style: TextStyle(color: t.textMuted, fontSize: 11, height: 1.2),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ]),
      ),
    );
  }

  Widget _photo(RaddTheme t, double size) {
    if (member.profileLocal != null) {
      final f = File(member.profileLocal!);
      if (f.existsSync()) {
        return Image.file(f, width: size, height: size, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(t, size));
      }
    }
    if (member.profileUrl != null) {
      return CachedNetworkImage(
        imageUrl: member.profileUrl!,
        width: size, height: size, fit: BoxFit.cover,
        // K4: fade actor photos in instead of a hard pop-in once the network
        // fetch resolves — matches the fadeIn treatment already expected on
        // poster art elsewhere in the design system.
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (_, __) => _placeholder(t, size),
        errorWidget: (_, __, ___) => _placeholder(t, size),
      );
    }
    return _placeholder(t, size);
  }

  Widget _placeholder(RaddTheme t, double size) => Container(
    color: t.bg,
    child: Icon(AppIcons.profileFill, color: t.textMuted, size: size * 0.45),
  );
}

// ── Loading shimmer ─────────────────────────────────────────────────────────

class _CastShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 40, height: 14, color: t.surface),
        const SizedBox(width: 8),
        Container(width: 20, height: 14, color: t.surface),
      ]),
      const SizedBox(height: 10),
      Shimmer.fromColors(
        baseColor: t.surface,
        highlightColor: t.border,
        child: SizedBox(
          height: 150,
          child: Row(
            children: List.generate(10, (_) => Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 72, height: 72,
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: t.surface),
                ),
                Container(width: 58, height: 10, color: t.surface),
                const SizedBox(height: 4),
                Container(width: 42, height: 9, color: t.surface),
              ]),
            )),
          ),
        ),
      ),
    ]);
  }
}
