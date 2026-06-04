import 'dart:io';
import 'package:flutter/material.dart';
import '../core/theme/radd_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../models/catalog_item.dart';
import '../services/actor_service.dart';
import '../screens/actor_screen.dart';

/// Horizontal scrolling cast strip shown on the show detail screen.
/// Hidden automatically when TMDB key is absent or cast is unavailable.
class CastRail extends StatelessWidget {
  final CatalogItem item;
  const CastRail({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    if (!ActorService.hasKey) return const SizedBox.shrink();
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Cast',
          style: TextStyle(color: t.textPrimary, fontSize: 15,
              fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      SizedBox(
        height: 128,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: cast.length,
          itemBuilder: (_, i) => _CastCard(member: cast[i]),
        ),
      ),
    ]);
  }
}

// ── Single cast card ────────────────────────────────────────────────────────

class _CastCard extends StatelessWidget {
  final CastMember member;
  const _CastCard({required this.member});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ActorScreen(member: member)),
      ),
      child: Container(
        width: 74,
        margin: const EdgeInsets.only(right: 10),
        child: Column(children: [
          // Photo
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: t.surface,
              border: Border.all(color: t.border, width: 1),
            ),
            child: ClipOval(child: _photo(t)),
          ),
          const SizedBox(height: 5),
          // Name
          Text(
            member.name,
            style: TextStyle(color: t.textPrimary, fontSize: 10,
                fontWeight: FontWeight.w600, height: 1.2),
            maxLines: 2, overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          if (member.character != null && member.character!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              member.character!,
              style: TextStyle(color: t.textMuted, fontSize: 9, height: 1.2),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ]),
      ),
    );
  }

  Widget _photo(RaddTheme t) {
    // 1. Local internal-storage file (downloaded, private, most preferred)
    if (member.profileLocal != null) {
      final f = File(member.profileLocal!);
      if (f.existsSync()) {
        return Image.file(f, width: 64, height: 64, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(t));
      }
    }
    // 2. Network (also caches internally via CachedNetworkImage)
    if (member.profileUrl != null) {
      return CachedNetworkImage(
        imageUrl: member.profileUrl!,
        width: 64, height: 64, fit: BoxFit.cover,
        placeholder: (_, __) => _placeholder(t),
        errorWidget: (_, __, ___) => _placeholder(t),
      );
    }
    // 3. Fallback
    return _placeholder(t);
  }

  Widget _placeholder(RaddTheme t) => Container(
    color: t.bg,
    child: Icon(Icons.person_rounded, color: t.textMuted, size: 30),
  );
}

// ── Loading shimmer ─────────────────────────────────────────────────────────

class _CastShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 40, height: 14, color: t.surface),
      const SizedBox(height: 10),
      Shimmer.fromColors(
        baseColor: t.surface,
        highlightColor: t.border,
        child: Row(
          children: List.generate(5, (_) => Container(
            width: 64, height: 64,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(shape: BoxShape.circle, color: t.surface),
          )),
        ),
      ),
    ]);
  }
}
