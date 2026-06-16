import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SceneBookmark {
  final int? id;
  final String contentId;
  final String? episodeId;
  final int positionMs;
  final String emoji;
  final String? note;
  final DateTime createdAt;

  const SceneBookmark({
    this.id,
    required this.contentId,
    this.episodeId,
    required this.positionMs,
    required this.emoji,
    this.note,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'content_id':  contentId,
    'episode_id':  episodeId,
    'position_ms': positionMs,
    'emoji':       emoji,
    if (note != null) 'note': note,
    'created_at':  createdAt.millisecondsSinceEpoch,
  };

  factory SceneBookmark.fromMap(Map<String, dynamic> m) {
    int _i(dynamic v) => v is int ? v : (v as num).toInt();
    return SceneBookmark(
      id:          _i(m['id']),
      contentId:   m['content_id'] as String,
      episodeId:   m['episode_id'] as String?,
      positionMs:  _i(m['position_ms']),
      emoji:       m['emoji'] as String,
      note:        m['note'] as String?,
      createdAt:   DateTime.fromMillisecondsSinceEpoch(_i(m['created_at'])),
    );
  }
}

class SceneBookmarkStore {
  static Database? _db;

  static Future<Database> get _instance async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      p.join(dir.path, 'scene_bookmarks.db'),
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE scene_bookmarks (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          content_id TEXT    NOT NULL,
          episode_id TEXT,
          position_ms INTEGER NOT NULL,
          emoji      TEXT    NOT NULL,
          created_at INTEGER NOT NULL
        )
      '''),
    );
    return _db!;
  }

  static Future<void> add(SceneBookmark bm) async {
    final db = await _instance;
    await db.insert('scene_bookmarks', bm.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<SceneBookmark>> getAll({
    required String contentId,
    String? episodeId,
  }) async {
    final db = await _instance;
    final rows = await db.query(
      'scene_bookmarks',
      where:     episodeId != null
          ? 'content_id = ? AND episode_id = ?'
          : 'content_id = ? AND episode_id IS NULL',
      whereArgs: episodeId != null ? [contentId, episodeId] : [contentId],
      orderBy:   'position_ms ASC',
    );
    return rows.map(SceneBookmark.fromMap).toList();
  }

  static Future<void> delete(int id) async {
    final db = await _instance;
    await db.delete('scene_bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteAll({
    required String contentId,
    String? episodeId,
  }) async {
    final db = await _instance;
    await db.delete(
      'scene_bookmarks',
      where:     episodeId != null
          ? 'content_id = ? AND episode_id = ?'
          : 'content_id = ? AND episode_id IS NULL',
      whereArgs: episodeId != null ? [contentId, episodeId] : [contentId],
    );
  }

  /// Delete ALL bookmarks across all content — used on logout to clear user data.
  static Future<void> deleteAllContent() async {
    final db = await _instance;
    await db.delete('scene_bookmarks');
  }
}
