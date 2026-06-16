import 'dart:io';
import 'package:flutter/material.dart';
import '../core/theme/radd_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../core/constants.dart';
import '../core/db/local_db.dart';
import '../models/catalog_item.dart';
import '../services/actor_service.dart';
import '../widgets/content_card.dart';

/// Full-screen view for an actor: large photo + every title in our catalog
/// that features them. Tapping a title navigates to its detail screen.
class ActorScreen extends StatelessWidget {
  final CastMember member;
  const ActorScreen({super.key, required this.member});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Scaffold(
      backgroundColor: t.bg,
      body: FutureBuilder<List<CatalogItem>>(
        future: ActorService.getFilmography(member.personId),
        builder: (context, snap) {
          final titles = snap.data ?? [];
          return CustomScrollView(slivers: [
            // ── Collapsing header with photo ──────────────────────────────
            SliverAppBar(
              backgroundColor: t.bg,
              surfaceTintColor: Colors.transparent,
              expandedHeight: 280,
              pinned: true,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    color: t.textPrimary, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.parallax,
                background: Stack(fit: StackFit.expand, children: [
                  // Blurred backdrop (actor photo, desaturated)
                  _buildPhoto(64, BoxFit.cover, t, blur: true),
                  // Dark gradient overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          t.bg.withOpacity(0.2),
                          t.bg.withOpacity(0.85),
                          t.bg,
                        ],
                        stops: const [0.0, 0.65, 1.0],
                      ),
                    ),
                  ),
                  // Centered avatar + name
                  Positioned(
                    bottom: 20, left: 0, right: 0,
                    child: Column(children: [
                      // Circular photo
                      Container(
                        width: 96, height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primary, width: 2),
                          boxShadow: [
                            BoxShadow(color: AppColors.primary.withOpacity(0.3),
                                blurRadius: 16, spreadRadius: 2),
                          ],
                        ),
                        child: ClipOval(child: _buildPhoto(96, BoxFit.cover, t)),
                      ),
                      const SizedBox(height: 10),
                      Text(member.name,
                          style: TextStyle(color: t.textPrimary, fontSize: 20,
                              fontWeight: FontWeight.w800),
                          textAlign: TextAlign.center),
                      if (titles.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            '${titles.length} title${titles.length == 1 ? "" : "s"} in RaddFlix',
                            style: TextStyle(color: t.textMuted, fontSize: 12),
                          ),
                        ),
                    ]),
                  ),
                ]),
              ),
            ),

            // ── Filmography section title ─────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text('Filmography',
                    style: TextStyle(color: t.textPrimary, fontSize: 16,
                        fontWeight: FontWeight.w800)),
              ),
            ),

            // ── Grid of titles ────────────────────────────────────────────
            if (snap.connectionState == ConnectionState.waiting)
              SliverToBoxAdapter(child: _Shimmer(t: t))
            else if (titles.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.movie_filter_outlined,
                        size: 48, color: t.textMuted.withOpacity(0.4)),
                    const SizedBox(height: 12),
                    Text('No titles in our catalog yet',
                        style: TextStyle(color: t.textMuted, fontSize: 14),
                        textAlign: TextAlign.center),
                  ]),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => ContentCard(item: titles[i]),
                    childCount: titles.length,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.62,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ]);
        },
      ),
    );
  }

  Widget _buildPhoto(double size, BoxFit fit, RaddTheme t, {bool blur = false}) {
    Widget img;
    if (member.profileLocal != null) {
      final f = File(member.profileLocal!);
      if (f.existsSync()) {
        img = Image.file(f, width: size, height: size, fit: fit,
            errorBuilder: (_, __, ___) => _placeholder(size, t));
      } else {
        img = _networkOrPlaceholder(size, fit, t);
      }
    } else {
      img = _networkOrPlaceholder(size, fit, t);
    }
    if (blur) {
      return ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0,      0,      0,      1, 0,
        ]),
        child: img,
      );
    }
    return img;
  }

  Widget _networkOrPlaceholder(double size, BoxFit fit, RaddTheme t) {
    if (member.profileUrl != null) {
      return CachedNetworkImage(imageUrl: member.profileUrl!,
          width: size, height: size, fit: fit,
          placeholder: (_, __) => _placeholder(size, t),
          errorWidget: (_, __, ___) => _placeholder(size, t));
    }
    return _placeholder(size, t);
  }

  Widget _placeholder(double size, RaddTheme t) => Container(
    width: size, height: size, color: t.surface,
    child: Icon(Icons.person_rounded, color: t.textMuted, size: size * 0.5));
}

class _Shimmer extends StatelessWidget {
  final RaddTheme t;
  const _Shimmer({required this.t});
  // M-04: replaced GridView.builder(shrinkWrap:true) inside a SliverToBoxAdapter
  // with a plain Column of rows — shrinkWrap inside CustomScrollView causes double
  // layout passes and scroll performance issues.
  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
    baseColor: t.surface, highlightColor: t.border,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: List.generate(2, (_) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: List.generate(3, (__) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: AspectRatio(
                  aspectRatio: 0.62,
                  child: Container(
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(AppRadius.md))),
                ),
              ),
            )),
          ),
        )),
      ),
    ),
  );
}
