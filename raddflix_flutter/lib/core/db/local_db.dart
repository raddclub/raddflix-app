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

  /// Active "Who's Watching" profile id for the current session. Set by
  /// ProfileNotifier on load/switch. All watchlist/watch-position reads and
  /// writes below default to this profile when no explicit profileId is
  /// passed, so existing call sites across the app stay correct without
  /// having to thread a profile id through every caller.
  static int currentProfileId = 1;

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
        -- M-15 GUARD: share_url scrambling with DeviceId as key is NOT yet wired.
        -- When wiring RequestEncoder.scrambleUrl()/unscrambleUrl(), ALWAYS:
        --   1. Keep the RF1: prefix check so legacy plain URLs pass through unchanged.
        --   2. Wrap unscrambleUrl() in try/catch; fall back to raw URL on failure —
        --      prevents device-ID change (reinstall) from permanently breaking all URLs.
        --   See: agent-hub/SECURITY_ARCHITECTURE.md §Layer-4 and §Rules line 306.
        filename  TEXT,
        remote_id INTEGER DEFAULT 0,
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
        profile_id  INTEGER NOT NULL DEFAULT 1,
        file_id     TEXT NOT NULL,
        position_ms INTEGER DEFAULT 0,
        duration_ms INTEGER DEFAULT 0,
        updated_at  INTEGER DEFAULT 0,
        synced      INTEGER DEFAULT 0,
        PRIMARY KEY (profile_id, file_id)
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
    // Watchlist — user-saved titles, one list per profile
    await db.execute('''
      CREATE TABLE IF NOT EXISTS watchlist (
        profile_id  INTEGER NOT NULL DEFAULT 1,
        id          INTEGER NOT NULL,
        title       TEXT NOT NULL,
        year        INTEGER,
        media_type  TEXT NOT NULL,
        poster_url  TEXT,
        poster_path TEXT,
        share_url   TEXT,
        added_at    INTEGER DEFAULT 0,
        PRIMARY KEY (profile_id, id)
      )
    ''');
    // "Who's Watching" profiles — local to this device, one account can have
    // several (family sharing). See models/profile.dart + providers/profile_provider.dart.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS profiles (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        name         TEXT NOT NULL,
        avatar_color TEXT DEFAULT '#8B002D',
        avatar_emoji TEXT DEFAULT '',
        is_kids      INTEGER DEFAULT 0,
        max_rating   TEXT DEFAULT 'nc17',
        pin          TEXT,
        sort_order   INTEGER DEFAULT 0,
        created_at   INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS episode_overrides (
        show_id    INTEGER NOT NULL,
        season     INTEGER NOT NULL,
        episode    INTEGER NOT NULL,
        status     TEXT NOT NULL DEFAULT 'coming_soon',
        updated_at INTEGER DEFAULT 0,
        PRIMARY KEY (show_id, season, episode)
      )
    ''');
        // Phase 12 — Full-text search (FTS5) for title + description
    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS catalog_fts
      USING fts5(title, description, content='titles', content_rowid='id')
    ''');
    // Populate FTS index from existing titles data
    await db.execute("INSERT INTO catalog_fts(catalog_fts) VALUES('rebuild')");
    // Phase 19 — Cast & crew tables (actor profiles + junction)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS persons (
        person_id     INTEGER PRIMARY KEY,
        name          TEXT NOT NULL,
        profile_url   TEXT,
        profile_local TEXT,
        fetched_at    INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cast_members (
        person_id  INTEGER NOT NULL,
        title_id   INTEGER NOT NULL,
        character  TEXT,
        order_idx  INTEGER DEFAULT 0,
        PRIMARY KEY (person_id, title_id)
      )
    ''');
    // Seed the default "Me" profile — id 1, matching the profile_id default
    // already baked into watchlist/watch_positions above.
    await db.insert('profiles', {
      'name': 'Me', 'avatar_color': '#8B002D', 'avatar_emoji': '',
      'is_kids': 0, 'max_rating': 'nc17', 'pin': null, 'sort_order': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
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
    if (oldV < 18) {
      // Admin episode status overrides (local only, survives catalog syncs)
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS episode_overrides (
            show_id    INTEGER NOT NULL,
            season     INTEGER NOT NULL,
            episode    INTEGER NOT NULL,
            status     TEXT NOT NULL DEFAULT 'coming_soon',
            updated_at INTEGER DEFAULT 0,
            PRIMARY KEY (show_id, season, episode)
          )
        ''');
      } catch (_) {}
    }
    if (oldV < 19) {
      // Cast & crew tables
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS persons (
            person_id     INTEGER PRIMARY KEY,
            name          TEXT NOT NULL,
            profile_url   TEXT,
            profile_local TEXT,
            fetched_at    INTEGER DEFAULT 0
          )
        ''');
      } catch (_) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS cast_members (
            person_id  INTEGER NOT NULL,
            title_id   INTEGER NOT NULL,
            character  TEXT,
            order_idx  INTEGER DEFAULT 0,
            PRIMARY KEY (person_id, title_id)
          )
        ''');
      } catch (_) {}
    }
    if (oldV < 20) {
      // Add remote_id to episodes — JazzDrive's permanent internal file ID.
      // Used as Pass 0 in JazzDriveService._getMedia() to match the exact file
      // without any filename guessing. Assigned once at upload time, never changes.
      try { await db.execute('ALTER TABLE episodes ADD COLUMN remote_id INTEGER DEFAULT 0'); } catch (_) {}
    }
    if (oldV < 21) {
      // "Who's Watching" multi-profile support.
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS profiles (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            name         TEXT NOT NULL,
            avatar_color TEXT DEFAULT '#8B002D',
            avatar_emoji TEXT DEFAULT '',
            is_kids      INTEGER DEFAULT 0,
            max_rating   TEXT DEFAULT 'nc17',
            pin          TEXT,
            sort_order   INTEGER DEFAULT 0,
            created_at   INTEGER DEFAULT 0
          )
        ''');
      } catch (_) {}
      // Seed the default profile so upgrading users get a "Me" profile with
      // id 1 — matching the profile_id=1 default used by pre-existing rows.
      try {
        final existing = await db.query('profiles', limit: 1);
        if (existing.isEmpty) {
          await db.insert('profiles', {
            'id': 1, 'name': 'Me', 'avatar_color': '#8B002D', 'avatar_emoji': '',
            'is_kids': 0, 'max_rating': 'nc17', 'pin': null, 'sort_order': 0,
            'created_at': DateTime.now().millisecondsSinceEpoch,
          });
        }
      } catch (_) {}
      // watchlist: id was the sole PRIMARY KEY, which would collide once two
      // profiles both save the same title. SQLite can't alter a PRIMARY KEY in
      // place, so rebuild the table with a composite (profile_id, id) key and
      // copy existing rows over (all become profile_id = 1).
      try {
        final cols = await db.rawQuery("PRAGMA table_info(watchlist)");
        final hasProfileCol = cols.any((c) => c['name'] == 'profile_id');
        if (!hasProfileCol) {
          await db.execute('ALTER TABLE watchlist RENAME TO watchlist_old');
          await db.execute('''
            CREATE TABLE watchlist (
              profile_id  INTEGER NOT NULL DEFAULT 1,
              id          INTEGER NOT NULL,
              title       TEXT NOT NULL,
              year        INTEGER,
              media_type  TEXT NOT NULL,
              poster_url  TEXT,
              poster_path TEXT,
              share_url   TEXT,
              added_at    INTEGER DEFAULT 0,
              PRIMARY KEY (profile_id, id)
            )
          ''');
          await db.execute('''
            INSERT INTO watchlist (profile_id, id, title, year, media_type, poster_url, poster_path, share_url, added_at)
            SELECT 1, id, title, year, media_type, poster_url, poster_path, share_url, added_at FROM watchlist_old
          ''');
          await db.execute('DROP TABLE watchlist_old');
        }
      } catch (_) {}
      // watch_positions: same rebuild — file_id alone was PRIMARY KEY, but each
      // profile needs its own independent resume position for the same file.
      try {
        final cols = await db.rawQuery("PRAGMA table_info(watch_positions)");
        final hasProfileCol = cols.any((c) => c['name'] == 'profile_id');
        if (!hasProfileCol) {
          await db.execute('ALTER TABLE watch_positions RENAME TO watch_positions_old');
          await db.execute('''
            CREATE TABLE watch_positions (
              profile_id  INTEGER NOT NULL DEFAULT 1,
              file_id     TEXT NOT NULL,
              position_ms INTEGER DEFAULT 0,
              duration_ms INTEGER DEFAULT 0,
              updated_at  INTEGER DEFAULT 0,
              synced      INTEGER DEFAULT 0,
              PRIMARY KEY (profile_id, file_id)
            )
          ''');
          await db.execute('''
            INSERT INTO watch_positions (profile_id, file_id, position_ms, duration_ms, updated_at, synced)
            SELECT 1, file_id, position_ms, duration_ms, updated_at, synced FROM watch_positions_old
          ''');
          await db.execute('DROP TABLE watch_positions_old');
        }
      } catch (_) {}
    }
  }

  // ── Admin episode overrides ──────────────────────────────────────────────

  /// Returns a map keyed by 'season_episode' (e.g. '1_3') → status string.
  /// Only entries the admin has explicitly set are returned.
  static Future<Map<String, String>> getEpisodeOverrides(int showId) async {
    final db = await instance;
    final rows = await db.query('episode_overrides',
        where: 'show_id = ?', whereArgs: [showId]);
    final result = <String, String>{};
    for (final r in rows) {
      result['${r['season']}_${r['episode']}'] = r['status'] as String;
    }
    return result;
  }

  /// Set or clear an admin override for a missing episode.
  /// [status] = null clears, 'coming_soon' or 'uploading' sets.
  static Future<void> setEpisodeOverride(
      int showId, int season, int episode, String? status) async {
    final db = await instance;
    if (status == null) {
      await db.delete('episode_overrides',
          where: 'show_id = ? AND season = ? AND episode = ?',
          whereArgs: [showId, season, episode]);
    } else {
      await db.insert(
        'episode_overrides',
        {
          'show_id': showId, 'season': season, 'episode': episode,
          'status': status,
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  // ── Cast & crew (TMDB-sourced, SQLite-cached) ─────────────────────────────

  static Future<void> saveCastRaw(
      int titleId, List<Map<String, dynamic>> cast) async {
    final db  = await instance;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final m in cast) {
      await db.insert(
        'persons',
        {
          'person_id':     m['person_id'],
          'name':          m['name'],
          'profile_url':   m['profile_url'],
          'profile_local': m['profile_local'],
          'fetched_at':    now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await db.insert(
        'cast_members',
        {
          'person_id': m['person_id'],
          'title_id':  titleId,
          'character': m['character'],
          'order_idx': m['order_idx'] ?? 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  static Future<List<Map<String, dynamic>>> getCastRaw(int titleId) async {
    final db   = await instance;
    final rows = await db.rawQuery('''
      SELECT p.person_id, p.name, p.profile_url, p.profile_local,
             c.character, c.order_idx
      FROM cast_members c
      JOIN persons p ON p.person_id = c.person_id
      WHERE c.title_id = ?
      ORDER BY c.order_idx ASC
    ''', [titleId]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  static Future<void> updatePersonImagePath(
      int personId, String localPath) async {
    final db = await instance;
    await db.update('persons', {'profile_local': localPath},
        where: 'person_id = ?', whereArgs: [personId]);
  }

  static Future<List<CatalogItem>> getPersonTitles(int personId) async {
    final db   = await instance;
    final rows = await db.rawQuery('''
      SELECT t.* FROM titles t
      INNER JOIN cast_members c ON c.title_id = t.id
      WHERE c.person_id = ?
      ORDER BY t.year DESC NULLS LAST, t.title ASC
    ''', [personId]);
    return rows.map(_rowToItem).toList();
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
    // FIX-LIKE-01: escape % and _ so they match literally, not as LIKE wildcards.
    final safeQ = query.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
    final rows = await db.query('titles',
        where: "title LIKE ? ESCAPE '\\'",
        whereArgs: ['%$safeQ%'],
        orderBy: 'title ASC',
        limit: 50);
    return rows.map(_rowToItem).toList();
  }

  /// Rebuild the FTS5 catalog index from the current titles table.
  /// Call after a bulk sync so search reflects new/updated titles immediately.

  /// Advanced search with full filter support: query (FTS5 title+description+genres),
  /// genre, year, language, minRating, isFree, status (ongoing/completed/released),
  /// offlineOnly (joined against downloads table), and sort order.
  ///
  /// All filters are optional. Empty query returns browse results (all matching filters).
  /// Returns up to 200 results with a description snippet for matched items.
  static Future<List<SearchResult>> searchAdvanced({
    String query = '',
    String? genre,
    int? year,
    String? language,
    double? minRating,
    bool? isFree,
    String? status,          // 'ongoing' | 'completed' | 'released'
    bool offlineOnly = false,
    String sortBy = 'relevance', // 'relevance' | 'rating' | 'year_desc' | 'year_asc' | 'title'
    int limit = 200,
  }) async {
    final db = await instance;

    // M-14 FIX: whitelist sortBy before it is interpolated directly into the SQL
    // ORDER BY clause. All filter values use ? params (safe), but sortBy and limit
    // are string/int-interpolated. An unexpected sortBy value could inject arbitrary
    // SQL; clamp limit to a safe range to prevent unbounded result sets.
    const _validSorts = {'relevance', 'rating', 'year_desc', 'year_asc', 'title'};
    final effectiveSortBy = _validSorts.contains(sortBy) ? sortBy : 'relevance';
    final safeLimit = limit.clamp(1, 500);

    // Build WHERE clauses
    final conditions = <String>[];
    final args = <dynamic>[];

    if (genre != null && genre.isNotEmpty) {
      conditions.add("t.genres LIKE ?");
      args.add('%$genre%');
    }
    if (year != null) {
      conditions.add("t.year = ?");
      args.add(year);
    }
    if (language != null && language.isNotEmpty) {
      conditions.add("LOWER(t.language) = LOWER(?)");
      args.add(language);
    }
    if (minRating != null) {
      conditions.add("t.rating >= ?");
      args.add(minRating);
    }
    if (isFree != null) {
      conditions.add("t.is_free = ?");
      args.add(isFree ? 1 : 0);
    }
    if (status != null && status.isNotEmpty) {
      if (status == 'ongoing') {
        conditions.add("(t.is_ongoing = 1 OR t.status = 'ongoing')");
      } else {
        conditions.add("t.status = ?");
        args.add(status);
      }
    }

    // Offline filter: join against downloads where status = 'completed'
    final offlineJoin = offlineOnly
        ? "INNER JOIN downloads dl ON dl.file_id = t.file_id AND dl.status = 'completed'"
        : '';

    // Sort clause — uses effectiveSortBy (whitelisted above, M-14)
    final orderClause = () {
      switch (effectiveSortBy) {
        case 'rating':     return 'ORDER BY t.rating DESC NULLS LAST, t.title ASC';
        case 'year_desc':  return 'ORDER BY t.year DESC NULLS LAST, t.title ASC';
        case 'year_asc':   return 'ORDER BY t.year ASC NULLS LAST, t.title ASC';
        case 'title':      return 'ORDER BY t.title ASC';
        default:           return ''; // relevance — handled by FTS rank
      }
    }();

    List<Map<String, dynamic>> rows = [];
    String? snippetQuery;

    if (query.trim().isNotEmpty) {
      // FTS5 search on title + description + genres (genres added to FTS in rebuildFtsIndex)
      final terms = query.trim().split(RegExp(r'\s+'));
      final ftsQuery = terms.map((w) => '"${w.replaceAll('"', '')}"*').join(' ');
      snippetQuery = ftsQuery;

      final whereStr = conditions.isNotEmpty ? 'AND ${conditions.join(" AND ")}' : '';
      final ftsOrder = effectiveSortBy == 'relevance' ? 'ORDER BY rank, t.title ASC' : orderClause;

      try {
        rows = await db.rawQuery('''
          SELECT t.*,
                 snippet(catalog_fts, 1, '[', ']', '…', 8) AS _snippet
          FROM titles t
          $offlineJoin
          INNER JOIN catalog_fts fts ON t.id = fts.rowid
          WHERE catalog_fts MATCH ?
          $whereStr
          $ftsOrder
          LIMIT $safeLimit
        ''', [ftsQuery, ...args]);
      } catch (_) {
        // FTS unavailable — fallback LIKE
        final likeWhere = ['t.title LIKE ?', ...conditions].join(' AND ');
        rows = await db.rawQuery('''
          SELECT t.* FROM titles t $offlineJoin
          WHERE $likeWhere $orderClause LIMIT $safeLimit
        ''', ['%$query%', ...args]);
      }
    } else {
      // Browse mode — no text query, just filters
      final whereStr = conditions.isNotEmpty ? 'WHERE ${conditions.join(" AND ")}' : '';
      rows = await db.rawQuery('''
        SELECT t.* FROM titles t $offlineJoin
        $whereStr $orderClause LIMIT $safeLimit
      ''', args);
    }

    return rows.map((row) {
      final item = _rowToItem(row);
      final snippet = row['_snippet'] as String?;
      return SearchResult(item: item, snippet: snippet);
    }).toList();
  }

  /// Returns distinct non-empty language values from the titles table.
  /// Used to populate the language filter chip list in search.
  static Future<List<String>> getDistinctLanguages() async {
    final db = await instance;
    final rows = await db.rawQuery(
      "SELECT DISTINCT language FROM titles WHERE language IS NOT NULL AND language != '' ORDER BY language ASC"
    );
    return rows.map((r) => r['language'] as String).toList();
  }

  /// Returns distinct non-empty year values descending.
  static Future<List<int>> getDistinctYears() async {
    final db = await instance;
    final rows = await db.rawQuery(
      "SELECT DISTINCT year FROM titles WHERE year IS NOT NULL ORDER BY year DESC"
    );
    return rows.map((r) => r['year'] as int).toList();
  }

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
    // Safe int parse: server may send id as String or int depending on JSON encoder
    final rawId = row['id'];
    final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
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
        // FIX-FOLDER-01: persist folder_share_url so TV shows (episodes in one folder)
        // can resolve stream links. Column added in migration v17 but was never written.
        if (folderShareUrl.isNotEmpty) 'folder_share_url': folderShareUrl,
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
        if (fileId.isNotEmpty) 'file_id': fileId,
        // FIX-FOLDER-01: persist folder_share_url on new inserts too
        if (folderShareUrl.isNotEmpty) 'folder_share_url': folderShareUrl,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // FIX-FOLDER-01: folder_share_url is now persisted above.
    // poster_share_url remains in stream_cache (no titles column yet).
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
  static Future<Map<String, dynamic>> getShareInfo(String fileId) async {
    final db = await instance;
    final epRows = await db.query('episodes',
        where: 'file_id = ?', whereArgs: [fileId], limit: 1);
    if (epRows.isNotEmpty) {
      final rawUrl   = epRows.first['share_url'] as String?;
      final filename = epRows.first['filename']  as String?;
      final remoteId = epRows.first['remote_id'] as int? ?? 0;
      final url = (rawUrl != null && rawUrl.isNotEmpty) ? await _decodeUrl(rawUrl) : null;
      return {'share_url': url, 'filename': filename, 'remote_id': remoteId};
    }
    final titleRows = await db.rawQuery(
        'SELECT share_url FROM titles WHERE file_id = ? LIMIT 1', [fileId]);
    if (titleRows.isNotEmpty) {
      final rawUrl = titleRows.first['share_url'] as String?;
      return {'share_url': rawUrl != null ? await _decodeUrl(rawUrl) : null, 'filename': null, 'remote_id': 0};
    }
    return {'share_url': null, 'filename': null, 'remote_id': 0};
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


  // ── Catalog pruning ──────────────────────────────────────────────────────

  /// Delete any title (and its orphaned episodes) whose id is NOT in [validIds].
  /// Called after a full Oracle sync to remove stale entries left over from a
  /// DB rebuild where title IDs changed (BUG-STALE-IDS fix).
  /// Returns the number of titles deleted.
  static Future<int> pruneStaleIds(List<int> validIds) async {
    if (validIds.isEmpty) return 0;
    final db = await instance;
    final placeholders = validIds.map((_) => '?').join(',');
    final deleted = await db.rawDelete(
      'DELETE FROM titles WHERE id NOT IN ($placeholders)',
      validIds,
    );
    if (deleted > 0) {
      await db.rawDelete(
        'DELETE FROM episodes WHERE title_id NOT IN ($placeholders)',
        validIds,
      );
      await rebuildFtsIndex();
    }
    return deleted;
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
      if (decoded == null || decoded.isEmpty) continue;
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

  static Future<int> getSavedPosition(String fileId, {int? profileId}) async {
    final db = await instance;
    final rows = await db.query('watch_positions',
        where: 'profile_id = ? AND file_id = ?',
        whereArgs: [profileId ?? currentProfileId, fileId]);
    if (rows.isEmpty) return 0;
    return rows.first['position_ms'] as int? ?? 0;
  }

  static Future<void> savePosition(String fileId, int positionMs,
      {int durationMs = 0, int? profileId}) async {
    final db = await instance;
    await db.insert(
      'watch_positions',
      {
        'profile_id':  profileId ?? currentProfileId,
        'file_id':     fileId,
        'position_ms': positionMs,
        'duration_ms': durationMs,
        'updated_at':  DateTime.now().millisecondsSinceEpoch,
        'synced':      0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> clearPosition(String fileId, {int? profileId}) async {
    final db = await instance;
    await db.delete('watch_positions',
        where: 'profile_id = ? AND file_id = ?',
        whereArgs: [profileId ?? currentProfileId, fileId]);
  }

  /// BUG-A22: clearPosition(fileId) was never called from the UI.
  /// Added clearAllPositions() to support a 'Reset Watch Progress' action
  /// in profile_screen without needing a specific fileId.
  static Future<void> clearAllPositions({int? profileId}) async {
    final db = await instance;
    await db.delete('watch_positions',
        where: 'profile_id = ?', whereArgs: [profileId ?? currentProfileId]);
  }

  static Future<List<Map<String, dynamic>>> getWatchPositions({int? profileId}) async {
    final db = await instance;
    return db.query('watch_positions',
        where: 'profile_id = ?', whereArgs: [profileId ?? currentProfileId],
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
  /// Note: server-side watch history has no concept of profiles (one account
  /// = one cloud history), so sync only ever reads/writes the *active*
  /// profile's local positions. Cross-device continue-watching therefore
  /// tracks whichever profile is active on this device when sync runs.
  static Future<List<Map<String, dynamic>>> getUnsyncedPositions({int? profileId}) async {
    final db = await instance;
    return db.query('watch_positions',
        where: 'profile_id = ? AND synced = 0 AND position_ms > 0',
        whereArgs: [profileId ?? currentProfileId],
        orderBy: 'updated_at DESC');
  }

  /// Mark a watch position as successfully confirmed on the server.
  static Future<void> markPositionSynced(String fileId, {int? profileId}) async {
    final db = await instance;
    await db.update(
      'watch_positions',
      {'synced': 1},
      where: 'profile_id = ? AND file_id = ?',
      whereArgs: [profileId ?? currentProfileId, fileId],
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
    int? profileId,
  }) async {
    final db = await instance;
    final pid = profileId ?? currentProfileId;
    final serverTs = watchedAtEpochSecs * 1000; // epoch-sec → epoch-ms
    final existing = await db.query('watch_positions',
        where: 'profile_id = ? AND file_id = ?', whereArgs: [pid, fileId], limit: 1);
    if (existing.isNotEmpty) {
      final localTs = existing.first['updated_at'] as int? ?? 0;
      if (serverTs <= localTs) return; // local is newer — keep it
      await db.update('watch_positions', {
        'position_ms': positionMs,
        'duration_ms': durationMs,
        'updated_at':  serverTs,
        'synced':      1,
      }, where: 'profile_id = ? AND file_id = ?', whereArgs: [pid, fileId]);
    } else {
      await db.insert('watch_positions', {
        'profile_id':  pid,
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

  /// Look up stream info for [fileId] from the catalog (episodes or titles).
  /// Returns a Map with share_url, filename?, remote_id? or null if not found.
  /// Used by DownloadsNotifier.retryDownload() so the user can retry a failed
  /// download directly from the Downloads screen without navigating back to the
  /// content page.
  static Future<Map<String, dynamic>?> getFileInfo(String fileId) async {
    final db = await instance;
    // Episodes table first (TV shows, dramas)
    final eps = await db.query('episodes',
        columns: ['file_id', 'share_url', 'filename', 'remote_id'],
        where: 'file_id = ?', whereArgs: [fileId], limit: 1);
    if (eps.isNotEmpty) return Map<String, dynamic>.from(eps.first);
    // Titles table fallback (movies / single-file items)
    try {
      final titles = await db.query('titles',
          columns: ['file_id', 'share_url'],
          where: 'file_id = ?', whereArgs: [fileId], limit: 1);
      if (titles.isNotEmpty) return Map<String, dynamic>.from(titles.first);
    } catch (_) {}
    return null;
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

  static Future<void> addToWatchlist(CatalogItem item, {int? profileId}) async {
    final db = await instance;
    await db.insert('watchlist', {
      'profile_id':  profileId ?? currentProfileId,
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

  static Future<void> removeFromWatchlist(int id, {int? profileId}) async {
    final db = await instance;
    await db.delete('watchlist',
        where: 'profile_id = ? AND id = ?', whereArgs: [profileId ?? currentProfileId, id]);
  }

  static Future<bool> isInWatchlist(int id, {int? profileId}) async {
    final db = await instance;
    final rows = await db.query('watchlist',
        where: 'profile_id = ? AND id = ?', whereArgs: [profileId ?? currentProfileId, id], limit: 1);
    return rows.isNotEmpty;
  }

  static Future<List<CatalogItem>> getWatchlist({int? profileId}) async {
    final db = await instance;
    final rows = await db.query('watchlist',
        where: 'profile_id = ?', whereArgs: [profileId ?? currentProfileId],
        orderBy: 'added_at DESC');
    return rows.map(_rowToItem).toList();
  }

  // ── Profiles ("Who's Watching") ─────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getProfiles() async {
    final db = await instance;
    return db.query('profiles', orderBy: 'sort_order ASC, id ASC');
  }

  static Future<int> createProfile({
    required String name,
    String avatarColor = '#8B002D',
    String avatarEmoji = '',
    bool isKids = false,
    String maxRating = 'nc17',
    String? pin,
  }) async {
    final db = await instance;
    final countRow = await db.rawQuery('SELECT COUNT(*) AS c FROM profiles');
    final sortOrder = (countRow.first['c'] as int?) ?? 0;
    return db.insert('profiles', {
      'name':         name,
      'avatar_color': avatarColor,
      'avatar_emoji': avatarEmoji,
      'is_kids':      isKids ? 1 : 0,
      'max_rating':   isKids ? 'pg' : maxRating,
      'pin':          pin,
      'sort_order':   sortOrder,
      'created_at':   DateTime.now().millisecondsSinceEpoch,
    });
  }

  static Future<void> updateProfile(
    int id, {
    String? name,
    String? avatarColor,
    String? avatarEmoji,
    bool? isKids,
    String? maxRating,
    String? pin,
    bool clearPin = false,
  }) async {
    final db = await instance;
    final values = <String, dynamic>{};
    if (name != null) values['name'] = name;
    if (avatarColor != null) values['avatar_color'] = avatarColor;
    if (avatarEmoji != null) values['avatar_emoji'] = avatarEmoji;
    if (isKids != null) values['is_kids'] = isKids ? 1 : 0;
    if (maxRating != null) values['max_rating'] = maxRating;
    if (clearPin) {
      values['pin'] = null;
    } else if (pin != null) {
      values['pin'] = pin;
    }
    if (values.isEmpty) return;
    await db.update('profiles', values, where: 'id = ?', whereArgs: [id]);
  }

  /// Deletes a profile and all data scoped to it (watchlist + resume
  /// positions). Downloads are intentionally left alone — they're shared
  /// device storage, not per-profile.
  static Future<void> deleteProfile(int id) async {
    final db = await instance;
    await db.delete('profiles', where: 'id = ?', whereArgs: [id]);
    await db.delete('watchlist', where: 'profile_id = ?', whereArgs: [id]);
    await db.delete('watch_positions', where: 'profile_id = ?', whereArgs: [id]);
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

  // ── Home-screen collections ──────────────────────────────────────────────

  /// Top-rated free content for the "Free to Watch" home row.
  static Future<List<CatalogItem>> getFreeContent({int limit = 20}) async {
    final db = await instance;
    final rows = await db.rawQuery(
      'SELECT * FROM titles WHERE is_free = 1 ORDER BY rating DESC, title ASC LIMIT ?',
      [limit],
    );
    return rows.map(_rowToItem).toList();
  }

  /// Ongoing shows for the "Ongoing" home row (status = ongoing OR is_ongoing = 1).
  static Future<List<CatalogItem>> getOngoingShows({int limit = 20}) async {
    final db = await instance;
    final rows = await db.rawQuery('''
      SELECT * FROM titles
      WHERE (is_ongoing = 1 OR status = 'ongoing') AND media_type = 'show'
      ORDER BY rating DESC, title ASC
      LIMIT ?
    ''', [limit]);
    return rows.map(_rowToItem).toList();
  }

  /// Most recently added titles — ordered by db_version DESC (highest = newest sync batch).
  static Future<List<CatalogItem>> getNewlyAdded({int limit = 20}) async {
    final db = await instance;
    final rows = await db.rawQuery(
      'SELECT * FROM titles ORDER BY db_version DESC, id DESC LIMIT ?',
      [limit],
    );
    return rows.map(_rowToItem).toList();
  }

  // ── Profile watch statistics ─────────────────────────────────────────────

  /// Aggregate watch statistics for the profile stats card.
  ///
  /// Returns:
  ///   total_ms   — sum of all saved playback positions (milliseconds)
  ///   completed  — items where progress ≥ 95 %
  ///   dl_count   — completed downloads
  ///   dl_bytes   — total byte size of completed downloads
  ///   top_genre  — most-watched genre (joined via episodes → titles)
  static Future<Map<String, dynamic>> getWatchStats({int? profileId}) async {
    final db = await instance;
    final pid = profileId ?? currentProfileId;

    final timeRows = await db.rawQuery(
      'SELECT COALESCE(SUM(position_ms), 0) AS total FROM watch_positions WHERE profile_id = ?',
      [pid],
    );
    final totalMs = (timeRows.first['total'] as int?) ?? 0;

    final completedRows = await db.rawQuery('''
      SELECT COUNT(*) AS cnt FROM watch_positions
      WHERE profile_id = ? AND duration_ms > 0
        AND CAST(position_ms AS REAL) / duration_ms >= 0.95
    ''', [pid]);
    final completed = (completedRows.first['cnt'] as int?) ?? 0;

    // Downloads are shared device storage, not per-profile — intentionally unscoped.
    final dlRows = await db.rawQuery('''
      SELECT COUNT(*) AS cnt,
             COALESCE(SUM(file_size), 0) AS total_bytes
      FROM downloads WHERE status = 'completed'
    ''');
    final dlCount = (dlRows.first['cnt'] as int?) ?? 0;
    final dlBytes = (dlRows.first['total_bytes'] as int?) ?? 0;

    String? topGenre;
    try {
      final genreRows = await db.rawQuery('''
        SELECT t.genres, COUNT(*) AS cnt
        FROM watch_positions wp
        JOIN episodes e ON e.file_id  = wp.file_id
        JOIN titles   t ON t.id       = e.title_id
        WHERE wp.profile_id = ? AND t.genres IS NOT NULL AND t.genres != ''
        GROUP BY t.genres ORDER BY cnt DESC LIMIT 1
      ''', [pid]);
      if (genreRows.isNotEmpty) {
        final raw = (genreRows.first['genres'] as String? ?? '')
            .replaceAll('[', '').replaceAll(']', '')
            .replaceAll('"', '').replaceAll("'", '');
        final parts = raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        if (parts.isNotEmpty) topGenre = parts.first;
      }
    } catch (_) {}

    return {
      'total_ms':  totalMs,
      'completed': completed,
      'dl_count':  dlCount,
      'dl_bytes':  dlBytes,
      'top_genre': topGenre,
    };
  }
}


/// Wraps a [CatalogItem] with an optional FTS5 description snippet showing
/// why the item matched. Snippet uses "[" / "]" markers around matched tokens.
class SearchResult {
  final CatalogItem item;
  final String? snippet; // null when no text query or FTS unavailable

  const SearchResult({required this.item, this.snippet});
}
