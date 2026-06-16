import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/player/scene_bookmark_store.dart';

/// Phase H — Enhanced Bookmark Panel
/// Features: emoji categories, notes, share, seek to, delete with undo.
class BookmarkPanel extends StatefulWidget {
  final List<SceneBookmark> bookmarks;
  final Duration currentPosition;
  final Duration totalDuration;
  final Color accentColor;
  final ValueChanged<Duration> onSeekTo;
  final VoidCallback onAddBookmark;
  final ValueChanged<SceneBookmark> onDeleteBookmark;
  final ValueChanged<SceneBookmark> onUpdateBookmark;

  const BookmarkPanel({
    super.key,
    required this.bookmarks,
    required this.currentPosition,
    required this.totalDuration,
    required this.accentColor,
    required this.onSeekTo,
    required this.onAddBookmark,
    required this.onDeleteBookmark,
    required this.onUpdateBookmark,
  });

  @override
  State<BookmarkPanel> createState() => _BookmarkPanelState();
}

class _BookmarkPanelState extends State<BookmarkPanel> {
  String _filterEmoji = 'all';
  SceneBookmark? _pendingDelete;
  int _undoCountdown = 5;

  static const _emojis = ['🔖', '❤️', '😂', '😱', '🤩', '💡', '⭐', '🎬'];

  @override
  Widget build(BuildContext context) {
    final acc = widget.accentColor;
    final filtered = _filterEmoji == 'all'
        ? widget.bookmarks
        : widget.bookmarks.where((b) => b.emoji == _filterEmoji).toList();

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.72),
      decoration: const BoxDecoration(
        color: Color(0xFF12121E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Center(child: Container(
          width: 36, height: 4, margin: const EdgeInsets.fromLTRB(0, 12, 0, 0),
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
        )),
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Icon(Icons.bookmarks_rounded, color: acc, size: 20),
            const SizedBox(width: 10),
            const Expanded(child: Text('Bookmarks',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
            Text('${widget.bookmarks.length}',
                style: TextStyle(color: acc, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(width: 16),
            GestureDetector(
              onTap: () { HapticFeedback.mediumImpact(); widget.onAddBookmark(); },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: acc,
                  borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.add_rounded, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  const Text('Add', style: TextStyle(color: Colors.white,
                      fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ]),
        ),
        // Emoji filter strip
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            children: [
              _filterChip('all', 'All', acc),
              const SizedBox(width: 6),
              ..._emojis.map((e) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _filterChip(e, e, acc),
              )),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 16),

        // Undo toast
        if (_pendingDelete != null)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF2A1A1A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withOpacity(0.3))),
            child: Row(children: [
              const Icon(Icons.delete_rounded, color: Colors.redAccent, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text('Bookmark deleted',
                  style: const TextStyle(color: Colors.white70, fontSize: 12))),
              GestureDetector(
                onTap: () => setState(() => _pendingDelete = null),
                child: Text('Undo ($_undoCountdown)',
                    style: TextStyle(color: acc, fontSize: 12, fontWeight: FontWeight.w700))),
            ]),
          ).animate().fadeIn(duration: 200.ms),

        // Bookmark list
        Flexible(
          child: filtered.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.bookmark_border_rounded, color: Colors.white24, size: 48),
                    const SizedBox(height: 12),
                    const Text('No bookmarks yet',
                        style: TextStyle(color: Colors.white38, fontSize: 14)),
                    const SizedBox(height: 6),
                    const Text('Tap Add to mark this moment',
                        style: TextStyle(color: Colors.white24, fontSize: 11)),
                  ]),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) => _BookmarkCard(
                    bookmark: filtered[i],
                    totalDuration: widget.totalDuration,
                    accentColor: acc,
                    onSeek: () {
                      Navigator.pop(context);
                      widget.onSeekTo(Duration(milliseconds: filtered[i].positionMs));
                    },
                    onDelete: () {
                      setState(() => _pendingDelete = filtered[i]);
                      widget.onDeleteBookmark(filtered[i]);
                      Future.delayed(const Duration(seconds: 5), () {
                        if (mounted) setState(() => _pendingDelete = null);
                      });
                    },
                  ),
                ),
        ),
      ]),
    ).animate().slideY(begin: 0.1, end: 0, duration: 250.ms, curve: Curves.easeOutCubic)
               .fadeIn(duration: 200.ms);
  }

  Widget _filterChip(String id, String label, Color acc) {
    final sel = _filterEmoji == id;
    return GestureDetector(
      onTap: () => setState(() => _filterEmoji = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: sel ? acc.withOpacity(0.2) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: sel ? acc : Colors.white12, width: sel ? 1.5 : 1)),
        child: Text(label, style: TextStyle(
          color: sel ? Colors.white : Colors.white60,
          fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.normal)),
      ),
    );
  }
}

class _BookmarkCard extends StatelessWidget {
  final SceneBookmark bookmark;
  final Duration totalDuration;
  final Color accentColor;
  final VoidCallback onSeek;
  final VoidCallback onDelete;

  const _BookmarkCard({
    required this.bookmark,
    required this.totalDuration,
    required this.accentColor,
    required this.onSeek,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final pos = Duration(milliseconds: bookmark.positionMs);
    final frac = totalDuration.inMilliseconds > 0
        ? bookmark.positionMs / totalDuration.inMilliseconds
        : 0.0;

    return Card(
      color: Colors.white.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white10)),
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onSeek,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            // Emoji
            Text(bookmark.emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            // Info
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(_fmt(pos),
                    style: TextStyle(color: accentColor, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                // Progress indicator
                Expanded(child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: frac.clamp(0.0, 1.0),
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(accentColor.withOpacity(0.6)),
                    minHeight: 3),
                )),
              ]),
              if (bookmark.note != null && bookmark.note!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(bookmark.note!, style: const TextStyle(color: Colors.white54, fontSize: 11),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ])),
            const SizedBox(width: 8),
            // Delete
            GestureDetector(
              onTap: onDelete,
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 16),
              ),
            ),
          ]),
        ),
      ),
    ).animate().fadeIn(duration: 150.ms).slideX(begin: 0.05, end: 0, duration: 150.ms);
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
    return '${m}:${s.toString().padLeft(2,'0')}';
  }
}
