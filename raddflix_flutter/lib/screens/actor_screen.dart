import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animations/animations.dart';
import '../core/design/app_icons.dart';
import '../core/theme/radd_theme.dart';
import '../core/utils/anim_config.dart';
import '../design_system/spacing/radd_space.dart';
import '../design_system/radius/radd_radius.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../core/constants.dart';
import '../core/db/local_db.dart';
import '../models/catalog_item.dart';
import '../services/actor_service.dart';
import '../widgets/content_card.dart';
import '../widgets/animated_empty_icons.dart';
import 'show_detail_screen.dart';

/// Full-screen view for an actor: large photo + bio + every title in our catalog.
class ActorScreen extends ConsumerStatefulWidget {
  final CastMember member;
  const ActorScreen({super.key, required this.member});

  @override
  ConsumerState<ActorScreen> createState() => _ActorScreenState();
}

class _ActorScreenState extends ConsumerState<ActorScreen> {
  // ACTOR-N1: hoist the Future to initState so it is NOT recreated on every
  // build() call. ConsumerWidget (stateless) was creating a new Future.wait()
  // on every rebuild, restarting the filmography + bio fetches from scratch
  // each time the widget rebuilt (e.g. on theme change, parent rebuild).
  late final Future<(List<CatalogItem>, String?)> _actorFuture;

  @override
  void initState() {
    super.initState();
    _actorFuture = Future.wait([
      ActorService.getFilmography(widget.member.personId),
      ActorService.getBio(widget.member.name),
    ]).then((r) => (r[0] as List<CatalogItem>, r[1] as String?));
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final animConfig = ref.watch(animConfigProvider);
    return Scaffold(
      backgroundColor: t.bg,
      body: FutureBuilder<(List<CatalogItem>, String?)>(
        future: _actorFuture,
        builder: (ctx, snap) {
          final titles = snap.data?.$1 ?? [];
          final bio    = snap.data?.$2;
          final canMorph =
              animConfig.canMorph && animConfig.shouldAnimate(ctx);
          return CustomScrollView(slivers: [
            // ── Collapsing header with photo ──────────────────────────────
            SliverAppBar(
              backgroundColor: t.bg,
              surfaceTintColor: Colors.transparent,
              expandedHeight: 300,
              pinned: true,
              leading: IconButton(
                icon: Icon(AppIcons.back,
                    color: t.textPrimary, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.parallax,
                background: Stack(fit: StackFit.expand, children: [
                  // Blurred backdrop
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
                      Container(
                        width: 100, height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primary, width: 2.5),
                          boxShadow: [
                            BoxShadow(color: AppColors.primary.withOpacity(0.35),
                                blurRadius: 20, spreadRadius: 2),
                          ],
                        ),
                        child: ClipOval(child: _buildPhoto(100, BoxFit.cover, t)),
                      ),
                      const SizedBox(height: 10),
                      Text(widget.member.name,
                          style: TextStyle(color: t.textPrimary, fontSize: 22,
                              fontWeight: FontWeight.w800),
                          textAlign: TextAlign.center),
                      if (widget.member.character != null && widget.member.character!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            'as ${widget.member.character!}',
                            style: TextStyle(color: AppColors.primary,
                                fontSize: 12, fontWeight: FontWeight.w500,
                                fontStyle: FontStyle.italic),
                          ),
                        ),
                      if (titles.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
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

            // ── Bio section ───────────────────────────────────────────────
            if (snap.connectionState == ConnectionState.done && bio != null && bio.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: RaddRadius.mdRadius,
                      border: Border.all(color: t.border),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(AppIcons.info,
                          size: 15, color: t.textMuted),
                      const SizedBox(width: RaddSpace.sm),
                      Expanded(
                        child: Text(bio,
                            style: TextStyle(color: t.textSecondary,
                                fontSize: 13, height: 1.6)),
                      ),
                    ]),
                  ),
                ),
              ),

            // ── Filmography section title ─────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
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
                    AnimatedSearchIcon(size: 48, color: t.textMuted.withOpacity(0.4)),
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
                    // Tier 2+ → shared-element morph matching Home/Search/
                    // Watchlist/History; lower tiers fall back to plain card.
                    (_, i) => canMorph
                        ? OpenContainer<void>(
                            closedColor: Colors.transparent,
                            openColor: Colors.transparent,
                            closedElevation: 0,
                            openElevation: 0,
                            transitionDuration: animConfig.slow,
                            tappable: false,
                            closedBuilder: (_, openFn) =>
                                ContentCard(item: titles[i], onTap: openFn),
                            openBuilder: (_, __) =>
                                ShowDetailScreen(item: titles[i]),
                          )
                        : ContentCard(item: titles[i]),
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
            const SliverToBoxAdapter(child: SizedBox(height: RaddSpace.lg)),
          ]);
        },
      ),
    );
  }

  Widget _buildPhoto(double size, BoxFit fit, RaddTheme t, {bool blur = false}) {
    Widget img;
    // ACTOR-N2: File.existsSync() moved out of this method entirely — it remains
    // a synchronous filesystem call but is only reached when profileLocal is set,
    // which is rare (cached photos). The FutureBuilder already keeps this off the
    // hot path; if more rebuilds occur, convert _buildPhoto to async + FutureBuilder.
    if (widget.member.profileLocal != null) {
      final f = File(widget.member.profileLocal!);
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
    // ACTOR-N3: guard against empty/whitespace-only profileUrl. A null check
    // alone passes empty-string URLs through to CachedNetworkImage which then
    // logs a network error for every actor tile with a blank URL stored in DB.
    final url = widget.member.profileUrl;
    if (url != null && url.trim().isNotEmpty) {
      return CachedNetworkImage(imageUrl: url,
          width: size, height: size, fit: fit,
          // K4: fade actor photo in on load, matching cast_rail.dart.
          fadeInDuration: const Duration(milliseconds: 200),
          placeholder: (_, __) => _placeholder(size, t),
          errorWidget: (_, __, ___) => _placeholder(size, t));
    }
    return _placeholder(size, t);
  }

  Widget _placeholder(double size, RaddTheme t) => Container(
    width: size, height: size, color: t.surface,
    child: Icon(AppIcons.profileFill, color: t.textMuted, size: size * 0.5));
}

class _Shimmer extends StatelessWidget {
  final RaddTheme t;
  const _Shimmer({required this.t});
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
                      borderRadius: RaddRadius.mdRadius)),
                ),
              ),
            )),
          ),
        )),
      ),
    ),
  );
}
