import sqlite3
import time
import threading
import json
from pathlib import Path
DB_PATH = str(Path(__file__).resolve().parent / "radd_media.db")
_lock = threading.RLock()
def _get_conn():
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn
def init_db():
    with _lock:
        with _get_conn() as conn:
            conn.executescript("""
            CREATE TABLE IF NOT EXISTS titles (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                content_key     TEXT UNIQUE NOT NULL,
                tmdb_id         INTEGER,
                imdb_id         TEXT,
                media_type      TEXT NOT NULL DEFAULT 'movie',
                title           TEXT NOT NULL,
                original_title  TEXT,
                year            TEXT,
                end_year        TEXT,
                rating          REAL,
                vote_count      INTEGER DEFAULT 0,
                poster          TEXT,
                backdrop        TEXT,
                overview        TEXT,
                genres_csv      TEXT,
                cast_names      TEXT,
                cast_json       TEXT,
                director        TEXT,
                crew_json       TEXT,
                languages_csv   TEXT,
                runtime         INTEGER,
                total_seasons   INTEGER,
                status          TEXT,
                tagline         TEXT,
                created_at      INTEGER NOT NULL,
                updated_at      INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_titles_key   ON titles(content_key);
            CREATE INDEX IF NOT EXISTS idx_titles_tmdb  ON titles(tmdb_id);
            CREATE INDEX IF NOT EXISTS idx_titles_imdb  ON titles(imdb_id);
            CREATE INDEX IF NOT EXISTS idx_titles_type  ON titles(media_type);
            CREATE INDEX IF NOT EXISTS idx_titles_dir   ON titles(director COLLATE NOCASE);
            CREATE INDEX IF NOT EXISTS idx_titles_year  ON titles(year);
            CREATE VIRTUAL TABLE IF NOT EXISTS titles_fts USING fts5(
                title, original_title, director, cast_names, overview, genres_csv,
                content='titles', content_rowid='id',
                tokenize='unicode61 remove_diacritics 2'
            );
            CREATE TRIGGER IF NOT EXISTS titles_ai AFTER INSERT ON titles BEGIN
                INSERT INTO titles_fts(rowid, title, original_title, director, cast_names, overview, genres_csv)
                VALUES (new.id, new.title, new.original_title, new.director, new.cast_names, new.overview, new.genres_csv);
            END;
            CREATE TRIGGER IF NOT EXISTS titles_ad AFTER DELETE ON titles BEGIN
                INSERT INTO titles_fts(titles_fts, rowid, title, original_title, director, cast_names, overview, genres_csv)
                VALUES ('delete', old.id, old.title, old.original_title, old.director, old.cast_names, old.overview, old.genres_csv);
            END;
            CREATE TRIGGER IF NOT EXISTS titles_au AFTER UPDATE ON titles BEGIN
                INSERT INTO titles_fts(titles_fts, rowid, title, original_title, director, cast_names, overview, genres_csv)
                VALUES ('delete', old.id, old.title, old.original_title, old.director, old.cast_names, old.overview, old.genres_csv);
                INSERT INTO titles_fts(rowid, title, original_title, director, cast_names, overview, genres_csv)
                VALUES (new.id, new.title, new.original_title, new.director, new.cast_names, new.overview, new.genres_csv);
            END;
            CREATE TABLE IF NOT EXISTS files (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                fingerprint     TEXT UNIQUE,
                title_id        INTEGER REFERENCES titles(id) ON DELETE SET NULL,
                account_id      INTEGER REFERENCES accounts(id),
                filename        TEXT NOT NULL,
                season          INTEGER,
                episode         INTEGER,
                episode_title   TEXT,
                size_bytes      INTEGER DEFAULT 0,
                quality         TEXT,
                language        TEXT,
                remote_id       TEXT,
                remote_folder_id TEXT,
                folder_path     TEXT,
                share_url       TEXT,
                share_key       TEXT,
                share_link_id   TEXT,
                share_folder_id TEXT,
                download_url    TEXT,
                remote_file_id  TEXT,
                uploaded_at     INTEGER,
                is_ready        INTEGER DEFAULT 0,
                created_at      INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_files_title  ON files(title_id);
            CREATE INDEX IF NOT EXISTS idx_files_fp     ON files(fingerprint);
            CREATE INDEX IF NOT EXISTS idx_files_se     ON files(season, episode);
            CREATE INDEX IF NOT EXISTS idx_files_acct   ON files(account_id);
            CREATE INDEX IF NOT EXISTS idx_files_share  ON files(share_key);
            CREATE INDEX IF NOT EXISTS idx_files_ready  ON files(is_ready);
            CREATE TABLE IF NOT EXISTS accounts (
                id                  INTEGER PRIMARY KEY AUTOINCREMENT,
                label               TEXT UNIQUE NOT NULL,
                msisdn              TEXT NOT NULL,
                jsessionid          TEXT,
                validation_key      TEXT,
                session_node        TEXT,
                notes               TEXT,
                is_active           INTEGER DEFAULT 1,
                storage_used_bytes  INTEGER DEFAULT 0,
                storage_free_bytes  INTEGER DEFAULT 0,
                last_scan_at        INTEGER,
                session_ok          INTEGER DEFAULT 0,
                created_at          INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS api_keys (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                provider        TEXT NOT NULL,
                api_key         TEXT NOT NULL UNIQUE,
                label           TEXT,
                is_active       INTEGER DEFAULT 1,
                is_dead         INTEGER DEFAULT 0,
                error_count     INTEGER DEFAULT 0,
                last_error      TEXT,
                requests_today  INTEGER DEFAULT 0,
                last_used_at    INTEGER,
                added_at        INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_apikeys_p ON api_keys(provider, is_active, is_dead);
            CREATE TABLE IF NOT EXISTS scan_log (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                account_id  INTEGER REFERENCES accounts(id),
                event       TEXT,
                message     TEXT,
                ts          INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_scanlog_a ON scan_log(account_id, ts);
            """)
def setup():
    init_db()
_loaded = False
def ensure_setup():
    global _loaded
    if not _loaded:
        setup()
        _loaded = True
def _now():
    return int(time.time())
def upsert_title(data: dict) -> int:
    ensure_setup()
    now = _now()
    ck = data.get('content_key', '')
    if not ck:
        return 0
    with _lock:
        with _get_conn() as conn:
            existing = conn.execute("SELECT id FROM titles WHERE content_key=?", (ck,)).fetchone()
            if existing:
                conn.execute("""
                    UPDATE titles SET
                        tmdb_id=?, imdb_id=?, media_type=?, title=?, original_title=?,
                        year=?, end_year=?, rating=?, vote_count=?, poster=?, backdrop=?,
                        overview=?, genres_csv=?, cast_names=?, cast_json=?, director=?,
                        crew_json=?, languages_csv=?, runtime=?, total_seasons=?,
                        status=?, tagline=?, updated_at=?
                    WHERE content_key=?
                """, (
                    data.get('tmdb_id'), data.get('imdb_id'),
                    data.get('media_type', 'movie'), data.get('title', ''),
                    data.get('original_title'), data.get('year'), data.get('end_year'),
                    data.get('rating'), data.get('vote_count', 0),
                    data.get('poster'), data.get('backdrop'), data.get('overview'),
                    data.get('genres_csv'), data.get('cast_names'), data.get('cast_json'),
                    data.get('director'), data.get('crew_json'), data.get('languages_csv'),
                    data.get('runtime'), data.get('total_seasons'),
                    data.get('status'), data.get('tagline'), now, ck,
                ))
                return existing['id']
            cur = conn.execute("""
                INSERT INTO titles (
                    content_key, tmdb_id, imdb_id, media_type, title, original_title,
                    year, end_year, rating, vote_count, poster, backdrop, overview,
                    genres_csv, cast_names, cast_json, director, crew_json,
                    languages_csv, runtime, total_seasons, status, tagline,
                    created_at, updated_at
                ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, (
                ck, data.get('tmdb_id'), data.get('imdb_id'),
                data.get('media_type', 'movie'), data.get('title', ''),
                data.get('original_title'), data.get('year'), data.get('end_year'),
                data.get('rating'), data.get('vote_count', 0),
                data.get('poster'), data.get('backdrop'), data.get('overview'),
                data.get('genres_csv'), data.get('cast_names'), data.get('cast_json'),
                data.get('director'), data.get('crew_json'), data.get('languages_csv'),
                data.get('runtime'), data.get('total_seasons'),
                data.get('status'), data.get('tagline'), now, now,
            ))
            return cur.lastrowid
def upsert_file(data: dict) -> int:
    ensure_setup()
    now = _now()
    fp = data.get('fingerprint')
    with _lock:
        with _get_conn() as conn:
            if fp:
                existing = conn.execute("SELECT id FROM files WHERE fingerprint=?", (fp,)).fetchone()
                if existing:
                    conn.execute("""
                        UPDATE files SET
                            title_id=?, account_id=?, filename=?, season=?, episode=?,
                            episode_title=?, size_bytes=?, quality=?, language=?,
                            remote_id=?, remote_folder_id=?, folder_path=?,
                            share_url=?, share_key=?, share_link_id=?, share_folder_id=?,
                            download_url=?, remote_file_id=?, uploaded_at=?, is_ready=?
                        WHERE fingerprint=?
                    """, (
                        data.get('title_id'), data.get('account_id'), data.get('filename', ''),
                        data.get('season'), data.get('episode'), data.get('episode_title'),
                        data.get('size_bytes', 0), data.get('quality'), data.get('language'),
                        data.get('remote_id'), data.get('remote_folder_id'),
                        data.get('folder_path'), data.get('share_url'), data.get('share_key'),
                        data.get('share_link_id'), data.get('share_folder_id'),
                        data.get('download_url'), data.get('remote_file_id'),
                        data.get('uploaded_at'), data.get('is_ready', 0), fp,
                    ))
                    return existing['id']
            cur = conn.execute("""
                INSERT OR REPLACE INTO files (
                    fingerprint, title_id, account_id, filename, season, episode,
                    episode_title, size_bytes, quality, language, remote_id,
                    remote_folder_id, folder_path, share_url, share_key, share_link_id,
                    share_folder_id, download_url, remote_file_id, uploaded_at, is_ready, created_at
                ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, (
                fp, data.get('title_id'), data.get('account_id'), data.get('filename', ''),
                data.get('season'), data.get('episode'), data.get('episode_title'),
                data.get('size_bytes', 0), data.get('quality'), data.get('language'),
                data.get('remote_id'), data.get('remote_folder_id'), data.get('folder_path'),
                data.get('share_url'), data.get('share_key'), data.get('share_link_id'),
                data.get('share_folder_id'), data.get('download_url'), data.get('remote_file_id'),
                data.get('uploaded_at'), data.get('is_ready', 0), now,
            ))
            return cur.lastrowid
def search_fts(query: str, limit: int = 20) -> list:
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            q = query.replace('"', '""').strip()
            try:
                rows = conn.execute("""
                    SELECT t.* FROM titles_fts f
                    JOIN titles t ON t.id = f.rowid
                    WHERE titles_fts MATCH ?
                    ORDER BY rank LIMIT ?
                """, (f'"{q}"', limit)).fetchall()
                if rows:
                    return [dict(r) for r in rows]
            except Exception:
                pass
            rows = conn.execute("""
                SELECT * FROM titles
                WHERE title LIKE ? OR cast_names LIKE ? OR director LIKE ?
                ORDER BY COALESCE(rating,0) DESC LIMIT ?
            """, (f'%{q}%', f'%{q}%', f'%{q}%', limit)).fetchall()
            return [dict(r) for r in rows]
def search_by_actor(actor: str, limit: int = 20) -> list:
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            rows = conn.execute("""
                SELECT * FROM titles WHERE cast_names LIKE ?
                ORDER BY COALESCE(rating,0) DESC LIMIT ?
            """, (f'%{actor}%', limit)).fetchall()
            return [dict(r) for r in rows]
def search_by_genre(genre: str, limit: int = 20) -> list:
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            rows = conn.execute("""
                SELECT * FROM titles WHERE genres_csv LIKE ?
                ORDER BY COALESCE(rating,0) DESC LIMIT ?
            """, (f'%{genre}%', limit)).fetchall()
            return [dict(r) for r in rows]
def search_by_director(director: str, limit: int = 20) -> list:
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            rows = conn.execute("""
                SELECT * FROM titles WHERE director LIKE ?
                ORDER BY COALESCE(rating,0) DESC LIMIT ?
            """, (f'%{director}%', limit)).fetchall()
            return [dict(r) for r in rows]
def search_by_year(year: str, limit: int = 20) -> list:
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            rows = conn.execute("""
                SELECT * FROM titles WHERE year = ?
                ORDER BY COALESCE(rating,0) DESC LIMIT ?
            """, (year, limit)).fetchall()
            return [dict(r) for r in rows]
def get_top_rated(limit: int = 10) -> list:
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            rows = conn.execute("""
                SELECT t.* FROM titles t
                JOIN files f ON f.title_id = t.id AND f.is_ready = 1
                WHERE t.rating IS NOT NULL
                ORDER BY t.rating DESC LIMIT ?
            """, (limit,)).fetchall()
            return [dict(r) for r in rows]
def get_random_title() -> dict:
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            row = conn.execute("""
                SELECT t.* FROM titles t
                JOIN files f ON f.title_id = t.id AND f.is_ready = 1
                ORDER BY RANDOM() LIMIT 1
            """).fetchone()
            return dict(row) if row else {}
def get_files_for_title(title_id: int) -> list:
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            rows = conn.execute("""
                SELECT * FROM files WHERE title_id=? AND is_ready=1
                ORDER BY COALESCE(season,0), COALESCE(episode,0), filename
            """, (title_id,)).fetchall()
            return [dict(r) for r in rows]
def get_title_by_id(title_id: int) -> dict:
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            row = conn.execute("SELECT * FROM titles WHERE id=?", (title_id,)).fetchone()
            return dict(row) if row else {}
def list_recent_titles(limit: int = 10) -> list:
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            rows = conn.execute("""
                SELECT DISTINCT t.* FROM titles t
                JOIN files f ON f.title_id = t.id AND f.is_ready = 1
                ORDER BY t.created_at DESC LIMIT ?
            """, (limit,)).fetchall()
            return [dict(r) for r in rows]
def count_library() -> dict:
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            titles = conn.execute("SELECT COUNT(*) n FROM titles").fetchone()['n']
            files  = conn.execute("SELECT COUNT(*) n FROM files WHERE is_ready=1").fetchone()['n']
            size   = conn.execute("SELECT COALESCE(SUM(size_bytes),0) s FROM files").fetchone()['s']
            return {'titles': titles, 'files': files, 'total_size': size}
def upsert_account(data: dict) -> int:
    ensure_setup()
    now = _now()
    with _lock:
        with _get_conn() as conn:
            existing = conn.execute(
                "SELECT id FROM accounts WHERE msisdn=?", (data.get('msisdn', ''),)
            ).fetchone()
            if existing:
                conn.execute("""
                    UPDATE accounts SET label=?, jsessionid=?, validation_key=?,
                        session_node=?, notes=?, is_active=?, session_ok=?
                    WHERE id=?
                """, (
                    data.get('label', ''), data.get('jsessionid'), data.get('validation_key'),
                    data.get('session_node'), data.get('notes'),
                    data.get('is_active', 1), data.get('session_ok', 0), existing['id'],
                ))
                return existing['id']
            cur = conn.execute("""
                INSERT INTO accounts (label, msisdn, jsessionid, validation_key, session_node,
                    notes, is_active, session_ok, created_at)
                VALUES (?,?,?,?,?,?,?,?,?)
            """, (
                data['label'], data.get('msisdn', ''), data.get('jsessionid'),
                data.get('validation_key'), data.get('session_node'), data.get('notes'),
                data.get('is_active', 1), data.get('session_ok', 0), now,
            ))
            return cur.lastrowid
def get_account(account_id: int) -> dict:
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            row = conn.execute("SELECT * FROM accounts WHERE id=?", (account_id,)).fetchone()
            return dict(row) if row else {}
def list_accounts_db() -> list:
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            rows = conn.execute("SELECT * FROM accounts ORDER BY id").fetchall()
            return [dict(r) for r in rows]
def update_account_session(account_id: int, jsessionid: str, validation_key: str, node: str = ''):
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            conn.execute("""
                UPDATE accounts SET jsessionid=?, validation_key=?, session_node=?, session_ok=1
                WHERE id=?
            """, (jsessionid, validation_key, node, account_id))
def update_account_storage(account_id: int, used: int, free: int):
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            conn.execute("""
                UPDATE accounts SET storage_used_bytes=?, storage_free_bytes=?, last_scan_at=?
                WHERE id=?
            """, (used, free, _now(), account_id))
def mark_account_scanned(account_id: int):
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            conn.execute("UPDATE accounts SET last_scan_at=? WHERE id=?", (_now(), account_id))
def add_api_key(provider: str, key: str, label: str = '') -> int:
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            try:
                cur = conn.execute("""
                    INSERT INTO api_keys (provider, api_key, label, added_at)
                    VALUES (?,?,?,?)
                """, (provider.lower(), key.strip(), label, _now()))
                return cur.lastrowid
            except sqlite3.IntegrityError:
                return 0
def get_next_api_key(provider: str) -> dict:
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            row = conn.execute("""
                SELECT * FROM api_keys
                WHERE provider=? AND is_active=1 AND is_dead=0
                ORDER BY COALESCE(last_used_at,0) ASC LIMIT 1
            """, (provider.lower(),)).fetchone()
            return dict(row) if row else {}
def mark_key_dead(key_id: int, error: str = ''):
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            conn.execute("""
                UPDATE api_keys SET is_dead=1, last_error=?, error_count=error_count+1 WHERE id=?
            """, (error, key_id))
def mark_key_used(key_id: int):
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            conn.execute("""
                UPDATE api_keys SET last_used_at=?, requests_today=requests_today+1 WHERE id=?
            """, (_now(), key_id))
def list_api_keys_db(provider: str = None) -> list:
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            if provider:
                rows = conn.execute(
                    "SELECT * FROM api_keys WHERE provider=? ORDER BY id", (provider,)
                ).fetchall()
            else:
                rows = conn.execute(
                    "SELECT * FROM api_keys ORDER BY provider, id"
                ).fetchall()
            return [dict(r) for r in rows]
def delete_api_key_db(key_id: int):
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            conn.execute("DELETE FROM api_keys WHERE id=?", (key_id,))
def toggle_api_key(key_id: int, active: bool):
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            conn.execute("UPDATE api_keys SET is_active=?, is_dead=0 WHERE id=?",
                         (1 if active else 0, key_id))
def log_scan(account_id: int, event: str, message: str):
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            conn.execute(
                "INSERT INTO scan_log (account_id, event, message, ts) VALUES (?,?,?,?)",
                (account_id, event, message, _now())
            )
def get_scan_log(account_id: int, limit: int = 200, after_ts: int = 0) -> list:
    ensure_setup()
    with _lock:
        with _get_conn() as conn:
            rows = conn.execute("""
                SELECT * FROM scan_log
                WHERE account_id=? AND ts > ?
                ORDER BY ts ASC LIMIT ?
            """, (account_id, after_ts, limit)).fetchall()
            return [dict(r) for r in rows]