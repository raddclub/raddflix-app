import 'dart:convert';
import 'dart:io';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../models/catalog_item.dart';
import '../constants.dart';
import '../security/keystore.dart';
import '../security/device_id.dart';
import '../security/request_encoder.dart';

/// Shared local SQLite database — encrypted with SQLCipher (AES-256).
///
/// The encryption key is generated on first install and stored in Android
/// Keystore via flutter_secure_storage. The DB file is opaque to anyone
/// without the key, protecting JazzDrive share_url values at rest.
///
/// Tables:
/// - titles        — full catalog (poster_url, share_url, poster_path, …)
/// - episodes      — TV episodes with per-episode share_url
/// - stream_cache  — 6h TTL JazzDrive CDN link cache
/// - watch_positions — resume position per file
/// - downloads     — offline download metadata
/// - sync_meta     — last sync version / timestamp
class LocalDb {
  static Database? _db;

  static Future<Database> get instance async {
    _db ??= await _openDb();
    return _db!;
  }

  static Future<Database> _openDb() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, AppConstants.catalogDbName);

    // Task 4.2 + 4.3: retrieve (or generate) the device-bound AES key from
    // Android Keystore, then open SQLCipher-encrypted database.
    final dbKey = await Keystore.getOrCreateDbKey();

    try {
      return await openDatabase(
        path,
        version: AppConstants.catalogDbVersion,
        password: dbKey,
        onCreate: _createAll,
        onUpgrade: _migrate,
      );
    } catch (_) {
      // Pre-launch migration path: if an unencrypted DB file already exists
      // (plain sqflite from development), SQLCipher rejects it with
      // "file is not a database". Delete it and start fresh encrypted.
      // After public launch this branch is unreachable (all installs start encrypted).
      try { await File(path).delete(); } catch (_) {}
      return openDatabase(
        path,
        version: AppConstants.catalogDbVersion,
        password: dbKey,
        onCreate: _createAll,
        onUpgrade: _migrate,
      );
    }
  }

  static Future<void> _createAll(Database db, int version) async {
    await db.execute('''
      CREATE TABLE titles (
        id          INTEGER PRIMARY KEY,
        title       TEXT NOT NULL,
        year        INTEGER,
        media_type  TEXT NOT NULL,
        description TEXT,
        rating      REAL,
        genres      TEXT,
        poster_url  TEXT,
        poster_path TEXT,
        share_url   TEXT,
        file_id     TEXT,
        is_free     INTEGER DEFAULT 0,
        db_version  INTEGER DEFAULT 0,
        language    TEXT,
        status      TEXT,
        is_ongoing  INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE episodes (
        id        INTEGER PRIMARY KEY,
        title_id  INTEGER NOT NULL,
        file_id   TEXT,
        season    INTEGER,
        episode   INTEGER,
        label     TEXT,
        quality   TEXT,
        is_free   INTEGER DEFAULT 0,
        share_url TEXT,
        filename  TEXT,
        FOREIGN KEY (title_id) REFERENCES titles(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE sync_meta (
        key   TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE watch_positions (
        file_id     TEXT PRIMARY KEY,
        position_ms INTEGER DEFAULT 0,
        duration_ms INTEGER DEFAULT 0,
        updated_at  INTEGER DEFAULT 0,
        synced      INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE downloads (
        file_id       TEXT PRIMARY KEY,
        title_text    TEXT,
        poster_url    TEXT,
        local_path    TEXT,
        status        TEXT DEFAULT 'pending',
        progress      REAL DEFAULT 0.0,
        file_size     INTEGER DEFAULT 0,
        downloaded_at INTEGER DEFAULT 0,
        content_type  TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE stream_cache (
        file_id    TEXT PRIMARY KEY,
        stream_url TEXT NOT NULL,
        poster_url TEXT,
        created_at INTEGER DEFAULT 0,
        expires_at INTEGER DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX idx_titles_type ON titles(media_type)');
    await db.execute('CREATE INDEX idx_episodes_title ON episodes(title_id)');
    // Phase: new-episode badge tracking
    await db.execute('''
      CREATE TABLE IF NOT EXISTS show_ep_seen (
        show_id    INTEGER PRIMARY KEY,
        seen_count INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX idx_stream_cache_expires ON stream_cache(expires_at)');
    // Phase 6 — usage tracking
    await db.execute('''
      CREATE TABLE IF NOT EXISTS usage_log (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        bytes       INTEGER NOT NULL DEFAULT 0,
        flushed     INTEGER NOT NULL DEFAULT 0,
        created_at  INTEGER NOT NULL DEFAULT 0
      )
    ''');
    // Phase 6 — quota cache (last known server quota)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS quota_cache (
        k TEXT PRIMARY KEY,
        v TEXT
      )
    ''');
    // Phase 9 — SIMOSA streak tracker
    await db.execute('''
      CREATE TABLE IF NOT EXISTS simosa_streak (
        id         INTEGER PRIMARY KEY,
        streak     INTEGER NOT NULL DEFAULT 0,
        last_claim TEXT
      )
    ''');
    // Watchlist — user-saved titles
    await db.execute('''
      CREATE TABLE IF NOT EXISTS watchlist (
        id          INTEGER PRIMARY KEY,
        title       TEXT NOT NULL,
        year        INTEGER,
        media_type  TEXT NOT NULL,
        poster_url  TEXT,
        poster_path TEXT,
        share_url   TEXT,
        added_at    INTEGER DEFAULT 0
      )
    ''');
        // Phase 12 — Full-text search (FTS5) for title + description
    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS catalog_fts
      USING fts5(title, description, content='titles', content_rowid='id')
    ''');
    // Populate FTS index from existing titles data
    await db.execute("INSERT INTO catalog_fts(catalog_fts) VALUES('rebuild')");
  }

  static Future<void> _migrate(Database db, int oldV, int newV) async {
    if (oldV < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS watch_positions (
          file_id     TEXT PRIMARY KEY,
          position_ms INTEGER DEFAULT 0,
          duration_ms INTEGER DEFAULT 0,
          updated_at  INTEGER DEFAULT 0
        )
      ''');
    }
    if (oldV < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS downloads (
          file_id       TEXT PRIMARY KEY,
          title_text    TEXT,
          poster_url    TEXT,
          local_path    TEXT,
          status        TEXT DEFAULT 'pending',
          progress      REAL DEFAULT 0.0,
          file_size     INTEGER DEFAULT 0,
          downloaded_at INTEGER DEFAULT 0
        )
      ''');
    }
    if (oldV < 4) {
      for (final col in ['language TEXT', 'status TEXT', 'is_ongoing INTEGER DEFAULT 0']) {
        try { await db.execute('ALTER TABLE titles ADD COLUMN $col'); } catch (_) {}
      }
    }
    if (oldV < 8) {
      try { await db.execute('ALTER TABLE downloads ADD COLUMN content_type TEXT'); } catch (_) {}
    }
    if (oldV < 9) {
      try {
        await db.execute("UPDATE titles SET media_type = 'show' WHERE media_type IN ('series', 'tv')");
      } catch (_) {}
      try { await db.delete('sync_meta'); } catch (_) {}
    }
    if (oldV < 10) {
      // Add share_url to titles (for movie-level files)
      try { await db.execute('ALTER TABLE titles ADD COLUMN share_url TEXT'); } catch (_) {}
      // Add share_url to episodes
      try { await db.execute('ALTER TABLE episodes ADD COLUMN share_url TEXT'); } catch (_) {}
      // Add local poster path to titles
      try { await db.execute('ALTER TABLE titles ADD COLUMN poster_path TEXT'); } catch (_) {}
    }
    if (oldV < 11) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS usage_log (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            bytes      INTEGER NOT NULL DEFAULT 0,
            flushed    INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL DEFAULT 0
          )
        ''');
      } catch (_) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS quota_cache (
            k TEXT PRIMARY KEY,
            v TEXT
          )
        ''');
      } catch (_) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS simosa_streak (
            id         INTEGER PRIMARY KEY,
            streak     INTEGER NOT NULL DEFAULT 0,
            last_claim TEXT
          )
        ''');
      } catch (_) {}
    }
    if (oldV < 12) {
      // New-episode badge tracking table
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS show_ep_seen (
            show_id    INTEGER PRIMARY KEY,
            seen_count INTEGER NOT NULL DEFAULT 0
          )
        ''');
      } catch (_) {}
      // Stream link cache table (6h TTL, shared for watch + download)
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS stream_cache (
            file_id    TEXT PRIMARY KEY,
            stream_url TEXT NOT NULL,
            poster_url TEXT,
            created_at INTEGER DEFAULT 0,
            expires_at INTEGER DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_stream_cache_expires ON stream_cache(expires_at)',
        );
      } catch (_) {}
    }
    if (oldV < 13) {
      // Phase 12 — FTS5 full-text search table
      try {
        await db.execute('''
          CREATE VIRTUAL TABLE IF NOT EXISTS catalog_fts
          USING fts5(title, description, content='titles', content_rowid='id')
        ''');
        // Rebuild the FTS index from all existing titles rows
        await db.execute("INSERT INTO catalog_fts(catalog_fts) VALUES('rebuild')");
      } catch (_) {}
    }
    if (oldV < 14) {
      // Watchlist table
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS watchlist (
            id          INTEGER PRIMARY KEY,
            title       TEXT NOT NULL,
            year        INTEGER,
            media_type  TEXT NOT NULL,
            poster_url  TEXT,
            poster_path TEXT,
            share_url   TEXT,
            added_at    INTEGER DEFAULT 0
          )
        ''');
      } catch (_) {}
    }
    if (oldV < 15) {
      // Offline-first history sync queue: track which positions have been pushed to server
      try { await db.execute('ALTER TABLE watch_positions ADD COLUMN synced INTEGER DEFAULT 0'); } catch (_) {}
    }
    if (oldV < 16) {
      // BUG-A36: Add file_id column to titles so getShareUrl() can find movies by file_id
      try { await db.execute('ALTER TABLE titles ADD COLUMN file_id TEXT'); } catch (_) {}
    }
    if (oldV < 17) {
      // Add filename to episodes so JazzDriveService can pick the right file in folder shares
      try { await db.execute('ALTER TABLE episodes ADD COLUMN filename TEXT'); } catch (_) {}
      // BUG-F08 fix: add JazzDrive share URL columns to titles
      try { await db.execute('ALTER TABLE titles ADD COLUMN poster_share_url TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE titles ADD COLUMN folder_share_url TEXT'); } catch (_) {}
      // Signal to startup that a full catalog re-sync is needed to populate the new column
      try {
        await db.insert('sync_meta', {'key': 'force_resync', 'value': '1'},
            conflictAlgorithm: ConflictAlgorithm.replace);
      } catch (_) {}
    }
  }

  // ── Titles ────────────────────────────────────────────────────────────────

  static Future<List<CatalogItem>> getMovies() async {
    final db = await instance;
    final rows = await db.query('titles',
        where: 'media_type = ?', whereArgs: ['movie'], orderBy: 'title ASC');
    return rows.map(_rowToItem).toList();
  }

  static Future<List<CatalogItem>> getShows() async {
    final db = await instance;
    final rows = await db.query('titles',
        where: 'media_type = ?', whereArgs: ['show'], orderBy: 'title ASC');
    return rows.map(_rowToItem).toList();
  }

  static Future<List<CatalogItem>> searchTitles(String query) async {
    final db = await instance;
    // Build FTS5 prefix query: "word1*" "word2*" — matches partial words and handles
    // Urdu/Roman transliterations better than LIKE (e.g. "khuda" finds "khuda hafiz")
    final terms = query.trim().split(RegExp(r'\s+'));
    final ftsQuery = terms.map((w) => '"${w.replaceAll('"', '')}"*').join(' ');
    try {
      final rows = await db.rawQuery('''
        SELECT t.* FROM titles t
        INNER JOIN catalog_fts fts ON t.id = fts.rowid
        WHERE catalog_fts MATCH ?
        ORDER BY rank, t.title ASC
        LIMIT 50
      ''', [ftsQuery]);
      if (rows.isNotEmpty) return rows.map(_rowToItem).toList();
    } catch (_) {}
    // Fallback: plain LIKE (used on first install before FTS index is populated)
    final rows = await db.query('titles',
        where: 'title LIKE ?',
        whereArgs: ['%$query%'],
        orderBy: 'title ASC',
        limit: 50);
    return rows.map(_rowToItem).toList();
  }

  /// Rebuild the FTS5 catalog index from the current titles table.
  /// Call after a bulk sync so search reflects new/updated titles immediately.
  static Future<void> rebuildFtsIndex() async {
    final db = await instance;
    try {
      await db.execute("INSERT INTO catalog_fts(catalog_fts) VALUES('rebuild')");
    } catch (_) {}
  }

  static Future<void> upsertTitle(CatalogItem item) async {
    final db = await instance;
    await db.insert(
      'titles',
      {
        'id':         item.id,
        'title':      item.title,
        'year':       item.year,
        'media_type': item.mediaType,
        'description': item.description,
        'rating':     item.rating,
        'genres':     item.genres,
        'poster_url': item.posterUrl,
        'share_url':  await _encodeUrl(item.shareUrl ?? ''),
        'file_id':    item.fileId,
        'is_free':    item.isFree ? 1 : 0,
        'db_version': item.dbVersion,
        'language':   item.language,
        'status':     item.status,
        'is_ongoing': (item.isOngoing ?? false) ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Merge a metadata-only delta title into the local catalog.
  ///
  /// Unlike [upsertTitle] which uses ConflictAlgorithm.replace (overwriting
  /// share_url / poster_path), this does a targeted UPDATE on conflict —
  /// preserving streaming credentials written by a prior Oracle sync.
  ///
  /// Safe to call with JazzDrive delta entries that intentionally carry
  /// NO share_url and NO file_id.
  /// Merge a delta title into local DB.
  /// Uses SELECT then UPDATE or INSERT instead of UPSERT syntax,
  /// which requires SQLite 3.24+ and crashes Android 8 (BUG-A04).
  /// Merge a delta title into local DB.
  ///
  /// delta_v2 carries full playback data: file_id, share_url, folder_share_url.
  /// On UPDATE: only overwrites share_url if the incoming value is non-empty,
  /// preserving any share_url written by a prior Oracle sync.
  /// Uses SELECT then UPDATE/INSERT — avoids ON CONFLICT DO UPDATE which requires
  /// SQLite 3.24+ and crashes Android 8 (BUG-A04).
  static Future<void> mergeDeltaTitle(Map<String, dynamic> row) async {
    final db = await instance;
    final id = row['id'] as int?;
    if (id == null) return;
    final title          = row['title']            as String? ?? '';
    final year           = row['year'];
    final mediaType      = row['media_type']        as String? ?? 'movie';
    final desc           = row['description']       as String? ?? '';
    final rating         = (row['rating'] as num?)?.toDouble() ?? 0.0;
    final genres         = row['genres']            as String? ?? '[]';
    final posterUrl      = row['poster_url']        as String? ?? '';
    final posterShareUrl = row['poster_share_url']  as String? ?? '';
    final isFree         = (row['is_free'] == true || row['is_free'] == 1) ? 1 : 0;
    final dbVer          = row['db_version']        as int?    ?? 0;
    final language       = row['language']          as String? ?? '';
    final status         = row['status']            as String? ?? 'released';
    final isOngoing      = (row['is_ongoing'] == true || row['is_ongoing'] == 1) ? 1 : 0;
    final shareUrl       = row['share_url']         as String? ?? '';
    final folderShareUrl = row['folder_share_url']  as String? ?? '';
    final fileId         = row['file_id']           as String? ?? '';

    final existing = await db.query('titles',
        columns: ['id', 'poster_url', 'db_version', 'share_url'],
        where: 'id = ?',
        whereArgs: [id]);

    if (existing.isNotEmpty) {
      final oldPoster   = existing.first['poster_url'] as String? ?? '';
      final oldDbVer    = existing.first['db_version'] as int?    ?? 0;
      final oldShareUrl = existing.first['share_url']  as String? ?? '';
      await db.update('titles', {
        'title':            title,
        'year':             year,
        'media_type':       mediaType,
        'description':      desc,
        'rating':           rating,
        'genres':           genres,
        'poster_url':       posterUrl.isNotEmpty ? posterUrl : oldPoster,
        'is_free':          isFree,
        'db_version':       dbVer > oldDbVer ? dbVer : oldDbVer,
        'language':         language,
        'status':           status,
        'is_ongoing':       isOngoing,
        // Only overwrite share_url if delta has a value; preserve Oracle-synced URL otherwise
        'share_url':        shareUrl.isNotEmpty ? await _encodeUrl(shareUrl) : oldShareUrl,
        // AUDIT-05: write file_id when delta provides one; preserve existing if delta omits it
        if (fileId.isNotEmpty) 'file_id': fileId,
      }, where: 'id = ?', whereArgs: [id]);
    } else {
      await db.insert('titles', {
        'id':          id,
        'title':       title,
        'year':        year,
        'media_type':  mediaType,
        'description': desc,
        'rating':      rating,
        'genres':      genres,
        'poster_url':  posterUrl,
        'is_free':     isFree,
        'db_version':  dbVer,
        'language':    language,
        'status':      status,
        'is_ongoing':  isOngoing,
        'share_url':   await _encodeUrl(shareUrl),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // poster_share_url is stored in stream_cache table (no column in titles yet).
    // folder_share_url and fileId are used by the player at runtime via getShareUrl().
    // Future migration: add folder_share_url column to titles when needed.
  }

  /// Decode a share_url that may be RF1:xxx scrambled (as stored in SQLite).
  ///
  /// Use this whenever a CatalogItem.shareUrl read directly from the model
  /// (rather than via getShareUrl / getShareInfo) must be passed to an API.
  /// Returns the decoded URL, or the original if it is not scrambled, or
  /// null if [url] is null/empty.
  static Future<String?> decodeShareUrl(String? url) async {
    if (url == null || url.isEmpty) return null;
    return _decodeUrl(url);
  }

  /// Get the JazzDrive share_url for a file_id.
  /// Checks both episodes (for TV) and titles (for movies) tables.
  static Future<String?> getShareUrl(String fileId) async {
    final db = await instance;
    // Check episodes first
    final epRows = await db.query('episodes',
        where: 'file_id = ?', whereArgs: [fileId], limit: 1);
    if (epRows.isNotEmpty) {
      final url = epRows.first['share_url'] as String?;
      if (url != null && url.isNotEmpty) return await _decodeUrl(url);
    }
    // Check titles (for movie-level file_ids stored in titles table)
    final titleRows = await db.rawQuery(
      'SELECT share_url FROM titles WHERE file_id = ? LIMIT 1',
      [fileId],
    );
    if (titleRows.isNotEmpty) {
      final rawUrl = titleRows.first['share_url'] as String?;
      return rawUrl != null ? await _decodeUrl(rawUrl) : null;
    }
    return null;
  }

  /// Reads and clears the force_resync flag written by the v17 migration.
  /// Returns true exactly once — clears the flag so subsequent calls return false.
  /// Used by main.dart to trigger a background catalog re-sync after schema upgrade.
  static Future<bool> consumeForceResyncFlag() async {
    final db = await instance;
    final rows = await db.query('sync_meta',
        where: "key = 'force_resync'", limit: 1);
    if (rows.isNotEmpty && rows.first['value'] == '1') {
      await db.delete('sync_meta', where: "key = 'force_resync'");
      return true;
    }
    return false;
  }

  /// Get both share_url and filename for a file_id in one DB query.
  /// Used by player to pass the correct filename to JazzDriveService for folder shares.
  static Future<Map<String, String?>> getShareInfo(String fileId) async {
    final db = await instance;
    final epRows = await db.query('episodes',
        where: 'file_id = ?', whereArgs: [fileId], limit: 1);
    if (epRows.isNotEmpty) {
      final rawUrl  = epRows.first['share_url'] as String?;
      final filename = epRows.first['filename']  as String?;
      final url = (rawUrl != null && rawUrl.isNotEmpty) ? await _decodeUrl(rawUrl) : null;
      return {'share_url': url, 'filename': filename};
    }
    final titleRows = await db.rawQuery(
        'SELECT share_url FROM titles WHERE file_id = ? LIMIT 1', [fileId]);
    if (titleRows.isNotEmpty) {
      final rawUrl = titleRows.first['share_url'] as String?;
      return {'share_url': rawUrl != null ? await _decodeUrl(rawUrl) : null, 'filename': null};
    }
    return {'share_url': null, 'filename': null};
  }

  /// Save the local poster path for a title (after permanent download).
  static Future<void> savePosterPath(int titleId, String localPath) async {
    final db = await instance;
    await db.update(
      'titles',
      {'poster_path': localPath},
      where: 'id = ?',
      whereArgs: [titleId],
    );
  }

  // ── Episodes ──────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getEpisodes(int titleId) async {
    final db = await instance;
    return db.query('episodes',
        where: 'title_id = ?',
        whereArgs: [titleId],
        orderBy: 'season ASC, episode ASC');
  }

  static Future<void> upsertEpisode(Map<String, dynamic> ep) async {
    final db = await instance;
    final shareUrl = ep['share_url'] as String? ?? '';
    final epToInsert = Map<String, dynamic>.from(ep);
    if (shareUrl.isNotEmpty) {
      epToInsert['share_url'] = await _encodeUrl(shareUrl);
    }
    await db.insert('episodes', epToInsert,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }


  // ── URL Scrambling Helpers ────────────────────────────────────────────────

  /// Scramble a JazzDrive share_url before storing in SQLite.
  /// Uses RequestEncoder.scrambleUrl() with device ID as key.
  /// Returns original unchanged if empty or already has RF1: prefix.
  static Future<String> _encodeUrl(String url) async {
    if (url.isEmpty || url.startsWith('RF1:')) return url;
    final deviceId = await DeviceIdentifier.getDeviceId();
    return RequestEncoder.scrambleUrl(url, deviceId);
  }

  /// Decode a share_url that may be RF1:xxx scrambled (as stored in SQLite).
  /// Returns the decoded URL, or the original if not scrambled, or null if null/empty.
  static Future<String?> _decodeUrl(String? url) async {
    if (url == null || url.isEmpty) return url;
    if (!url.startsWith('RF1:')) return url;
    final deviceId = await DeviceIdentifier.getDeviceId();
    return RequestEncoder.unscrambleUrl(url, deviceId);
  }

  // ── Stream Cache ──────────────────────────────────────────────────────────

  /// Get a cached stream link for [fileId]. Returns null if not cached or expired.
  static Future<Map<String, dynamic>?> getStreamCache(String fileId) async {
    final db = await instance;
    final nowTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final rows = await db.query('stream_cache',
        where: 'file_id = ? AND expires_at > ?',
        whereArgs: [fileId, nowTs],
        limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// Get all non-expired stream cache entries (for loading into memory on start).
  static Future<List<Map<String, dynamic>>> getValidStreamCache() async {
    final db = await instance;
    final nowTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return db.query('stream_cache',
        where: 'expires_at > ?', whereArgs: [nowTs]);
  }

  /// Save a stream link to cache.
  static Future<void> saveStreamCache({
    required String fileId,
    required String streamUrl,
    String? posterUrl,
    required int expiresAt,
  }) async {
    final db = await instance;
    await db.insert(
      'stream_cache',
      {
        'file_id':    fileId,
        'stream_url': streamUrl,
        'poster_url': posterUrl,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'expires_at': expiresAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Delete a specific stream cache entry (force refresh on next play).
  static Future<void> deleteStreamCache(String fileId) async {
    final db = await instance;
    await db.delete('stream_cache', where: 'file_id = ?', whereArgs: [fileId]);
  }

  /// Remove all expired stream cache entries. Call once per day on app start.
  static Future<void> cleanExpiredStreamCache() async {
    final db = await instance;
    final nowTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final deleted = await db.delete('stream_cache',
        where: 'expires_at <= ?', whereArgs: [nowTs]);
    if (deleted > 0) {
      // ignore: avoid_print
      print('[LocalDb] Cleaned $deleted expired stream cache entries');
    }
  }


  /// Return up to [count] is_free=1 movie titles ordered by db_version DESC.
  ///
  /// Used by [JazzDriveService.warmTopFreeItems] to pre-warm the stream-link
  /// cache on startup. share_urls are decoded (unscrambled) before returning.
  static Future<List<Map<String, dynamic>>> getTopFreeMovies(int count) async {
    final db = await instance;
    final rows = await db.rawQuery(
      "SELECT id, file_id, share_url FROM titles "
      "WHERE is_free = 1 AND media_type = 'movie' "
      "  AND file_id IS NOT NULL AND file_id != '' "
      "  AND share_url IS NOT NULL AND share_url != '' "
      "ORDER BY db_version DESC LIMIT ?",
      [count],
    );
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      final rawUrl = row['share_url'] as String? ?? '';
      final decoded = rawUrl.isNotEmpty ? await _decodeUrl(rawUrl) : '';
      if (decoded.isEmpty) continue;
      result.add({
        'id':        row['id'],
        'file_id':   row['file_id'] as String? ?? '',
        'share_url': decoded,
      });
    }
    return result;
  }

  // ── Sync metadata ─────────────────────────────────────────────────────────

  static Future<int> getLastSyncVersion() async {
    final db = await instance;
    final rows = await db.query('sync_meta',
        where: 'key = ?', whereArgs: ['last_version']);
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first['value'] as String? ?? '0') ?? 0;
  }

  static Future<void> setLastSyncVersion(int version) async {
    final db = await instance;
    await db.insert('sync_meta',
        {'key': 'last_version', 'value': version.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<int> getLastSyncTimestamp() async {
    final db = await instance;
    final rows = await db.query('sync_meta',
        where: 'key = ?', whereArgs: ['last_sync_ts']);
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first['value'] as String? ?? '0') ?? 0;
  }

  static Future<void> setLastSyncTimestamp(int ts) async {
    final db = await instance;
    await db.insert('sync_meta',
        {'key': 'last_sync_ts', 'value': ts.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<int> getTotalCount() async {
    final db = await instance;
    final result = await db.rawQuery('SELECT COUNT(*) as c FROM titles');
    return (result.first['c'] as int?) ?? 0;
  }

  // ── Watch Positions ───────────────────────────────────────────────────────

  static Future<int> getSavedPosition(String fileId) async {
    final db = await instance;
    final rows = await db.query('watch_positions',
        where: 'file_id = ?', whereArgs: [fileId]);
    if (rows.isEmpty) return 0;
    return rows.first['position_ms'] as int? ?? 0;
  }

  static Future<void> savePosition(String fileId, int positionMs,
      {int durationMs = 0}) async {
    final db = await instance;
    await db.insert(
      'watch_positions',
      {
        'file_id':     fileId,
        'position_ms': positionMs,
        'duration_ms': durationMs,
        'updated_at':  DateTime.now().millisecondsSinceEpoch,
        'synced':      0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> clearPosition(String fileId) async {
    final db = await instance;
    await db.delete('watch_positions',
        where: 'file_id = ?', whereArgs: [fileId]);
  }

  /// BUG-A22: clearPosition(fileId) was never called from the UI.
  /// Added clearAllPositions() to support a 'Reset Watch Progress' action
  /// in profile_screen without needing a specific fileId.
  static Future<void> clearAllPositions() async {
    final db = await instance;
    await db.delete('watch_positions');
  }

  static Future<List<Map<String, dynamic>>> getWatchPositions() async {
    final db = await instance;
    return db.query('watch_positions',
        orderBy: 'updated_at DESC', limit: 20);
  }

  static Future<void> saveWatchPosition({
    required String fileId,
    required int positionMs,
    required int durationMs,
  }) async {
    await savePosition(fileId, positionMs, durationMs: durationMs);
  }

  /// Returns all watch positions not yet confirmed synced to the server.
  /// Called by HistoryApi.flushUnsynced() on startup and connectivity restore.
  static Future<List<Map<String, dynamic>>> getUnsyncedPositions() async {
    final db = await instance;
    return db.query('watch_positions',
        where: 'synced = 0 AND position_ms > 0',
        orderBy: 'updated_at DESC');
  }

  /// Mark a watch position as successfully confirmed on the server.
  static Future<void> markPositionSynced(String fileId) async {
    final db = await instance;
    await db.update(
      'watch_positions',
      {'synced': 1},
      where: 'file_id = ?',
      whereArgs: [fileId],
    );
  }

  /// Upsert a server-side history entry into local DB.
  /// Only overwrites local position if the server record is newer (watchedAt > updated_at).
  /// Marks synced=1 — came from server, no need to re-push.
  static Future<void> upsertServerPosition({
    required String fileId,
    required int positionMs,
    required int durationMs,
    required int watchedAtEpochSecs,
  }) async {
    final db = await instance;
    final serverTs = watchedAtEpochSecs * 1000; // epoch-sec → epoch-ms
    final existing = await db.query('watch_positions',
        where: 'file_id = ?', whereArgs: [fileId], limit: 1);
    if (existing.isNotEmpty) {
      final localTs = existing.first['updated_at'] as int? ?? 0;
      if (serverTs <= localTs) return; // local is newer — keep it
      await db.update('watch_positions', {
        'position_ms': positionMs,
        'duration_ms': durationMs,
        'updated_at':  serverTs,
        'synced':      1,
      }, where: 'file_id = ?', whereArgs: [fileId]);
    } else {
      await db.insert('watch_positions', {
        'file_id':     fileId,
        'position_ms': positionMs,
        'duration_ms': durationMs,
        'updated_at':  serverTs,
        'synced':      1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  // ── Downloads ─────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getDownloads() async {
    final db = await instance;
    return db.query('downloads', orderBy: 'downloaded_at DESC');
  }

  static Future<void> insertDownload({
    required String fileId,
    required String titleText,
    String? posterUrl,
    required String localPath,
    String? contentType,
  }) async {
    final db = await instance;
    await db.insert(
      'downloads',
      {
        'file_id':       fileId,
        'title_text':    titleText,
        'poster_url':    posterUrl,
        'local_path':    localPath,
        'status':        'downloading',
        'progress':      0.0,
        'downloaded_at': DateTime.now().millisecondsSinceEpoch,
        'content_type':  contentType,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> updateDownloadProgress(
      String fileId, double progress) async {
    final db = await instance;
    await db.update(
      'downloads',
      {'progress': progress},
      where: 'file_id = ?',
      whereArgs: [fileId],
    );
  }

  static Future<void> updateDownloadStatus(
      String fileId, String status, double progress, int fileSize) async {
    final db = await instance;
    await db.update(
      'downloads',
      {'status': status, 'progress': progress, 'file_size': fileSize},
      where: 'file_id = ?',
      whereArgs: [fileId],
    );
  }

  static Future<void> deleteDownload(String fileId) async {
    final db = await instance;
    final rows = await db.query('downloads',
        where: 'file_id = ?', whereArgs: [fileId]);
    if (rows.isNotEmpty) {
      final path = rows.first['local_path'] as String?;
      if (path != null) {
        try { await File(path).delete(); } catch (_) {}
      }
    }
    await db.delete('downloads', where: 'file_id = ?', whereArgs: [fileId]);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  // ── Phase 6: Usage Tracking ────────────────────────────────────────────

  static Future<void> addPendingUsage({required int bytes}) async {
    final db = await instance;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.insert('usage_log', {'bytes': bytes, 'flushed': 0, 'created_at': now});
  }

  static Future<int> getPendingUsageBytes() async {
    final db = await instance;
    final rows = await db.query('usage_log', where: 'flushed = ?', whereArgs: [0]);
    int total = 0;
    for (final r in rows) { total += (r['bytes'] as int? ?? 0); }
    return total;
  }

  static Future<void> clearPendingUsage() async {
    final db = await instance;
    await db.update('usage_log', {'flushed': 1}, where: 'flushed = ?', whereArgs: [0]);
    // BUG-F07 fix: delete already-flushed rows to prevent unbounded table growth
    await db.delete('usage_log', where: 'flushed = ?', whereArgs: [1]);
  }

  static Future<void> cacheQuota(Map<String, dynamic> quota) async {
    final db = await instance;
    final v = const JsonEncoder().convert(quota);
    await db.insert('quota_cache', {'k': 'last_quota', 'v': v},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<Map<String, dynamic>> getCachedQuota() async {
    final db = await instance;
    final rows = await db.query('quota_cache', where: 'k = ?', whereArgs: ['last_quota']);
    if (rows.isEmpty) return {'allowed': true};
    final v = rows.first['v'] as String? ?? '{}';
    try {
      return Map<String, dynamic>.from(
          const JsonDecoder().convert(v) as Map);
    } catch (_) {
      return {'allowed': true};
    }
  }

  // ── New-episode badge ────────────────────────────────────────────────────

  /// Returns a map of {show_id → new_episode_count} for all shows where the
  /// current episode count in SQLite exceeds the last-seen count.
  /// Single query — safe to call on every catalog load.
  static Future<Map<int, int>> getNewEpisodeCounts() async {
    final db = await instance;
    final rows = await db.rawQuery('''
      SELECT e.title_id,
             COUNT(e.id)               AS total,
             COALESCE(s.seen_count, 0) AS seen
      FROM   episodes e
      LEFT JOIN show_ep_seen s ON s.show_id = e.title_id
      GROUP  BY e.title_id
      HAVING COUNT(e.id) > COALESCE(s.seen_count, 0)
    ''');
    final result = <int, int>{};
    for (final row in rows) {
      final showId = row['title_id'] as int;
      final total  = row['total']   as int;
      final seen   = row['seen']    as int;
      result[showId] = total - seen;
    }
    return result;
  }

  /// Mark all current episodes of [showId] as seen, clearing the badge.
  /// Called from ShowDetailScreen when the user opens a show.
  static Future<void> markEpisodesSeen(int showId) async {
    final db = await instance;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM episodes WHERE title_id = ?', [showId]);
    final count = (rows.first['cnt'] as int?) ?? 0;
    await db.insert(
      'show_ep_seen',
      {'show_id': showId, 'seen_count': count},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── Phase 9: SIMOSA Streak ──────────────────────────────────────────────

  static Future<Map<String, dynamic>> getSimosaStreak() async {
    final db = await instance;
    final rows = await db.query('simosa_streak', where: 'id = ?', whereArgs: [1]);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (rows.isEmpty) return {'streak': 0, 'claimed_today': false};
    final row = rows.first;
    final lastClaim = row['last_claim'] as String?;
    final claimedToday = lastClaim == today;
    // Reset streak if more than 2 days since last claim
    int streak = (row['streak'] as int?) ?? 0;
    if (lastClaim != null && lastClaim != today) {
      final last = DateTime.tryParse(lastClaim);
      final diff = DateTime.now().difference(last ?? DateTime.now()).inDays;
      if (diff > 1) streak = 0;
    }
    return {'streak': streak, 'claimed_today': claimedToday};
  }

  static Future<void> recordSimosaClaim() async {
    final db = await instance;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final info = await getSimosaStreak();
    final claimedToday = info['claimed_today'] as bool;
    if (claimedToday) return;
    final streak = (info['streak'] as int) + 1;
    await db.insert('simosa_streak', {
      'id': 1, 'streak': streak, 'last_claim': today
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ── Watchlist ────────────────────────────────────────────────────────────

  static Future<void> addToWatchlist(CatalogItem item) async {
    final db = await instance;
    await db.insert('watchlist', {
      'id':          item.id,
      'title':       item.title,
      'year':        item.year,
      'media_type':  item.mediaType,
      'poster_url':  item.posterUrl,
      'poster_path': item.posterPath,
      'share_url':   item.shareUrl,
      'added_at':    DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> removeFromWatchlist(int id) async {
    final db = await instance;
    await db.delete('watchlist', where: 'id = ?', whereArgs: [id]);
  }

  static Future<bool> isInWatchlist(int id) async {
    final db = await instance;
    final rows = await db.query('watchlist', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty;
  }

  static Future<List<CatalogItem>> getWatchlist() async {
    final db = await instance;
    final rows = await db.query('watchlist', orderBy: 'added_at DESC');
    return rows.map(_rowToItem).toList();
  }

    static CatalogItem _rowToItem(Map<String, dynamic> row) {
    return CatalogItem(
      id:          row['id'] as int,
      title:       row['title'] as String,
      year:        row['year'] as int?,
      mediaType:   row['media_type'] as String,
      description: row['description'] as String?,
      rating:      (row['rating'] as num?)?.toDouble(),
      genres:      row['genres'] as String?,
      posterUrl:   row['poster_url'] as String?,
      shareUrl:    row['share_url'] as String?,
      posterPath:  row['poster_path'] as String?,
      isFree:      (row['is_free'] as int? ?? 0) == 1,
      dbVersion:   row['db_version'] as int? ?? 0,
      language:    row['language'] as String?,
      status:      row['status'] as String?,
      isOngoing:   (row['is_ongoing'] as int? ?? 0) == 1,
      fileId:      row['file_id'] as String?,  // AUDIT-03: was missing — CatalogItem.fileId was always null
    );
  }

  // ── Offline Guest Identity ────────────────────────────────────────────────
  // Stored in sync_meta under key 'guest_id'. Generated once on first guest
  // login, persists across app restarts, survives offline. Never sent to server.

  /// Returns the local guest ID, creating it if it doesn't exist yet.
  /// Safe to call with no network — pure SQLite.
  static Future<String> getOrCreateGuestId() async {
    final db = await instance;
    final rows = await db.query(
      'sync_meta',
      where: "key = 'guest_id'",
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.first['value'] as String;

    // Generate a new permanent guest ID — UUID v4 style using timestamp + random
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rnd = (ts * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFF;
    final guestId = 'GUEST_${ts.toRadixString(16)}_${rnd.toRadixString(16)}';

    await db.insert('sync_meta', {'key': 'guest_id', 'value': guestId},
        conflictAlgorithm: ConflictAlgorithm.replace);
    return guestId;
  }

  /// Returns true if a local guest identity has been created.
  static Future<bool> hasGuestId() async {
    final db = await instance;
    final rows = await db.query(
      'sync_meta',
      where: "key = 'guest_id'",
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Removes the local guest identity (call on full account reset only).
  static Future<void> clearGuestId() async {
    final db = await instance;
    await db.delete('sync_meta', where: "key = 'guest_id'");
  }
}
