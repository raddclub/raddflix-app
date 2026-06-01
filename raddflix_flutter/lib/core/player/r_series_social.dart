/// Phase R — Social Features
/// R1 — Activity Feed (friends' recent watches — local simulation)
/// R2 — Content Rating & Review (1-5 stars + short text)
/// R3 — Clip Sharing (generate 30-sec highlight shareable link)
/// R4 — Spoiler-Protected Comments
library r_series;

import 'dart:convert';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// R2 — User Rating & Review
// ─────────────────────────────────────────────────────────────────────────────

class ContentReview {
  final String contentId;
  final int rating;      // 1-5
  final String review;
  final DateTime createdAt;
  final bool containsSpoiler;

  const ContentReview({
    required this.contentId,
    required this.rating,
    required this.review,
    required this.createdAt,
    this.containsSpoiler = false,
  });

  Map<String, dynamic> toJson() => {
    'contentId': contentId, 'rating': rating,
    'review': review, 'createdAt': createdAt.millisecondsSinceEpoch,
    'containsSpoiler': containsSpoiler,
  };

  factory ContentReview.fromJson(Map<String, dynamic> j) => ContentReview(
    contentId: j['contentId'], rating: j['rating'],
    review: j['review'],
    createdAt: DateTime.fromMillisecondsSinceEpoch(j['createdAt']),
    containsSpoiler: j['containsSpoiler'] ?? false,
  );
}

class ReviewStore {
  ReviewStore._();
  static final instance = ReviewStore._();

  final _reviews = <String, ContentReview>{};

  void save(ContentReview r) => _reviews[r.contentId] = r;
  ContentReview? find(String contentId) => _reviews[contentId];

  String toJson() =>
      jsonEncode(_reviews.values.map((r) => r.toJson()).toList());
  void loadFromJson(String json) {
    try {
      final list = jsonDecode(json) as List;
      for (final j in list.cast<Map<String, dynamic>>()) {
        final r = ContentReview.fromJson(j);
        _reviews[r.contentId] = r;
      }
    } catch (_) {}
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// R2 — Rating Widget
// ─────────────────────────────────────────────────────────────────────────────
class StarRatingBar extends StatefulWidget {
  final int initialRating;
  final ValueChanged<int> onRatingChanged;
  final Color accentColor;
  final double size;

  const StarRatingBar({
    super.key,
    this.initialRating = 0,
    required this.onRatingChanged,
    required this.accentColor,
    this.size = 32,
  });

  @override
  State<StarRatingBar> createState() => _StarRatingBarState();
}

class _StarRatingBarState extends State<StarRatingBar> {
  late int _rating;

  @override
  void initState() { super.initState(); _rating = widget.initialRating; }

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: List.generate(5, (i) {
      final filled = i < _rating;
      return GestureDetector(
        onTap: () {
          setState(() => _rating = i + 1);
          widget.onRatingChanged(i + 1);
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: Icon(
            filled ? Icons.star_rounded : Icons.star_border_rounded,
            key: ValueKey(filled),
            color: filled ? const Color(0xFFFFD700) : Colors.white24,
            size: widget.size,
          ),
        ),
      );
    }));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// R2 — Add Review Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────
class AddReviewSheet extends StatefulWidget {
  final String contentId;
  final String title;
  final Color accentColor;
  final ValueChanged<ContentReview> onSave;

  const AddReviewSheet({
    super.key,
    required this.contentId,
    required this.title,
    required this.accentColor,
    required this.onSave,
  });

  static void show(BuildContext context, {
    required String contentId,
    required String title,
    required Color accentColor,
    required ValueChanged<ContentReview> onSave,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddReviewSheet(
          contentId: contentId, title: title,
          accentColor: accentColor, onSave: onSave),
    );
  }

  @override
  State<AddReviewSheet> createState() => _AddReviewSheetState();
}

class _AddReviewSheetState extends State<AddReviewSheet> {
  int _rating = 0;
  bool _spoiler = false;
  final _ctrl = TextEditingController();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.all(24),
        child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('Rate ${widget.title}', style: const TextStyle(color: Colors.white,
              fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          StarRatingBar(
            initialRating: _rating, accentColor: widget.accentColor,
            onRatingChanged: (r) => setState(() => _rating = r)),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            maxLines: 3,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Write a review (optional)…',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withOpacity(0.07),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Checkbox(
              value: _spoiler, activeColor: widget.accentColor,
              onChanged: (v) => setState(() => _spoiler = v ?? false)),
            const Text('Contains spoilers',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
          ]),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              onPressed: _rating > 0 ? () {
                final r = ContentReview(
                  contentId: widget.contentId, rating: _rating,
                  review: _ctrl.text.trim(),
                  createdAt: DateTime.now(), containsSpoiler: _spoiler);
                widget.onSave(r);
                Navigator.of(context).pop();
              } : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.accentColor,
                disabledBackgroundColor: Colors.white12,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14)),
              child: Text(_rating > 0 ? 'Submit Review' : 'Select a rating first',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            )),
        ])),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// R4 — Spoiler-Protected Comment
// ─────────────────────────────────────────────────────────────────────────────
class SpoilerText extends StatefulWidget {
  final String text;
  const SpoilerText({super.key, required this.text});

  @override
  State<SpoilerText> createState() => _SpoilerTextState();
}

class _SpoilerTextState extends State<SpoilerText> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _revealed = true),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _revealed ? Colors.transparent : Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(4)),
        child: Text(
          _revealed ? widget.text : '⚠ Spoiler — tap to reveal',
          style: TextStyle(
            color: _revealed ? Colors.white : Colors.black,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
