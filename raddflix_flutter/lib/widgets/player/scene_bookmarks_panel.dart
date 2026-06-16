import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants.dart';
import '../../core/player/scene_bookmark_store.dart';

const _kEmojis = ['❤️', '🔥', '😂', '😮', '💔', '📌', '⭐', '🎯'];

class SceneBookmarksPanel extends StatelessWidget {
  final List<SceneBookmark> bookmarks;
  final String Function(Duration) fmtDur;
  final ValueChanged<Duration> onSeekTo;
  final ValueChanged<int> onDelete;
  final VoidCallback onClose;

  const SceneBookmarksPanel({
    super.key,
    required this.bookmarks,
    required this.fmtDur,
    required this.onSeekTo,
    required this.onDelete,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F1A),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
          child: Row(children: [
            const Icon(Icons.bookmark_rounded, color: Color(0xFFE8002D), size: 18),
            const SizedBox(width: 8),
            Text('Scene Bookmarks (${bookmarks.length})',
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            GestureDetector(
              onTap: onClose,
              child: const Icon(Icons.close_rounded, color: Colors.white54, size: 20)),
          ]),
        ),
        const Divider(color: Colors.white12, height: 1),

        if (bookmarks.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Column(children: [
              Icon(Icons.bookmark_border_rounded, color: Colors.white24, size: 40),
              SizedBox(height: 12),
              Text('No bookmarks yet', style: TextStyle(color: Colors.white38, fontSize: 13)),
              SizedBox(height: 4),
              Text('Long-press the seek bar to add one',
                  style: TextStyle(color: Colors.white24, fontSize: 11)),
            ]),
          )
        else
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: bookmarks.length,
              itemBuilder: (ctx, i) {
                final bm = bookmarks[i];
                return Dismissible(
                  key: Key(bm.id.toString()),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red.withOpacity(0.3),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete_rounded, color: Colors.red, size: 20)),
                  onDismissed: (_) => onDelete(bm.id!),
                  child: ListTile(
                    dense: true,
                    leading: Text(bm.emoji, style: const TextStyle(fontSize: 20)),
                    title: Text(fmtDur(Duration(milliseconds: bm.positionMs)),
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text('Tap to jump • Swipe left to delete',
                        style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onSeekTo(Duration(milliseconds: bm.positionMs));
                      onClose();
                    },
                    onLongPress: () {
                      HapticFeedback.mediumImpact();
                      onDelete(bm.id!);
                    },
                  ),
                );
              },
            ),
          ),
      ]),
    ).animate().slideY(begin: 1, end: 0, duration: 220.ms, curve: AppCurves.standard);
  }
}

/// Emoji picker bottom sheet for saving a scene bookmark.
Future<String?> showBookmarkEmojiPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF0F0F1A),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Add Scene Bookmark', style: TextStyle(
            color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12, runSpacing: 12,
          children: _kEmojis.map((e) => GestureDetector(
            onTap: () => Navigator.pop(context, e),
            child: Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12)),
              child: Center(child: Text(e, style: const TextStyle(fontSize: 24))),
            ),
          )).toList(),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
      ]),
    ),
  );
}
