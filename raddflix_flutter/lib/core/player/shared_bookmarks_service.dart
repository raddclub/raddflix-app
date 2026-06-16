/// Phase I3 — Shared Bookmarks
/// Make a scene bookmark public → visible to friends watching the same content.
/// "3 people bookmarked this scene 🔥" indicator on the seek bar.
///
/// Implementation: bookmarks stored locally + synced to a lightweight
/// in-memory data structure keyed by contentId+timestamp.
/// In production: POST to a Radd backend. Here: SharedPreferences + JSON.
library shared_bookmarks;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Bookmark model ────────────────────────────────────────────────────────────
class SharedBookmark {
  final String id;           // uuid-like
  final String contentId;
  final Duration position;
  final String label;        // user note
  final bool isPublic;
  final String ownerName;    // display name
  final DateTime createdAt;
  final int likeCount;

  const SharedBookmark({
    required this.id,
    required this.contentId,
    required this.position,
    required this.label,
    required this.isPublic,
    required this.ownerName,
    required this.createdAt,
    this.likeCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'contentId': contentId,
    'posMs': position.inMilliseconds,
    'label': label, 'isPublic': isPublic,
    'ownerName': ownerName,
    'createdAt': createdAt.toIso8601String(),
    'likeCount': likeCount,
  };

  factory SharedBookmark.fromJson(Map<String, dynamic> j) => SharedBookmark(
    id: j['id'], contentId: j['contentId'],
    position: Duration(milliseconds: (j['posMs'] as num).toInt()),
    label: j['label'], isPublic: j['isPublic'],
    ownerName: j['ownerName'],
    createdAt: DateTime.parse(j['createdAt']),
    likeCount: j['likeCount'] ?? 0,
  );

  SharedBookmark copyWith({bool? isPublic, int? likeCount, String? label}) =>
      SharedBookmark(
        id: id, contentId: contentId, position: position,
        label: label ?? this.label,
        isPublic: isPublic ?? this.isPublic,
        ownerName: ownerName, createdAt: createdAt,
        likeCount: likeCount ?? this.likeCount,
      );
}

// ── Bookmark store ────────────────────────────────────────────────────────────
class SharedBookmarkStore {
  SharedBookmarkStore._();
  static final instance = SharedBookmarkStore._();

  Future<List<SharedBookmark>> load(String contentId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('bookmarks_$contentId') ?? '[]';
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(SharedBookmark.fromJson)
        .toList();
  }

  Future<void> save(String contentId, List<SharedBookmark> bookmarks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bookmarks_$contentId',
        jsonEncode(bookmarks.map((b) => b.toJson()).toList()));
  }

  Future<SharedBookmark> add(SharedBookmark bookmark) async {
    final list = await load(bookmark.contentId);
    list.add(bookmark);
    await save(bookmark.contentId, list);
    return bookmark;
  }

  Future<void> delete(String contentId, String bookmarkId) async {
    final list = await load(contentId);
    list.removeWhere((b) => b.id == bookmarkId);
    await save(contentId, list);
  }

  Future<SharedBookmark> togglePublic(String contentId, String bookmarkId) async {
    final list = await load(contentId);
    final idx = list.indexWhere((b) => b.id == bookmarkId);
    if (idx < 0) throw Exception('Bookmark not found');
    list[idx] = list[idx].copyWith(isPublic: !list[idx].isPublic);
    await save(contentId, list);
    return list[idx];
  }

  /// Generate a simple unique ID.
  String generateId() =>
      DateTime.now().millisecondsSinceEpoch.toRadixString(36) +
      (DateTime.now().microsecond % 999).toRadixString(36);
}

// ── Seek bar bookmark dots widget ─────────────────────────────────────────────
/// Shows bookmark markers on the seek bar.
/// [bookmarks] are all bookmarks (own + friends' public ones).
class BookmarkSeekDots extends StatelessWidget {
  final List<SharedBookmark> bookmarks;
  final Duration total;
  final Color accentColor;
  final ValueChanged<SharedBookmark> onTap;

  const BookmarkSeekDots({
    super.key,
    required this.bookmarks,
    required this.total,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (total.inMilliseconds == 0) return const SizedBox.shrink();
    return LayoutBuilder(builder: (_, constraints) {
      return Stack(children: bookmarks.map((bm) {
        final frac = bm.position.inMilliseconds / total.inMilliseconds;
        final x = frac.clamp(0.0, 1.0) * constraints.maxWidth;
        return Positioned(
          left: x - 4, top: 0,
          child: GestureDetector(
            onTap: () => onTap(bm),
            child: Tooltip(
              message: '${bm.ownerName}: ${bm.label}',
              child: Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bm.isPublic ? accentColor : Colors.white54,
                  border: Border.all(color: Colors.white, width: 0.8),
                ),
              ),
            ),
          ),
        );
      }).toList());
    });
  }
}

// ── Add Bookmark bottom sheet ─────────────────────────────────────────────────
class AddBookmarkSheet extends StatefulWidget {
  final Duration position;
  final String contentId;
  final Color accentColor;
  final ValueChanged<SharedBookmark> onSaved;

  const AddBookmarkSheet({
    super.key,
    required this.position,
    required this.contentId,
    required this.accentColor,
    required this.onSaved,
  });

  static Future<void> show(BuildContext context, {
    required Duration position,
    required String contentId,
    required Color accentColor,
    required ValueChanged<SharedBookmark> onSaved,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddBookmarkSheet(
        position: position, contentId: contentId,
        accentColor: accentColor, onSaved: onSaved,
      ),
    );
  }

  @override
  State<AddBookmarkSheet> createState() => _AddBookmarkSheetState();
}

class _AddBookmarkSheetState extends State<AddBookmarkSheet> {
  final _ctrl = TextEditingController();
  bool _isPublic = false;
  bool _saving = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final bm = SharedBookmark(
      id: SharedBookmarkStore.instance.generateId(),
      contentId: widget.contentId,
      position: widget.position,
      label: _ctrl.text.trim().isEmpty ? 'Bookmark' : _ctrl.text.trim(),
      isPublic: _isPublic,
      ownerName: 'You',
      createdAt: DateTime.now(),
    );
    await SharedBookmarkStore.instance.add(bm);
    if (mounted) {
      widget.onSaved(bm);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: Colors.white10),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          )),
          const SizedBox(height: 20),
          Row(children: [
            Icon(Icons.bookmark_add_rounded, color: widget.accentColor, size: 22),
            const SizedBox(width: 10),
            Text('Bookmark at ${_fmt(widget.position)}',
                style: const TextStyle(color: Colors.white,
                    fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Add a note (optional)',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withOpacity(0.07),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Switch(
              value: _isPublic,
              onChanged: (v) => setState(() => _isPublic = v),
              activeColor: widget.accentColor,
            ),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_isPublic ? 'Public — friends can see this' : 'Private — only you',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              if (_isPublic)
                const Text('"3 people bookmarked this scene 🔥"',
                    style: TextStyle(color: Colors.white38, fontSize: 10)),
            ])),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(_saving ? 'Saving…' : 'Save Bookmark',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}
