/// Phase I2 — Reaction Stamps
/// Tap emoji reactions while watching → they float up from the bottom.
/// Timestamps saved so you can see "reactions at this moment" on seek bar.
library reaction_stamps;

import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// ── Reaction entry (saved with timestamp) ────────────────────────────────────
class ReactionEntry {
  final String emoji;
  final Duration position;
  final DateTime createdAt;

  ReactionEntry({required this.emoji, required this.position, required this.createdAt});

  Map<String, dynamic> toJson() => {
    'emoji': emoji,
    'posMs': position.inMilliseconds,
    'at': createdAt.toIso8601String(),
  };
  factory ReactionEntry.fromJson(Map<String, dynamic> j) => ReactionEntry(
    emoji: j['emoji'],
    position: Duration(milliseconds: j['posMs'] as int),
    createdAt: DateTime.parse(j['at']),
  );
}

// ── Reaction timestamp store ──────────────────────────────────────────────────
class ReactionStore {
  ReactionStore._();
  static final instance = ReactionStore._();

  Future<void> save(String contentId, ReactionEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'reactions_$contentId';
    final raw = prefs.getString(key) ?? '[]';
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>()
        .map(ReactionEntry.fromJson).toList();
    list.add(entry);
    await prefs.setString(key, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  Future<List<ReactionEntry>> load(String contentId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('reactions_$contentId') ?? '[]';
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>()
        .map(ReactionEntry.fromJson).toList();
  }

  Future<void> clear(String contentId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('reactions_$contentId');
  }
}

// ── Available emoji reactions ─────────────────────────────────────────────────
const _reactionEmojis = ['❤️', '😂', '😮', '😢', '🔥', '👏', '😍', '💯'];

// ── Active floating emoji particle ───────────────────────────────────────────
class _Particle {
  final String emoji;
  final double x;           // 0.0–1.0 horizontal start
  late AnimationController ctrl;
  late Animation<double> y;    // 0.0 = bottom, 1.0 = top
  late Animation<double> opacity;
  late Animation<double> scale;

  _Particle({required this.emoji, required this.x, required TickerProvider vsync}) {
    ctrl = AnimationController(duration: const Duration(milliseconds: 2200), vsync: vsync);
    y = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: ctrl, curve: Curves.easeOut));
    opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 70),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 20),
    ]).animate(ctrl);
    scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.4, end: 1.2), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 10),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.8), weight: 75),
    ]).animate(ctrl);
  }

  void dispose() => ctrl.dispose();
}

// ─────────────────────────────────────────────────────────────────────────────
/// Reaction panel + floating emoji overlay.
/// Place in the player Stack.
class ReactionStampsOverlay extends StatefulWidget {
  final Duration position;
  final String contentId;
  final Color accentColor;
  final bool visible; // show panel (when controls visible)

  const ReactionStampsOverlay({
    super.key,
    required this.position,
    required this.contentId,
    required this.accentColor,
    required this.visible,
  });

  @override
  State<ReactionStampsOverlay> createState() => _ReactionStampsOverlayState();
}

class _ReactionStampsOverlayState extends State<ReactionStampsOverlay>
    with TickerProviderStateMixin {
  final List<_Particle> _particles = [];
  final _rng = math.Random();

  void _fire(String emoji) async {
    HapticFeedback.lightImpact();
    final p = _Particle(
      emoji: emoji,
      x: 0.1 + _rng.nextDouble() * 0.2,  // left 10-30% to avoid seek bar
      vsync: this,
    );
    p.ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        setState(() { _particles.remove(p); p.dispose(); });
      }
    });
    setState(() => _particles.add(p));
    p.ctrl.forward();

    // Persist reaction timestamp
    await ReactionStore.instance.save(
      widget.contentId,
      ReactionEntry(emoji: emoji, position: widget.position, createdAt: DateTime.now()),
    );
  }

  @override
  void dispose() {
    for (final p in _particles) {
      p.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      // Floating emoji particles
      ..._particles.map((p) => AnimatedBuilder(
        animation: p.ctrl,
        builder: (_, __) {
          final size = MediaQuery.of(context).size;
          return Positioned(
            left: p.x * size.width,
            bottom: p.y.value * size.height * 0.65 + 80,
            child: Opacity(
              opacity: p.opacity.value.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: p.scale.value,
                child: Text(p.emoji,
                    style: const TextStyle(fontSize: 32)),
              ),
            ),
          );
        },
      )),

      // Emoji picker panel (left side, visible when controls are shown)
      if (widget.visible)
        Positioned(
          left: 8,
          top: 0,
          bottom: 0,
          child: Center(
            child: Container(
              width: 44,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.58),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white15),
              ),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _reactionEmojis.map((e) => GestureDetector(
                  onTap: () => _fire(e),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(e, style: const TextStyle(fontSize: 22)),
                  ),
                )).toList(),
              ),
            ),
          ),
        ),
    ]);
  }
}
