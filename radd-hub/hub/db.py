"""Single SQLite database for the entire Hub.

Schema is the union of v2's flix ``uploads`` table and dbgen's
``titles``/``files``/``accounts`` tables, plus new tables for the
multi-key vault, mirror retry queue, and admin users.

The :func:`migrate_from_v2` function pulls data out of the two old
SQLite files (``radd_flix.db`` + ``radd_media.db``) without touching them.
"""
from __future__ import annotations
import sqlite3
import time
import threading
import json
import re
from pathlib import Path
from typing import Optional, Iterable
from . import config

_lock = threading.RLock()

SCHEMA_VERSION = 1


def _conn() -> sqlite3.Connection:
    config.ensure_dirs()
    c = sqlite3.connect(str(config.DB_PATH), check_same_thread=False, timeout=30.0)
    c.row_factory = sqlite3.Row
    c.execute("PRAGMA journal_mode=WAL")
    c.execute("PRAGMA foreign_keys=ON")
    c.execute("PRAGMA synchronous=NORMAL")
    return c


class _ConnCtx:
    """Context manager that commits (or rolls back) *and* closes the connection.

    ``sqlite3.Connection`` used bare as a context manager only handles
    transactions — it never closes the underlying file handle.  This wrapper
    adds the missing ``close()`` call so callers don't leak OS file descriptors.

    Usage (unchanged from before):
        with db.conn() as c:
            c.execute(...)
    """
    __slots__ = ("_c",)

    def __init__(self) -> None:
        self._c = _conn()

    def __enter__(self) -> sqlite3.Connection:
        return self._c

    def __exit__(self, exc_type, exc_val, exc_tb):
        try:
            if exc_type:
                self._c.rollback()
            else:
                self._c.commit()
        finally:
            self._c.close()
        return False


def conn() -> "_ConnCtx":
    return _ConnCtx()


# --------------------------------------------------------------------------- #
# Schema                                                                      #
# --------------------------------------------------------------------------- #

_DDL = [
    # ---- titles — master catalog (the single source of truth for all media)
    """CREATE TABLE IF NOT EXISTS titles (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        -- identity
        slug                TEXT UNIQUE,           -- url-safe: 'inception-2010'
        content_key         TEXT UNIQUE,           -- internal dedup key (legacy)
        -- external IDs
        tmdb_id             INTEGER,
        imdb_id             TEXT,                  -- e.g. 'tt1375666'
        -- core metadata
        media_type          TEXT,                  -- 'movie' | 'tv' | 'anime' | 'drama'
        title               TEXT,
        original_title      TEXT,
        year                TEXT,                  -- '2023'
        release_date        TEXT,                  -- '2023-12-22'
        language            TEXT,                  -- 'hindi'|'urdu'|'english'|'punjabi'|'pashto'|'sindhi'|'dual'
        country             TEXT,
        status              TEXT,                  -- 'released'|'ongoing'|'completed'|'cancelled'
        -- ratings
        rating              REAL,                  -- TMDB rating (0-10)
        imdb_rating         REAL,                  -- IMDB/OMDB rating (0-10)
        vote_count          INTEGER DEFAULT 0,
        -- descriptive
        genres              TEXT,                  -- JSON array: ["Action","Drama"]
        genres_csv          TEXT,                  -- legacy / fallback
        plot                TEXT,                  -- full description
        cast_json           TEXT,                  -- legacy cast JSON
        director            TEXT,
        crew_json           TEXT,
        languages_csv       TEXT,
        -- media specifics
        runtime             INTEGER,               -- minutes
        season_count        INTEGER,               -- for tv/anime
        episode_count       INTEGER,               -- total episodes
        -- external asset URLs (TMDB/OMDB)
        poster              TEXT,                  -- TMDB poster URL
        backdrop            TEXT,                  -- TMDB backdrop URL
        -- JazzDrive-hosted assets
        folder_share_url    TEXT,                  -- JazzDrive folder share link (used to generate download URLs)
        poster_share_url    TEXT,                  -- JazzDrive-hosted poster share URL
        backdrop_share_url  TEXT,                  -- JazzDrive-hosted backdrop
        trailer_url         TEXT,                  -- YouTube/external trailer URL
        -- source tracking
        account_number      TEXT,                  -- MSISDN of JazzDrive account e.g. '03001234567'
        industry            TEXT,                  -- 'hollywood'|'bollywood'|'lollywood'|'chinese'|...
        -- admin control
        is_published        INTEGER DEFAULT 0,     -- 0=processing  1=visible to users
        is_ready            INTEGER DEFAULT 1,     -- legacy
        confidence          INTEGER DEFAULT 0,     -- 0-100: metadata completeness score
        -- timestamps
        created_at          INTEGER,
        updated_at          INTEGER
    )""",
    "CREATE INDEX IF NOT EXISTS idx_titles_tmdb    ON titles(tmdb_id)",
    "CREATE INDEX IF NOT EXISTS idx_titles_year    ON titles(year)",
    "CREATE INDEX IF NOT EXISTS idx_titles_title   ON titles(title)",
    # NOTE: idx_titles_slug / idx_titles_pub / idx_titles_imdb are created in the
    # migrations block of init_db() because those columns may not exist yet on older DBs.

    # ---- files (every file from EITHER source)
    """CREATE TABLE IF NOT EXISTS files (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        fingerprint         TEXT UNIQUE NOT NULL,
        title_id            INTEGER,
        source              TEXT NOT NULL,        -- 'scan' | 'upload'
        account_id          INTEGER,              -- jazzdrive account if scan/upload
        filename            TEXT NOT NULL,
        local_path          TEXT,
        media_kind          TEXT,                 -- movie/series/season/episode/other
        season              INTEGER,
        episode             INTEGER,
        size_bytes          INTEGER DEFAULT 0,
        quality             TEXT,
        remote_id           TEXT,
        remote_folder_id    TEXT,
        remote_file_id      TEXT,
        folder_path         TEXT,
        share_url           TEXT,
        share_key           TEXT,
        share_link_id       TEXT,
        share_folder_id     TEXT,
        download_url        TEXT,
        uploaded_at         INTEGER,
        scanned_at          INTEGER,
        is_ready            INTEGER DEFAULT 1,
        github_status       TEXT,                 -- 'ok' | 'failed' | 'pending' | NULL
        github_synced_at    INTEGER,
        gsheets_status      TEXT,
        gsheets_synced_at   INTEGER,
        raw_json            TEXT,
        FOREIGN KEY (title_id) REFERENCES titles(id) ON DELETE SET NULL
    )""",
    "CREATE INDEX IF NOT EXISTS idx_files_title    ON files(title_id)",
    "CREATE INDEX IF NOT EXISTS idx_files_source   ON files(source)",
    "CREATE INDEX IF NOT EXISTS idx_files_account  ON files(account_id)",
    "CREATE INDEX IF NOT EXISTS idx_files_remote   ON files(remote_id)",
    "CREATE INDEX IF NOT EXISTS idx_files_share    ON files(share_folder_id)",
    "CREATE INDEX IF NOT EXISTS idx_files_filename ON files(filename)",

    # ---- jazzdrive accounts
    """CREATE TABLE IF NOT EXISTS accounts (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        msisdn            TEXT UNIQUE NOT NULL,
        label             TEXT,
        notes             TEXT,
        validation_key    TEXT,
        jsessionid        TEXT,
        node              TEXT,
        refresh_token     TEXT,
        token_expires_at  INTEGER,
        last_scan_at      INTEGER,
        last_keepalive_at INTEGER,
        is_active         INTEGER DEFAULT 1,
        role              TEXT    DEFAULT 'flix',
        created_at        INTEGER
    )""",

    # ---- multi-key vault
    """CREATE TABLE IF NOT EXISTS keys (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        provider        TEXT NOT NULL,
        label           TEXT,
        value_enc       BLOB NOT NULL,
        is_active       INTEGER DEFAULT 1,
        exhausted_until INTEGER DEFAULT 0,
        failure_count   INTEGER DEFAULT 0,
        total_uses      INTEGER DEFAULT 0,
        last_used_at    INTEGER,
        last_status     TEXT,
        created_at      INTEGER,
        updated_at      INTEGER
    )""",
    "CREATE INDEX IF NOT EXISTS idx_keys_provider ON keys(provider, is_active)",

    # ---- mirror retry queue / log
    """CREATE TABLE IF NOT EXISTS mirror_log (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        target        TEXT NOT NULL,            -- 'github' | 'gsheets'
        action        TEXT NOT NULL,            -- 'push_entry' | 'push_full'
        ref           TEXT,                     -- file_id / title_id
        payload       TEXT,                     -- json
        status        TEXT DEFAULT 'pending',   -- pending | ok | failed
        attempts      INTEGER DEFAULT 0,
        last_error    TEXT,
        next_retry_at INTEGER,
        created_at    INTEGER,
        updated_at    INTEGER
    )""",
    "CREATE INDEX IF NOT EXISTS idx_mirror_pending ON mirror_log(status, next_retry_at)",

    # ---- download queue
    """CREATE TABLE IF NOT EXISTS queue (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        job_id        TEXT UNIQUE,
        movie         TEXT,
        site          TEXT,
        status        TEXT,
        progress      REAL DEFAULT 0,
        message       TEXT,
        url           TEXT,
        dest          TEXT,
        log           TEXT,
        created_at    INTEGER,
        updated_at    INTEGER
    )""",

    # ---- scan log per account
    """CREATE TABLE IF NOT EXISTS scan_log (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id  INTEGER,
        kind        TEXT,
        message     TEXT,
        ts          INTEGER
    )""",
    "CREATE INDEX IF NOT EXISTS idx_scan_log_acct ON scan_log(account_id, ts)",

    # ---- users
    """CREATE TABLE IF NOT EXISTS users (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        username    TEXT UNIQUE,
        role        TEXT,
        quota       INTEGER DEFAULT 0,
        created_at  INTEGER
    )""",

    # ---- generic settings k/v
    """CREATE TABLE IF NOT EXISTS settings (
        k TEXT PRIMARY KEY,
        v TEXT
    )""",

    # ---- recommendation cache
    """CREATE TABLE IF NOT EXISTS recommendation_cache (
        seed_tmdb_id  INTEGER,
        media_type    TEXT,
        payload_json  TEXT,
        fetched_at    INTEGER,
        PRIMARY KEY (seed_tmdb_id, media_type)
    )""",

    # ---- quality upgrade subscriptions
    """CREATE TABLE IF NOT EXISTS quality_upgrade_subscriptions (
        user_jid      TEXT,
        fingerprint   TEXT,
        current_q     TEXT,
        target_q      TEXT,
        notified_at   INTEGER,
        created_at    INTEGER DEFAULT (strftime('%s','now')),
        PRIMARY KEY (user_jid, fingerprint)
    )""",

    # ---- bot status index (jobs bots are watching; used by quality-upgrade notifier)
    """CREATE TABLE IF NOT EXISTS bot_status_index (
        fingerprint   TEXT PRIMARY KEY,
        user_jid      TEXT,
        title         TEXT,
        state         TEXT,
        progress_pct  REAL DEFAULT 0,
        detail        TEXT,
        updated_at    INTEGER DEFAULT (strftime('%s','now')),
        created_at    INTEGER DEFAULT (strftime('%s','now'))
    )""",
    "CREATE INDEX IF NOT EXISTS idx_bot_status_user ON bot_status_index(user_jid, state)",

    # ---- rate limit log (per-user request timestamps for bot throttling)
    """CREATE TABLE IF NOT EXISTS rate_limit_log (
        id       INTEGER PRIMARY KEY AUTOINCREMENT,
        user_jid TEXT NOT NULL,
        ts       INTEGER NOT NULL
    )""",
    "CREATE INDEX IF NOT EXISTS idx_rate_limit_ts   ON rate_limit_log(ts)",
    "CREATE INDEX IF NOT EXISTS idx_rate_limit_user ON rate_limit_log(user_jid, ts)",

    # ---- stream_links — time-limited playable download URLs (expires every 4-6 h)
    """CREATE TABLE IF NOT EXISTS stream_links (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        file_id         INTEGER NOT NULL,
        download_url    TEXT NOT NULL,
        generated_at    INTEGER NOT NULL,
        expires_at      INTEGER NOT NULL,    -- epoch; regenerate before this
        is_valid        INTEGER DEFAULT 1,   -- 0 = manually invalidated
        account_id      INTEGER,             -- which JazzDrive account generated it
        request_count   INTEGER DEFAULT 0,   -- times served to users
        bytes_served    INTEGER DEFAULT 0,   -- bytes served through this link
        last_served_at  INTEGER,
        FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE
    )""",
    "CREATE INDEX IF NOT EXISTS idx_stream_file    ON stream_links(file_id, is_valid, expires_at)",

    # ---- plans — subscription tiers (monthly/daily limits)
    """CREATE TABLE IF NOT EXISTS plans (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        name             TEXT NOT NULL,      -- 'Basic' | 'Premium' | 'Unlimited'
        price_pkr        INTEGER DEFAULT 0,
        daily_limit_gb   REAL    DEFAULT 0,  -- 0 = unlimited
        monthly_limit_gb REAL    DEFAULT 0,  -- 0 = unlimited
        max_devices      INTEGER DEFAULT 1,
        duration_days    INTEGER DEFAULT 30,
        description      TEXT,
        is_active        INTEGER DEFAULT 1,
        created_at       INTEGER
    )""",

    # ---- user_subscriptions — who has which plan
    """CREATE TABLE IF NOT EXISTS user_subscriptions (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        user_jid         TEXT NOT NULL,
        plan_id          INTEGER,
        started_at       INTEGER,
        expires_at       INTEGER,
        is_active        INTEGER DEFAULT 1,
        bytes_used_total INTEGER DEFAULT 0,
        FOREIGN KEY (plan_id) REFERENCES plans(id)
    )""",
    "CREATE INDEX IF NOT EXISTS idx_sub_jid ON user_subscriptions(user_jid, is_active)",

    # ---- user_usage — daily data usage per WhatsApp JID
    """CREATE TABLE IF NOT EXISTS user_usage (
        user_jid       TEXT NOT NULL,
        date           TEXT NOT NULL,   -- 'YYYY-MM-DD'
        bytes_used     INTEGER DEFAULT 0,
        requests_count INTEGER DEFAULT 0,
        last_active_at INTEGER,
        PRIMARY KEY (user_jid, date)
    )""",
    "CREATE INDEX IF NOT EXISTS idx_usage_jid ON user_usage(user_jid, date)",

    # ---- app_users — RaddFlix Android app subscriber accounts
    """CREATE TABLE IF NOT EXISTS app_users (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        phone           TEXT UNIQUE NOT NULL,
        password_hash   TEXT NOT NULL,
        device_id       TEXT,
        device_name     TEXT,
        device_bound_at INTEGER,
        is_active       INTEGER DEFAULT 1,
        created_at      INTEGER DEFAULT (strftime('%s','now')),
        last_login_at   INTEGER,
        is_admin        INTEGER DEFAULT 0
    )""",
    "CREATE INDEX IF NOT EXISTS idx_app_users_phone ON app_users(phone)",

    # ---- app_subscriptions — which plan each app user is on
    """CREATE TABLE IF NOT EXISTS app_subscriptions (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id     INTEGER NOT NULL REFERENCES app_users(id),
        plan        TEXT NOT NULL DEFAULT 'free',
        started_at  INTEGER,
        expires_at  INTEGER,
        is_active   INTEGER DEFAULT 1,
        created_at  INTEGER DEFAULT (strftime('%s','now'))
    )""",
    "CREATE INDEX IF NOT EXISTS idx_app_subs_user ON app_subscriptions(user_id, is_active)",

    # ---- tid_payments — manual TID payment verification queue
    """CREATE TABLE IF NOT EXISTS tid_payments (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id        INTEGER REFERENCES app_users(id),
        phone          TEXT NOT NULL,
        amount_pkr     INTEGER NOT NULL,
        tid            TEXT NOT NULL,
        payment_method TEXT DEFAULT 'jazzcash',
        plan           TEXT NOT NULL,
        status         TEXT DEFAULT 'pending',
        admin_note     TEXT,
        submitted_at   INTEGER DEFAULT (strftime('%s','now')),
        reviewed_at    INTEGER,
        reviewed_by    TEXT
    )""",
    "CREATE INDEX IF NOT EXISTS idx_tid_status ON tid_payments(status, submitted_at)",
    "CREATE INDEX IF NOT EXISTS idx_tid_user   ON tid_payments(user_id)",

    # ---- app_refresh_tokens — JWT refresh token store
    """CREATE TABLE IF NOT EXISTS app_refresh_tokens (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id     INTEGER NOT NULL REFERENCES app_users(id),
        token_hash  TEXT UNIQUE NOT NULL,
        device_id   TEXT,
        created_at  INTEGER DEFAULT (strftime('%s','now')),
        expires_at  INTEGER,
        revoked     INTEGER DEFAULT 0
    )""",
    "CREATE INDEX IF NOT EXISTS idx_refresh_token ON app_refresh_tokens(token_hash)",
    "CREATE INDEX IF NOT EXISTS idx_refresh_user  ON app_refresh_tokens(user_id, revoked)",

    # ---- turbo_cache — lightning fast search/link lookups
    """CREATE TABLE IF NOT EXISTS turbo_cache (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        query       TEXT,
        site        TEXT,
        cat         TEXT, -- 'search' | 'links'
        data        TEXT, -- JSON data
        expires_at  INTEGER,
        UNIQUE(query, site, cat)
    )""",
    # ---- media_index — high-speed canonical deduplication
    """CREATE TABLE IF NOT EXISTS media_index (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        title_id            INTEGER,
        normalized_title    TEXT,
        season              INTEGER,
        episode             INTEGER,
        quality             TEXT,
        file_id             INTEGER,
        created_at          INTEGER,
        UNIQUE(normalized_title, season, episode, quality)
    )""",
    "CREATE INDEX IF NOT EXISTS idx_media_idx_lookup ON media_index(normalized_title, season, episode)",
    # ── watch_history — per-user per-file resume position (Phase 5)
    """CREATE TABLE IF NOT EXISTS watch_history (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id     INTEGER NOT NULL REFERENCES app_users(id),
        file_id     TEXT NOT NULL,
        position_ms INTEGER DEFAULT 0,
        duration_ms INTEGER DEFAULT 0,
        watched_at  INTEGER DEFAULT (strftime('%s','now')),
        UNIQUE(user_id, file_id)
    )""",
    "CREATE INDEX IF NOT EXISTS idx_watch_history_user ON watch_history(user_id, watched_at)",
    # BUG-S11 fix: ensure UNIQUE constraint exists on migrated DBs (pre-constraint tables won't have it)
    """CREATE UNIQUE INDEX IF NOT EXISTS idx_watch_history_unique
       ON watch_history(user_id, file_id)""",
    # ── notifications — push notification inbox (Phase 9)
    """CREATE TABLE IF NOT EXISTS notifications (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id     INTEGER REFERENCES app_users(id),
        title       TEXT NOT NULL,
        body        TEXT,
        image_url   TEXT,
        action_url  TEXT,
        is_read     INTEGER DEFAULT 0,
        created_at  INTEGER DEFAULT (strftime('%s','now'))
    )""",
    "CREATE INDEX IF NOT EXISTS idx_notif_user ON notifications(user_id, created_at)",
    # ── payment_methods — admin-configurable gateways (Phase 8)
    """CREATE TABLE IF NOT EXISTS payment_methods (
        id                   INTEGER PRIMARY KEY AUTOINCREMENT,
        code                 TEXT UNIQUE NOT NULL,
        name                 TEXT NOT NULL,
        icon                 TEXT DEFAULT '💳',
        account_number       TEXT,
        account_name         TEXT,
        instructions         TEXT,
        is_enabled           INTEGER DEFAULT 1,
        sort_order           INTEGER DEFAULT 0,
        min_amount_pkr       REAL DEFAULT 0,
        amount_tolerance_pkr REAL DEFAULT 10,
        updated_at           INTEGER
    )""",
    # ── SMS payment receipts — incoming SMS matched to TID submissions ────────
    """CREATE TABLE IF NOT EXISTS received_sms_payments (
        id                 INTEGER PRIMARY KEY AUTOINCREMENT,
        source             TEXT NOT NULL DEFAULT 'unknown',
        tid                TEXT,
        amount_pkr         REAL,
        sender_phone       TEXT,
        raw_sms            TEXT,
        received_at        INTEGER NOT NULL DEFAULT (strftime('%s','now')),
        matched_payment_id INTEGER
    )""",
    """CREATE INDEX IF NOT EXISTS idx_sms_received_at
       ON received_sms_payments(received_at DESC)""",
    """CREATE INDEX IF NOT EXISTS idx_sms_matched
       ON received_sms_payments(matched_payment_id)""",
    # ── App signature allowlist (settings → app-version page) ────────────────
    """CREATE TABLE IF NOT EXISTS app_signatures (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        sig_hash    TEXT UNIQUE NOT NULL,
        label       TEXT DEFAULT '',
        is_allowed  INTEGER DEFAULT 1,
        note        TEXT DEFAULT '',
        created_at  INTEGER DEFAULT (strftime('%s','now'))
    )""",
    # ── Security telemetry (Phase 25.6) ─────────────────────────────────────
    """CREATE TABLE IF NOT EXISTS tamper_reports (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        device_hash TEXT NOT NULL,
        reason      TEXT NOT NULL DEFAULT 'unknown',
        reported_at INTEGER NOT NULL DEFAULT 0,
        app_version TEXT,
        is_rooted   INTEGER DEFAULT 0,
        ip_addr     TEXT
    )""",
    """CREATE INDEX IF NOT EXISTS idx_tamper_reports_device
       ON tamper_reports(device_hash)""",
    """CREATE INDEX IF NOT EXISTS idx_tamper_reports_ts
       ON tamper_reports(reported_at DESC)""",

    # ── FTS5 full-text search — titles_fts content table (P2.1) ─────────────────
    # Content-based FTS5: reads data from 'titles' on demand (no duplication).
    # Kept in sync by the three triggers below.
    """CREATE VIRTUAL TABLE IF NOT EXISTS titles_fts USING fts5(
        title, plot, genres, language,
        content='titles', content_rowid='id',
        tokenize='unicode61 remove_diacritics 1'
    )""",
    """CREATE TRIGGER IF NOT EXISTS titles_ai AFTER INSERT ON titles BEGIN
       INSERT INTO titles_fts(rowid, title, plot, genres, language)
       VALUES (new.id, new.title, new.plot, new.genres, new.language);
    END""",
    """CREATE TRIGGER IF NOT EXISTS titles_ad AFTER DELETE ON titles BEGIN
       INSERT INTO titles_fts(titles_fts, rowid, title, plot, genres, language)
       VALUES ('delete', old.id, old.title, old.plot, old.genres, old.language);
    END""",
    """CREATE TRIGGER IF NOT EXISTS titles_au AFTER UPDATE ON titles BEGIN
       INSERT INTO titles_fts(titles_fts, rowid, title, plot, genres, language)
       VALUES ('delete', old.id, old.title, old.plot, old.genres, old.language);
       INSERT INTO titles_fts(rowid, title, plot, genres, language)
       VALUES (new.id, new.title, new.plot, new.genres, new.language);
    END""",
]


def init_db() -> None:
    with _lock, _conn() as c:
        for stmt in _DDL:
            c.execute(stmt)
        c.execute("INSERT OR IGNORE INTO settings(k,v) VALUES('schema_version', ?)",
                  (str(SCHEMA_VERSION),))
        # safe migrations — add columns that may be missing from older DBs
        for migration_sql in [
            # accounts
            "ALTER TABLE accounts ADD COLUMN role TEXT DEFAULT 'flix'",
            "ALTER TABLE accounts ADD COLUMN refresh_token TEXT",
            "ALTER TABLE accounts ADD COLUMN raw_accesstoken TEXT",
            # titles — new columns
            "ALTER TABLE titles ADD COLUMN slug TEXT",
            "ALTER TABLE titles ADD COLUMN imdb_id TEXT",
            "ALTER TABLE titles ADD COLUMN language TEXT",
            "ALTER TABLE titles ADD COLUMN release_date TEXT",
            "ALTER TABLE titles ADD COLUMN country TEXT",
            "ALTER TABLE titles ADD COLUMN status TEXT",
            "ALTER TABLE titles ADD COLUMN imdb_rating REAL",
            "ALTER TABLE titles ADD COLUMN genres TEXT",
            "ALTER TABLE titles ADD COLUMN plot TEXT",
            "ALTER TABLE titles ADD COLUMN season_count INTEGER",
            "ALTER TABLE titles ADD COLUMN episode_count INTEGER",
            "ALTER TABLE titles ADD COLUMN folder_share_url TEXT",
            "ALTER TABLE titles ADD COLUMN poster_share_url TEXT",
            "ALTER TABLE titles ADD COLUMN backdrop_share_url TEXT",
            "ALTER TABLE titles ADD COLUMN trailer_url TEXT",
            "ALTER TABLE titles ADD COLUMN account_number TEXT",
            "ALTER TABLE titles ADD COLUMN industry TEXT",
            "ALTER TABLE titles ADD COLUMN is_published INTEGER DEFAULT 0",
            "ALTER TABLE titles ADD COLUMN confidence INTEGER DEFAULT 0",
            "ALTER TABLE titles ADD COLUMN is_ongoing INTEGER DEFAULT 0",
            "ALTER TABLE titles ADD COLUMN poster_url TEXT",
            "ALTER TABLE queue ADD COLUMN poster_url TEXT",
            "ALTER TABLE titles ADD COLUMN is_free INTEGER DEFAULT 0",
            "ALTER TABLE queue ADD COLUMN is_ongoing INTEGER DEFAULT 0",
            # indexes for new columns (IF NOT EXISTS handles re-runs)
            "CREATE INDEX IF NOT EXISTS idx_titles_slug ON titles(slug)",
            "CREATE INDEX IF NOT EXISTS idx_titles_pub  ON titles(is_published, media_type)",
            "CREATE INDEX IF NOT EXISTS idx_titles_imdb ON titles(imdb_id)",
            # FTS5 index rebuild — populates titles_fts for all existing rows
            # (no-op if already populated; safe to re-run)
            "ALTER TABLE plans ADD COLUMN badge TEXT",
            "ALTER TABLE plans ADD COLUMN color TEXT",
            "ALTER TABLE plans ADD COLUMN features_json TEXT",
            # app_users — mobile app admin flag (gates "Server Downloads" in-app)
            "ALTER TABLE app_users ADD COLUMN is_admin INTEGER DEFAULT 0",
            "INSERT INTO titles_fts(titles_fts) VALUES('rebuild')",
            # P3.5 cleanup — drop legacy/duplicate columns from titles.
            # Order matters: drop triggers first so SQLite allows DROP COLUMN;
            # then recreate FTS5 table + triggers without cast_names.
            # Requires SQLite 3.35.0+ (Ubuntu 22.04 ships 3.37.2 — safe).
            # All wrapped in try/except via the migration loop — idempotent.
            "DROP TRIGGER IF EXISTS titles_ai",
            "DROP TRIGGER IF EXISTS titles_ad",
            "DROP TRIGGER IF EXISTS titles_au",
            "DROP TABLE IF EXISTS titles_fts",
            "ALTER TABLE titles DROP COLUMN omdb_id",
            "ALTER TABLE titles DROP COLUMN overview",
            "ALTER TABLE titles DROP COLUMN cast",
            "ALTER TABLE titles DROP COLUMN cast_names",
            # Recreate FTS5 virtual table without cast_names
            "CREATE VIRTUAL TABLE IF NOT EXISTS titles_fts USING fts5(title, plot, genres, language, content=\'titles\', content_rowid=\'id\', tokenize=\'unicode61 remove_diacritics 1\')",
            # Recreate sync triggers without cast_names
            "CREATE TRIGGER IF NOT EXISTS titles_ai AFTER INSERT ON titles BEGIN INSERT INTO titles_fts(rowid, title, plot, genres, language) VALUES (new.id, new.title, new.plot, new.genres, new.language); END",
            "CREATE TRIGGER IF NOT EXISTS titles_ad AFTER DELETE ON titles BEGIN INSERT INTO titles_fts(titles_fts, rowid, title, plot, genres, language) VALUES (\'delete\', old.id, old.title, old.plot, old.genres, old.language); END",
            "CREATE TRIGGER IF NOT EXISTS titles_au AFTER UPDATE ON titles BEGIN INSERT INTO titles_fts(titles_fts, rowid, title, plot, genres, language) VALUES (\'delete\', old.id, old.title, old.plot, old.genres, old.language); INSERT INTO titles_fts(rowid, title, plot, genres, language) VALUES (new.id, new.title, new.plot, new.genres, new.language); END",
            # Rebuild FTS5 index after recreation
            "INSERT INTO titles_fts(titles_fts) VALUES(\'rebuild\')",
            # ── payment_methods — columns added after initial schema deploy ──
            "ALTER TABLE payment_methods ADD COLUMN icon TEXT DEFAULT '💳'",
            "ALTER TABLE payment_methods ADD COLUMN account_name TEXT",
            "ALTER TABLE payment_methods ADD COLUMN min_amount_pkr REAL DEFAULT 0",
            "ALTER TABLE payment_methods ADD COLUMN amount_tolerance_pkr REAL DEFAULT 10",
            "ALTER TABLE payment_methods ADD COLUMN updated_at INTEGER",
        ]:
            try:
                c.execute(migration_sql)
            except Exception:
                pass  # column/index already exists, or FTS5 not compiled in SQLite

    # ── Seed default payment methods if table is empty ───────────────────────
    _default_methods = [
        ('easypaisa', 'EasyPaisa', '💚', 0),
        ('jazzcash',  'JazzCash',  '🔴', 1),
        ('nayapay',   'NayaPay',   '🟡', 2),
        ('sadapay',   'SadaPay',   '⚫', 3),
    ]
    with _lock, _conn() as c:
        for code, name, icon, sort in _default_methods:
            c.execute(
                "INSERT OR IGNORE INTO payment_methods(code, name, icon, sort_order) VALUES(?,?,?,?)",
                (code, name, icon, sort)
            )
        # Generate sms_gateway_key on first boot if not already set
        gk = c.execute("SELECT v FROM settings WHERE k='sms_gateway_key'").fetchone()
        if not gk:
            import secrets as _sec
            c.execute("INSERT OR IGNORE INTO settings(k,v) VALUES('sms_gateway_key',?)",
                      (_sec.token_hex(24),))

    # ── Seed default subscription plans if table is empty ───────────────────
    # These match the hardcoded fallback in mobile_api.py /api/subscription/plans.
    # Once seeded the admin can edit/add/remove plans freely via /plans/.
    import json as _json
    _default_plans = [
        ("Starter",  150, 10.0,  1, 30, "#D4784A",
         _json.dumps(["Zero-data streaming", "HD quality", "All content"]),           ""),
        ("Basic",    250, 30.0,  1, 30, "#7C5CFF",
         _json.dumps(["Zero-data streaming", "HD 720p quality", "All content"]),      "POPULAR"),
        ("Standard", 400, 60.0,  1, 30, "#2563EB",
         _json.dumps(["Zero-data streaming", "Full HD 1080p", "All content"]),        "BEST VALUE"),
        ("Premium",  700, 100.0, 2, 30, "#22C55E",
         _json.dumps(["Zero-data streaming", "Full HD 1080p", "All content", "2 devices"]), ""),
    ]
    with _lock, _conn() as c:
        existing = c.execute("SELECT COUNT(*) AS n FROM plans").fetchone()["n"]
        if existing == 0:
            _now = int(time.time())
            for _name, _price, _gb, _devs, _days, _color, _feats, _badge in _default_plans:
                c.execute(
                    """INSERT OR IGNORE INTO plans
                       (name,price_pkr,monthly_limit_gb,max_devices,duration_days,
                        color,features_json,badge,is_active,created_at)
                       VALUES(?,?,?,?,?,?,?,?,1,?)""",
                    (_name, _price, _gb, _devs, _days, _color, _feats, _badge, _now)
                )

    # Run schema check at startup — logs WARNING for any missing critical columns.
    validate_schema()




# --------------------------------------------------------------------------- #
# Schema health check                                                         #
# --------------------------------------------------------------------------- #

# Every table -> list of columns that MUST exist for the app to work correctly.
# Derived from full A-Z audit of all 27 admin-panel route files (2026-06-08).
_CRITICAL_SCHEMA = {
    "app_subscriptions": [
        "is_active",
        "expires_at", "plan", "user_id", "started_at", "created_at",
    ],
    "app_users": [
        "id", "phone", "is_active", "created_at",
        "device_id", "device_name", "last_login_at", "is_admin",
    ],
    "titles": [
        "is_published", "updated_at", "media_type",
        "poster", "slug", "is_free", "rating", "language",
        "genres", "plot", "folder_share_url", "poster_share_url",
    ],
    "files": [
        "is_ready", "share_url", "title_id",
        "season", "episode", "filename", "size_bytes", "fingerprint",
    ],
    "tid_payments": [
        "status", "plan", "user_id", "phone",
        "amount_pkr", "tid", "payment_method", "submitted_at", "reviewed_at",
    ],
    "accounts": [
        "is_active", "msisdn", "validation_key", "jsessionid",
        "token_expires_at", "role", "refresh_token",
    ],
    "settings": ["k", "v"],
    "plans": [
        "is_active", "price_pkr", "name",
        "duration_days", "max_devices", "description",
        "badge", "color", "features_json",
    ],
    "queue": [
        "job_id", "movie", "site", "status", "created_at", "updated_at",
    ],
}


# Returns: {ok, issue_count, issues, checks, checked_at}
# Logs WARNING per missing item so problems appear in supervisord logs at startup.
def validate_schema():
    import time as _time
    import logging as _logging
    _log = _logging.getLogger("hub.db.schema")

    issues = []
    checks = {}

    with _conn() as c:
        tables_raw = c.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        ).fetchall()
        existing_tables = {r["name"] for r in tables_raw}

        col_cache = {}
        for tbl in existing_tables:
            try:
                rows = c.execute('PRAGMA table_info("%s")' % tbl).fetchall()
                col_cache[tbl] = {r["name"] for r in rows}
            except Exception:
                col_cache[tbl] = set()

    ts = int(_time.time())

    for table, columns in _CRITICAL_SCHEMA.items():
        if table not in existing_tables:
            msg = "MISSING TABLE %s" % table
            issues.append(msg)
            _log.warning("schema-check: %s", msg)
            for col in columns:
                checks["%s.%s" % (table, col)] = False
            continue

        for col in columns:
            key = "%s.%s" % (table, col)
            ok  = col in col_cache.get(table, set())
            checks[key] = ok
            if not ok:
                msg = "MISSING COLUMN %s" % key
                issues.append(msg)
                _log.warning("schema-check: %s", msg)

    result = {
        "ok":          len(issues) == 0,
        "issue_count": len(issues),
        "issues":      issues,
        "checks":      checks,
        "checked_at":  ts,
    }
    if issues:
        _log.warning("schema-check: %d issue(s) found", len(issues))
    else:
        _log.info("schema-check: all %d critical columns OK", len(checks))
    return result

# --------------------------------------------------------------------------- #
# Generic helpers                                                             #
# --------------------------------------------------------------------------- #

def setting(k: str, default: Optional[str] = None) -> Optional[str]:
    with _conn() as c:
        r = c.execute("SELECT v FROM settings WHERE k=?", (k,)).fetchone()
        return r["v"] if r else default

def set_setting(k: str, v: str) -> None:
    with _lock, _conn() as c:
        c.execute("INSERT INTO settings(k,v) VALUES(?,?) "
                  "ON CONFLICT(k) DO UPDATE SET v=excluded.v", (k, v))


# --------------------------------------------------------------------------- #
# Title / file upserts                                                         #
# --------------------------------------------------------------------------- #

def _enrich_title(row: Optional[sqlite3.Row]) -> Optional[dict]:
    if not row:
        return None
    d = dict(row)
    # Prioritize zero-rated JazzDrive assets if they exist
    # v3.1: Redirect through /library/api/poster to generate direct links
    if d.get("poster_share_url"):
        d["poster"] = f"/library/api/poster/{d['id']}"
    return d

def get_title(title_id: int) -> Optional[dict]:
    with _conn() as c:
        r = c.execute("SELECT * FROM titles WHERE id=?", (title_id,)).fetchone()
        return _enrich_title(r)

def upsert_title(meta: dict) -> Optional[int]:
    """Insert or update a title row.  Auto-generates slug and confidence if missing."""
    if not meta:
        return None
    now = int(time.time())

    # Auto-generate slug from title+year if not supplied
    if not meta.get("slug") and meta.get("title"):
        try:
            from .metadata import slug_from as _slug_from
            meta = dict(meta)
            meta["slug"] = _slug_from(meta["title"], meta.get("year"))
        except Exception:
            pass

    # Auto-compute confidence if not supplied
    if not meta.get("confidence"):
        try:
            from .metadata import confidence_score as _cs
            meta = dict(meta) if not isinstance(meta, dict) else meta
            meta["confidence"] = _cs(meta)
        except Exception:
            pass

    cols = [
        "content_key","slug","tmdb_id","imdb_id",
        "media_type","title","original_title","year","release_date",
        "language","country","status",
        "rating","imdb_rating","vote_count",
        "genres","genres_csv","plot","cast_json",
        "director","crew_json","languages_csv",
        "runtime","season_count","episode_count",
        "poster","backdrop",
        "folder_share_url","poster_share_url","backdrop_share_url","trailer_url",
        "account_number","industry","is_published","confidence",
    ]

    vals = []
    for c_ in cols:
        v = meta.get(c_)
        if c_ == "genres" and isinstance(v, list):
            v = json.dumps(v)
        vals.append(v)

    with _lock, _conn() as c:
        # Lookup by content_key → slug → tmdb_id → title+year+media_type
        ck = meta.get("content_key")
        sl = meta.get("slug")
        ti = meta.get("tmdb_id")
        tv = meta.get("title")
        yr = meta.get("year")
        mt = meta.get("media_type")
        existing = None
        if ck:
            existing = c.execute("SELECT id FROM titles WHERE content_key=?", (ck,)).fetchone()
        if not existing and sl:
            existing = c.execute("SELECT id FROM titles WHERE slug=?", (sl,)).fetchone()
        if not existing and ti:
            existing = c.execute("SELECT id FROM titles WHERE tmdb_id=?", (ti,)).fetchone()
        # Fallback: match by normalised title + year + media_type to prevent
        # re-enrich from inserting duplicate rows for titles that have no
        # content_key/slug/tmdb_id yet (e.g. scanner-only titles).
        if not existing and tv and yr and mt:
            existing = c.execute(
                "SELECT id FROM titles WHERE LOWER(TRIM(title))=LOWER(TRIM(?)) AND year=? AND media_type=?",
                (tv, yr, mt)
            ).fetchone()
        if existing:
            tid = existing["id"]
            # Only overwrite non-null incoming values
            sets, update_vals = [], []
            for col, val in zip(cols, vals):
                if val is not None and val != "":
                    sets.append(f"{col}=?")
                    update_vals.append(val)
            if sets:
                c.execute(
                    f"UPDATE titles SET {', '.join(sets)}, updated_at=? WHERE id=?",
                    tuple(update_vals) + (now, tid)
                )
            return tid
        cur = c.execute(
            "INSERT INTO titles(" + ",".join(cols) + ",created_at,updated_at) VALUES("
            + ",".join("?" * len(cols)) + ",?,?)",
            tuple(vals) + (now, now)
        )
        return cur.lastrowid


def find_file_by_name(filename: str, size: int = 0) -> Optional[dict]:
    """Return a file record if it already exists and is ready."""
    with conn() as c:
        if size > 0:
            # Allow 1% size variance for different sources
            low, high = int(size * 0.99), int(size * 1.01)
            row = c.execute(
                "SELECT * FROM files WHERE filename=? AND size_bytes BETWEEN ? AND ? "
                "AND is_ready=1 LIMIT 1", (filename, low, high)
            ).fetchone()
        else:
            row = c.execute(
                "SELECT * FROM files WHERE filename=? AND is_ready=1 LIMIT 1",
                (filename,)
            ).fetchone()
        return dict(row) if row else None


def upsert_file(rec: dict) -> Optional[int]:
    if not rec or not rec.get("fingerprint"):
        return None
    now = int(time.time())
    rec.setdefault("scanned_at" if rec.get("source") == "scan" else "uploaded_at", now)
    rec.setdefault("is_ready", 1)  # scanned files are ready by default
    cols = ["fingerprint","title_id","source","account_id","filename","local_path",
            "media_kind","season","episode","size_bytes","quality","remote_id",
            "remote_folder_id","remote_file_id","folder_path","share_url","share_key",
            "share_link_id","share_folder_id","download_url","uploaded_at","scanned_at",
            "is_ready","raw_json"]
    vals = []
    for c_ in cols:
        v = rec.get(c_)
        if c_ == "raw_json" and isinstance(v, (dict, list)):
            v = json.dumps(v)
        vals.append(v)
    with _lock, _conn() as c:
        existing = c.execute("SELECT id FROM files WHERE fingerprint=?", (rec["fingerprint"],)).fetchone()
        if existing:
            fid = existing["id"]
            sets = []
            update_vals = []
            for col, val in zip(cols, vals):
                if val is not None:
                    sets.append(f"{col}=?")
                    update_vals.append(val)
            if sets:
                c.execute(f"UPDATE files SET {', '.join(sets)} WHERE id=?",
                          tuple(update_vals) + (fid,))
            return fid
        cur = c.execute("INSERT INTO files(" + ",".join(cols) + ") VALUES(" +
                        ",".join("?" * len(cols)) + ")", tuple(vals))
        fid = cur.lastrowid
        
    # Async-like indexing (done outside lock if possible, but here we just call it)
    try:
        index_media_file(fid)
    except:
        pass
        
    return fid


def update_file(file_id: int, data: dict) -> None:
    """Partially update a file row."""
    if not data or not file_id:
        return
    sets: list[str] = []
    vals: list = []
    for k, v in data.items():
        if v is not None and k not in ("id",):
            sets.append(f"{k}=?")
            vals.append(v)
    if not sets:
        return
    with _lock, _conn() as c:
        c.execute(f"UPDATE files SET {', '.join(sets)} WHERE id=?",
                  tuple(vals) + (file_id,))

def update_title(title_id: int, data: dict) -> None:
    """Partially update a title row.  Only keys present in data with non-None values are written."""
    if not data or not title_id:
        return
    now = int(time.time())
    sets: list[str] = []
    vals: list = []
    for k, v in data.items():
        if v is not None and k not in ("id", "created_at"):
            sets.append(f"{k}=?")
            vals.append(v)
    if not sets:
        return
    with _lock, _conn() as c:
        c.execute(f"UPDATE titles SET {', '.join(sets)}, updated_at=? WHERE id=?",
                  tuple(vals) + (now, title_id))


def update_mirror_status(file_id: int, *, github=None, gsheets=None) -> None:
    sets, vals = [], []
    now = int(time.time())
    if github is not None:
        sets += ["github_status=?", "github_synced_at=?"]
        vals += [github, now]
    if gsheets is not None:
        sets += ["gsheets_status=?", "gsheets_synced_at=?"]
        vals += [gsheets, now]
    if not sets: return
    with _lock, _conn() as c:
        c.execute(f"UPDATE files SET {', '.join(sets)} WHERE id=?", tuple(vals) + (file_id,))


# --------------------------------------------------------------------------- #
# Library queries                                                             #
# --------------------------------------------------------------------------- #

def count_library() -> dict:
    with _conn() as c:
        t  = c.execute("SELECT COUNT(*) AS n FROM titles").fetchone()["n"]
        f  = c.execute("SELECT COUNT(*) AS n FROM files").fetchone()["n"]
        sz = c.execute("SELECT COALESCE(SUM(size_bytes),0) AS s FROM files").fetchone()["s"]
        scn = c.execute("SELECT COUNT(*) AS n FROM files WHERE source='scan'").fetchone()["n"]
        upl = c.execute("SELECT COUNT(*) AS n FROM files WHERE source='upload'").fetchone()["n"]
        gh_ok = c.execute("SELECT COUNT(*) AS n FROM files WHERE github_status='ok'").fetchone()["n"]
        gs_ok = c.execute("SELECT COUNT(*) AS n FROM files WHERE gsheets_status='ok'").fetchone()["n"]
    return {"titles": t, "files": f, "total_size": sz,
            "scans": scn, "uploads": upl,
            "github_synced": gh_ok, "gsheets_synced": gs_ok}


def list_titles(*, limit: int = 200, q: str = "") -> list:
    sql = "SELECT * FROM titles"
    args = []
    if q:
        sql += " WHERE title LIKE ? OR original_title LIKE ?"
        args += [f"%{q}%", f"%{q}%"]
    sql += " ORDER BY updated_at DESC LIMIT ?"
    args.append(limit)
    with _conn() as c:
        return [_enrich_title(r) for r in c.execute(sql, args).fetchall()]


def list_files_for_title(title_id: int) -> list:
    with _conn() as c:
        return [dict(r) for r in c.execute(
            "SELECT * FROM files WHERE title_id=? ORDER BY season,episode,filename",
            (title_id,)).fetchall()]


def list_files(*, limit: int = 500, source: Optional[str] = None) -> list:
    sql = "SELECT * FROM files"
    args = []
    if source:
        sql += " WHERE source=?"
        args.append(source)
    sql += " ORDER BY COALESCE(scanned_at, uploaded_at, 0) DESC LIMIT ?"
    args.append(limit)
    with _conn() as c:
        return [dict(r) for r in c.execute(sql, args).fetchall()]


# --------------------------------------------------------------------------- #
# Bot status index                                                             #
# --------------------------------------------------------------------------- #

def upsert_bot_status(fingerprint: str, *, user_jid: str = "", title: str = "",
                      state: str = "pending", progress_pct: float = 0.0,
                      detail: str = "") -> None:
    """Insert or replace a row in bot_status_index."""
    now = int(time.time())
    with _lock, _conn() as c:
        c.execute(
            "INSERT OR REPLACE INTO bot_status_index"
            "(fingerprint,user_jid,title,state,progress_pct,detail,updated_at,created_at) "
            "VALUES(?,?,?,?,?,?,?,COALESCE("
            "  (SELECT created_at FROM bot_status_index WHERE fingerprint=?), ?"
            "))",
            (fingerprint, user_jid, title, state, progress_pct, detail, now,
             fingerprint, now)
        )


def list_bot_status(user_jid: Optional[str] = None, state: Optional[str] = None,
                    limit: int = 100) -> list:
    """Return bot_status_index rows, optionally filtered by user_jid and/or state."""
    sql  = "SELECT * FROM bot_status_index WHERE 1=1"
    args: list = []
    if user_jid:
        sql += " AND user_jid=?"; args.append(user_jid)
    if state:
        sql += " AND state=?";    args.append(state)
    sql += " ORDER BY updated_at DESC LIMIT ?"
    args.append(limit)
    with _conn() as c:
        return [dict(r) for r in c.execute(sql, args).fetchall()]


def delete_bot_status(fingerprint: str) -> None:
    with _lock, _conn() as c:
        c.execute("DELETE FROM bot_status_index WHERE fingerprint=?", (fingerprint,))


# --------------------------------------------------------------------------- #
# Rate limit log                                                               #
# --------------------------------------------------------------------------- #

def log_rate_request(user_jid: str) -> None:
    """Record a request timestamp for `user_jid` (used by bot throttling)."""
    now = int(time.time())
    with _lock, _conn() as c:
        c.execute(
            "INSERT INTO rate_limit_log(user_jid, ts) VALUES(?,?)",
            (user_jid, now)
        )


def rate_limit_count(user_jid: str, window_s: int = 60) -> int:
    """Count how many requests `user_jid` made in the last `window_s` seconds."""
    cutoff = int(time.time()) - window_s
    with _conn() as c:
        row = c.execute(
            "SELECT COUNT(*) AS n FROM rate_limit_log WHERE user_jid=? AND ts>=?",
            (user_jid, cutoff)
        ).fetchone()
    return int(row["n"]) if row else 0


def cleanup_rate_limit_log(older_than_s: int = 3600) -> int:
    """Prune entries older than `older_than_s` seconds. Returns rows deleted."""
    cutoff = int(time.time()) - older_than_s
    with _lock, _conn() as c:
        cur = c.execute("DELETE FROM rate_limit_log WHERE ts<?", (cutoff,))
    return cur.rowcount


# --------------------------------------------------------------------------- #
# Accounts                                                                    #
# --------------------------------------------------------------------------- #

def list_accounts(*, hide_secrets: bool = True, role: Optional[str] = None) -> list:
    with _conn() as c:
        if role:
            # Match exact role ("scan") OR role that contains it ("flix,scan")
            rows = [dict(r) for r in c.execute(
                "SELECT * FROM accounts WHERE role=? OR role LIKE ? OR role LIKE ? OR role LIKE ? ORDER BY id",
                (role, f"{role},%", f"%,{role}", f"%,{role},%")).fetchall()]
        else:
            rows = [dict(r) for r in c.execute(
                "SELECT * FROM accounts ORDER BY id").fetchall()]
    if hide_secrets:
        for r in rows:
            r.pop("validation_key", None)
            r.pop("jsessionid",     None)
    return rows


def normalize_msisdn(msisdn: str) -> str:
    """Normalize a Pakistan mobile number to 03xxxxxxxxx format."""
    s = str(msisdn or "").strip().replace(" ", "").replace("-", "").replace("+", "")
    if s.startswith("92"):
        s = "0" + s[2:]
    if s.startswith("3") and len(s) == 10:
        s = "0" + s
    return s


def get_account(account_id: int) -> Optional[dict]:
    with _conn() as c:
        r = c.execute("SELECT * FROM accounts WHERE id=?", (account_id,)).fetchone()
        return dict(r) if r else None


def upsert_account(*, msisdn: str, label: str = "", notes: str = "",
                   role: str = "flix") -> int:
    """Upsert an account with strict role enforcement.

    Roles:
      - 'flix': The upload/heartbeat account. ONLY ONE allowed globally.
      - 'scan': Read-only library-building accounts. Multiple allowed.

    Rules:
      - A number already in 'scan' cannot become 'flix' — delete from scan first.
      - A number already in 'flix' cannot become 'scan' — delete from flix first.
      - Only one 'flix' account allowed — if a different number is already flix, raises ValueError.
      - Re-logging into the same number for the same role is always allowed (updates credentials).

    Raises:
      ValueError: on any role-conflict violation.
    """
    now = int(time.time())
    with _lock, _conn() as c:
        existing = c.execute("SELECT id, role FROM accounts WHERE msisdn=?", (msisdn,)).fetchone()

        if role == "flix":
            # Block: this number is already a scan account
            if existing and existing["role"] == "scan":
                raise ValueError(
                    f"{msisdn} is already a scan account. "
                    "Remove it from scan before using it as the flix account.")
            # Block: an *active* different number is already the flix account.
            # Inactive (logged-out) accounts can be overwritten silently.
            other_flix = c.execute(
                "SELECT msisdn FROM accounts WHERE role='flix' AND is_active=1 AND msisdn != ?",
                (msisdn,)
            ).fetchone()
            if other_flix:
                raise ValueError(
                    f"An active flix account already exists ({other_flix['msisdn']}). "
                    "Delete it before adding a new one.")

        elif role == "scan":
            # Block: this number is already the flix account
            if existing and existing["role"] == "flix":
                raise ValueError(
                    f"{msisdn} is already the flix account. "
                    "Remove it from flix before adding it as a scan account.")

        if existing:
            c.execute("UPDATE accounts SET label=?, notes=?, role=? WHERE id=?",
                      (label, notes, role, existing["id"]))
            return existing["id"]

        cur = c.execute(
            "INSERT INTO accounts(msisdn,label,notes,role,created_at) VALUES(?,?,?,?,?)",
            (msisdn, label, notes, role, now))
        return cur.lastrowid


def update_account_session(account_id: int, *, validation_key: str, jsessionid: str,
                           node: str = "", expires_at: int = 0,
                           refresh_token: str = "",
                           raw_accesstoken: str = "") -> None:
    with _lock, _conn() as c:
        c.execute("UPDATE accounts SET validation_key=?, jsessionid=?, node=?, "
                  "token_expires_at=?, refresh_token=?, raw_accesstoken=? WHERE id=?",
                  (validation_key, jsessionid, node, expires_at,
                   refresh_token or None, raw_accesstoken or None, account_id))


def delete_account(account_id: int) -> None:
    with _lock, _conn() as c:
        c.execute("DELETE FROM accounts WHERE id=?", (account_id,))


def change_account_role(account_id: int, new_role: str) -> None:
    """Change an existing account's role between 'scan' and 'flix'.

    Rules:
      - Only one active 'flix' account allowed globally.
      - Switching to the current role is a no-op.

    Raises:
      ValueError: if new_role is invalid or a conflict exists.
    """
    if new_role not in ("scan", "flix"):
        raise ValueError(f"Invalid role: {new_role!r}")
    with _lock, _conn() as c:
        acct = c.execute("SELECT id, role FROM accounts WHERE id=?", (account_id,)).fetchone()
        if not acct:
            raise ValueError(f"Account {account_id} not found")
        if acct["role"] == new_role:
            return
        if new_role == "flix":
            other = c.execute(
                "SELECT msisdn FROM accounts WHERE role='flix' AND is_active=1 AND id != ?",
                (account_id,)
            ).fetchone()
            if other:
                raise ValueError(
                    f"Active flix account already exists ({other['msisdn']}). "
                    "Change or remove it before promoting a new one.")
        c.execute("UPDATE accounts SET role=? WHERE id=?", (new_role, account_id))


def touch_account_scan(account_id: int) -> None:
    with _lock, _conn() as c:
        c.execute("UPDATE accounts SET last_scan_at=? WHERE id=?",
                  (int(time.time()), account_id))


def append_scan_log(account_id: int, kind: str, message: str) -> None:
    with _lock, _conn() as c:
        c.execute("INSERT INTO scan_log(account_id,kind,message,ts) VALUES(?,?,?,?)",
                  (account_id, kind, message, int(time.time())))


def get_scan_log(account_id: int, after: int = 0, limit: int = 200) -> list:
    with _conn() as c:
        rows = c.execute("SELECT * FROM scan_log WHERE account_id=? AND id>? "
                         "ORDER BY id LIMIT ?",
                         (account_id, after, limit)).fetchall()
    return [dict(r) for r in rows]



def clear_scan_log(account_id: int) -> int:
    """Delete all scan log rows for an account. Returns number of rows deleted."""
    with conn() as c:
        cur = c.execute("DELETE FROM scan_log WHERE account_id=?", (account_id,))
        return cur.rowcount

def find_duplicates(limit: int = 500) -> list:
    """Return files that share the same title_id, appearing more than once.

    Rows are ordered by title then size DESC so the largest (keeper) comes first
    within each group.
    """
    with _conn() as c:
        rows = c.execute("""
            SELECT f.id, f.filename, f.quality, f.size_bytes, f.remote_id,
                   f.remote_folder_id, f.folder_path, f.account_id,
                   t.title, t.year, t.tmdb_id, t.id AS title_id,
                   t.media_type
            FROM files f
            LEFT JOIN titles t ON t.id = f.title_id
            WHERE f.title_id IS NOT NULL
              AND f.title_id IN (
                  SELECT title_id FROM files
                  WHERE title_id IS NOT NULL
                  GROUP BY title_id
                  HAVING COUNT(*) > 1
              )
            ORDER BY t.title, f.quality, f.size_bytes DESC
            LIMIT ?
        """, (limit,)).fetchall()
    return [dict(r) for r in rows]


# --------------------------------------------------------------------------- #
# Migration from v2.0                                                         #
# --------------------------------------------------------------------------- #

V2_FLIX_DB  = config.PROJECT_ROOT.parent / "RaddHub-v2.0" / "services" / "flix"  / "radd_flix.db"
V2_DBGEN_DB = config.PROJECT_ROOT.parent / "RaddHub-v2.0" / "services" / "dbgen" / "radd_media.db"


def migrate_from_v2() -> dict:
    """Read v2.0 SQLite files (read-only) and copy rows into v3 DB.

    Idempotent: re-running merges only what's missing.
    """
    stats = {"flix_uploads": 0, "dbgen_titles": 0, "dbgen_files": 0,
             "dbgen_accounts": 0, "errors": []}

    # ---- flix uploads ------------------------------------------------------
    if V2_FLIX_DB.exists():
        try:
            src = sqlite3.connect(f"file:{V2_FLIX_DB}?mode=ro", uri=True)
            src.row_factory = sqlite3.Row
            for r in src.execute("SELECT * FROM uploads"):
                row = dict(r)
                fp = "flix:" + (row.get("fingerprint") or "")
                # Build a title from tmdb fields
                tmdb_id = row.get("tmdb_numeric_id")
                try: tmdb_id = int(tmdb_id) if tmdb_id else None
                except: tmdb_id = None
                title_id = upsert_title({
                    "content_key":   row.get("content_key") or fp,
                    "tmdb_id":       tmdb_id,
                    "media_type":    "tv" if (row.get("media_kind") or "").lower() in
                                     ("series","season","episode","tv") else "movie",
                    "title":         (row.get("tmdb_title") or row.get("name") or "Unknown"),
                    "original_title":(row.get("tmdb_title") or row.get("name") or "Unknown"),
                    "year":          (row.get("tmdb_year") or "")[:4],
                    "rating":        row.get("tmdb_rating"),
                    "poster":        row.get("tmdb_poster"),
                    "genres_csv":    row.get("genres_csv"),
                    "cast_json":     row.get("cast_json"),
                    "director":      row.get("director"),
                    "crew_json":     row.get("director_json"),
                    "languages_csv": row.get("languages_csv"),
                    "runtime":       row.get("runtime"),
                })
                upsert_file({
                    "fingerprint":     fp,
                    "title_id":        title_id,
                    "source":          "upload",
                    "filename":        row.get("name", ""),
                    "local_path":      row.get("path"),
                    "media_kind":      row.get("media_kind") or row.get("mediatype"),
                    "season":          row.get("season"),
                    "episode":         row.get("episode"),
                    "size_bytes":      row.get("size_bytes") or 0,
                    "remote_id":       row.get("remote_id"),
                    "remote_folder_id":row.get("remote_folder_id"),
                    "remote_file_id":  row.get("remote_file_id"),
                    "folder_path":     row.get("share_folder_path"),
                    "share_url":       row.get("share_url"),
                    "share_key":       row.get("share_key"),
                    "share_link_id":   row.get("share_link_id"),
                    "share_folder_id": row.get("share_folder_id"),
                    "download_url":    row.get("download_url"),
                    "uploaded_at":     _to_epoch(row.get("uploaded_at")),
                })
                stats["flix_uploads"] += 1
            src.close()
        except Exception as e:
            stats["errors"].append(f"flix migration: {e}")

    # ---- dbgen titles + files + accounts -----------------------------------
    if V2_DBGEN_DB.exists():
        try:
            src = sqlite3.connect(f"file:{V2_DBGEN_DB}?mode=ro", uri=True)
            src.row_factory = sqlite3.Row
            # accounts
            try:
                for r in src.execute("SELECT * FROM accounts"):
                    a = dict(r)
                    aid = upsert_account(msisdn=a.get("msisdn") or "",
                                         label=a.get("label") or "",
                                         notes=a.get("notes") or "")
                    if a.get("validation_key") and a.get("jsessionid"):
                        update_account_session(aid,
                            validation_key=a.get("validation_key"),
                            jsessionid=a.get("jsessionid"),
                            node=a.get("node") or "")
                    stats["dbgen_accounts"] += 1
            except Exception as e:
                stats["errors"].append(f"dbgen accounts: {e}")
            # titles
            local_to_new = {}
            try:
                for r in src.execute("SELECT * FROM titles"):
                    t = dict(r)
                    new_id = upsert_title({
                        "content_key":  t.get("content_key"),
                        "tmdb_id":      t.get("tmdb_id"),
                        "media_type":   t.get("media_type"),
                        "title":        t.get("title"),
                        "original_title":t.get("original_title"),
                        "year":         t.get("year"),
                        "rating":       t.get("rating"),
                        "vote_count":   t.get("vote_count") or 0,
                        "poster":       t.get("poster"),
                        "genres_csv":   t.get("genres_csv"),
                        "cast_json":    t.get("cast_json"),
                        "director":     t.get("director"),
                        "crew_json":    t.get("crew_json"),
                        "languages_csv":t.get("languages_csv"),
                        "runtime":      t.get("runtime"),
                    })
                    local_to_new[t["id"]] = new_id
                    stats["dbgen_titles"] += 1
            except Exception as e:
                stats["errors"].append(f"dbgen titles: {e}")
            # files
            try:
                for r in src.execute("SELECT * FROM files"):
                    f_ = dict(r)
                    upsert_file({
                        "fingerprint":     "scan:" + (f_.get("fingerprint") or
                                                    str(f_.get("id"))),
                        "title_id":        local_to_new.get(f_.get("title_id")),
                        "source":          "scan",
                        "filename":        f_.get("filename") or "",
                        "media_kind":      f_.get("media_kind"),
                        "season":          f_.get("season"),
                        "episode":         f_.get("episode"),
                        "size_bytes":      f_.get("size_bytes") or 0,
                        "quality":         f_.get("quality"),
                        "remote_id":       f_.get("remote_id"),
                        "remote_folder_id":f_.get("remote_folder_id"),
                        "folder_path":     f_.get("folder_path"),
                        "share_url":       f_.get("share_url"),
                        "share_key":       f_.get("share_key"),
                        "share_link_id":   f_.get("share_link_id"),
                        "share_folder_id": f_.get("share_folder_id"),
                        "download_url":    f_.get("download_url"),
                        "scanned_at":      _to_epoch(f_.get("uploaded_at") or
                                                     f_.get("created_at")),
                    })
                    stats["dbgen_files"] += 1
            except Exception as e:
                stats["errors"].append(f"dbgen files: {e}")
            src.close()
        except Exception as e:
            stats["errors"].append(f"dbgen migration: {e}")

    set_setting("v2_migrated_at", str(int(time.time())))
    return stats


# --------------------------------------------------------------------------- #
# Stream links — time-limited playable URLs                                   #
# --------------------------------------------------------------------------- #

def get_stream_link(file_id: int) -> Optional[dict]:
    """Return the most recent valid, unexpired stream link for a file, or None."""
    now = int(time.time())
    with _conn() as c:
        row = c.execute(
            "SELECT * FROM stream_links WHERE file_id=? AND is_valid=1 AND expires_at>? "
            "ORDER BY generated_at DESC LIMIT 1",
            (file_id, now)
        ).fetchone()
    return dict(row) if row else None


def save_stream_link(file_id: int, download_url: str, *,
                     expires_in: int = 18000, account_id: Optional[int] = None) -> int:
    """Save a new stream link for a file. Invalidates previous links for same file."""
    now = int(time.time())
    with _lock, _conn() as c:
        # Invalidate old links
        c.execute("UPDATE stream_links SET is_valid=0 WHERE file_id=?", (file_id,))
        cur = c.execute(
            "INSERT INTO stream_links(file_id, download_url, generated_at, expires_at, "
            "is_valid, account_id) VALUES(?,?,?,?,1,?)",
            (file_id, download_url, now, now + expires_in, account_id)
        )
    return cur.lastrowid


def invalidate_stream_links(file_id: int) -> None:
    """Mark all stream links for a file as invalid."""
    with _lock, _conn() as c:
        c.execute("UPDATE stream_links SET is_valid=0 WHERE file_id=?", (file_id,))


def log_stream_serve(link_id: int, bytes_served: int = 0) -> None:
    """Increment request count and bytes served for a stream link."""
    now = int(time.time())
    with _lock, _conn() as c:
        c.execute(
            "UPDATE stream_links SET request_count=request_count+1, "
            "bytes_served=bytes_served+?, last_served_at=? WHERE id=?",
            (bytes_served, now, link_id)
        )


# --------------------------------------------------------------------------- #
# Plans & subscriptions                                                        #
# --------------------------------------------------------------------------- #

def list_plans(active_only: bool = True) -> list:
    with _conn() as c:
        sql = "SELECT * FROM plans"
        if active_only:
            sql += " WHERE is_active=1"
        sql += " ORDER BY price_pkr"
        return [dict(r) for r in c.execute(sql).fetchall()]


def upsert_plan(rec: dict) -> int:
    now = int(time.time())
    cols = ["name","price_pkr","daily_limit_gb","monthly_limit_gb",
            "max_devices","duration_days","description","badge","color",
            "features_json","is_active"]
    vals = [rec.get(c) for c in cols]
    with _lock, _conn() as c:
        existing = None
        if rec.get("id"):
            existing = c.execute("SELECT id FROM plans WHERE id=?", (rec["id"],)).fetchone()
        if existing:
            pid = existing["id"]
            c.execute(
                "UPDATE plans SET " + ", ".join(f"{k}=?" for k in cols) + " WHERE id=?",
                tuple(vals) + (pid,)
            )
            return pid
        cur = c.execute(
            "INSERT INTO plans(" + ",".join(cols) + ",created_at) VALUES(" +
            ",".join("?" * len(cols)) + ",?)",
            tuple(vals) + (now,)
        )
        return cur.lastrowid


def get_user_subscription(user_jid: str) -> Optional[dict]:
    """Return the active, non-expired subscription for a user (joined with plan)."""
    now = int(time.time())
    with _conn() as c:
        row = c.execute(
            "SELECT s.*, p.name as plan_name, p.daily_limit_gb, p.monthly_limit_gb, "
            "p.max_devices, p.price_pkr "
            "FROM user_subscriptions s "
            "LEFT JOIN plans p ON s.plan_id=p.id "
            "WHERE s.user_jid=? AND s.is_active=1 AND s.expires_at>? "
            "ORDER BY s.expires_at DESC LIMIT 1",
            (user_jid, now)
        ).fetchone()
    return dict(row) if row else None


def grant_subscription(user_jid: str, plan_id: int) -> int:
    """Grant a plan subscription to a user. Deactivates any existing active subscription."""
    now = int(time.time())
    plan = None
    with _conn() as c:
        plan = c.execute("SELECT * FROM plans WHERE id=?", (plan_id,)).fetchone()
    if not plan:
        raise ValueError(f"Plan {plan_id} not found")
    plan = dict(plan)
    duration = plan.get("duration_days") or 30
    with _lock, _conn() as c:
        c.execute("UPDATE user_subscriptions SET is_active=0 WHERE user_jid=?", (user_jid,))
        cur = c.execute(
            "INSERT INTO user_subscriptions(user_jid, plan_id, started_at, expires_at, is_active) "
            "VALUES(?,?,?,?,1)",
            (user_jid, plan_id, now, now + duration * 86400)
        )
    return cur.lastrowid


# --------------------------------------------------------------------------- #
# User usage — daily data tracking                                             #
# --------------------------------------------------------------------------- #

def log_usage(user_jid: str, bytes_used: int = 0, requests: int = 1) -> None:
    """Increment daily usage for a user."""
    from datetime import date as _date
    today = _date.today().isoformat()
    now   = int(time.time())
    with _lock, _conn() as c:
        c.execute(
            "INSERT INTO user_usage(user_jid, date, bytes_used, requests_count, last_active_at) "
            "VALUES(?,?,?,?,?) "
            "ON CONFLICT(user_jid, date) DO UPDATE SET "
            "bytes_used=bytes_used+excluded.bytes_used, "
            "requests_count=requests_count+excluded.requests_count, "
            "last_active_at=excluded.last_active_at",
            (user_jid, today, bytes_used, requests, now)
        )


def get_usage_today(user_jid: str) -> dict:
    """Return today's usage row for a user."""
    from datetime import date as _date
    today = _date.today().isoformat()
    with _conn() as c:
        row = c.execute(
            "SELECT * FROM user_usage WHERE user_jid=? AND date=?", (user_jid, today)
        ).fetchone()
    return dict(row) if row else {"user_jid": user_jid, "date": today,
                                  "bytes_used": 0, "requests_count": 0}


def get_usage_month(user_jid: str) -> dict:
    """Return aggregated usage for the current calendar month."""
    from datetime import date as _date
    month_prefix = _date.today().strftime("%Y-%m")
    with _conn() as c:
        row = c.execute(
            "SELECT SUM(bytes_used) AS bytes, SUM(requests_count) AS reqs "
            "FROM user_usage WHERE user_jid=? AND date LIKE ?",
            (user_jid, f"{month_prefix}%")
        ).fetchone()
    return {"bytes_used": row["bytes"] or 0, "requests_count": row["reqs"] or 0}


def check_quota(user_jid: str) -> dict:
    """Check if a user is within their plan quota.

    Returns:
      { allowed, plan_name, daily_limit_gb, monthly_limit_gb,
        daily_used_gb, monthly_used_gb, daily_remaining_gb, monthly_remaining_gb }
    """
    sub = get_user_subscription(user_jid)
    if not sub:
        return {"allowed": False, "reason": "no_subscription",
                "plan_name": None, "daily_limit_gb": 0}

    today_usage   = get_usage_today(user_jid)
    month_usage   = get_usage_month(user_jid)
    GB            = 1024 ** 3

    daily_limit   = float(sub.get("daily_limit_gb") or 0)
    monthly_limit = float(sub.get("monthly_limit_gb") or 0)
    daily_used    = (today_usage.get("bytes_used") or 0) / GB
    monthly_used  = (month_usage.get("bytes_used") or 0) / GB

    if daily_limit and daily_used >= daily_limit:
        return {"allowed": False, "reason": "daily_limit_reached",
                "plan_name": sub.get("plan_name"),
                "daily_limit_gb": daily_limit, "daily_used_gb": round(daily_used, 2)}

    if monthly_limit and monthly_used >= monthly_limit:
        return {"allowed": False, "reason": "monthly_limit_reached",
                "plan_name": sub.get("plan_name"),
                "monthly_limit_gb": monthly_limit, "monthly_used_gb": round(monthly_used, 2)}

    return {
        "allowed":             True,
        "plan_name":           sub.get("plan_name"),
        "daily_limit_gb":      daily_limit,
        "monthly_limit_gb":    monthly_limit,
        "daily_used_gb":       round(daily_used, 2),
        "monthly_used_gb":     round(monthly_used, 2),
        "daily_remaining_gb":  round(max(0, daily_limit - daily_used), 2) if daily_limit else None,
        "monthly_remaining_gb":round(max(0, monthly_limit - monthly_used), 2) if monthly_limit else None,
    }


def _to_epoch(s) -> int:
    if not s: return 0
    if isinstance(s, (int, float)): return int(s)
    if isinstance(s, str):
        try: return int(s)
        except ValueError:
            try:
                from datetime import datetime
                return int(datetime.fromisoformat(s).timestamp())
            except Exception:
                return 0
    return 0


# --------------------------------------------------------------------------- #
# Deduplication & Queue Check                                                 #
# --------------------------------------------------------------------------- #

def is_episode_in_library(show_title: str, season: int, episode: int) -> bool:
    """
    Check if a specific episode of a show exists in the library.
    Uses the Canonical Media Index for high-speed lookups.
    """
    if not show_title or season is None or episode is None:
        return False

    # Normalize title for matching
    clean_show = re.sub(r"[^a-z0-9]+", "", show_title.lower()).strip()
    
    with _conn() as c:
        ready = c.execute(
            "SELECT id FROM media_index WHERE normalized_title=? AND season=? AND episode=? LIMIT 1",
            (clean_show, season, episode)
        ).fetchone()
        return bool(ready)


def index_media_file(file_id: int) -> None:
    """Extract metadata and add a file to the high-speed Canonical Index."""
    with _conn() as c:
        f = c.execute("SELECT f.*, t.title FROM files f JOIN titles t ON f.title_id=t.id WHERE f.id=?", (file_id,)).fetchone()
        if not f or not f["title"]: return
        
        s, e = f["season"], f["episode"]
        if s is None or e is None:
            # Try extraction from filename
            from .media_naming import _detect_season_episode
            s_ext, e_ext = _detect_season_episode(f["filename"])
            s = s if s is not None else s_ext
            e = e if e is not None else e_ext

        # Normalize title
        clean_title = re.sub(r"[^a-z0-9]+", "", f["title"].lower()).strip()
        
        c.execute(
            "INSERT OR REPLACE INTO media_index (title_id, normalized_title, season, episode, quality, file_id, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (f["title_id"], clean_title, s, e, f["quality"], f["id"], int(time.time()))
        )

def backfill_media_index() -> int:
    """Populate media_index from all existing files. Returns count indexed."""
    count = 0
    with _conn() as c:
        files = c.execute("SELECT id FROM files WHERE is_ready=1").fetchall()
        for f in files:
            try:
                index_media_file(f["id"])
                count += 1
            except: pass
    return count


def check_duplicate(query: str, year: Optional[str] = None) -> Optional[dict]:
    """Check if a movie or a specific season is already in the library or queue.
    
    Returns a dict with 'reason' ('library' or 'queue') and metadata if duplicate found.
    """
    # 1. Extract Season
    season_num = None
    m_season = re.search(r"(?:season|s)\s*0*(\d+)", query, re.I)
    if m_season:
        season_num = int(m_season.group(1))
    
    # 2. Clean Title for matching (remove season part and quality tags)
    clean_title = re.sub(r"(?:season|s)\s*0*\d+", "", query, flags=re.I)
    clean_title = re.sub(r"\b(1080p|720p|480p|4k|2160p|bluray|web-dl|hdtv|x264|x265|hevc)\b", "", clean_title, flags=re.I)
    clean_title = clean_title.strip(" ._-")
    if not clean_title:
        clean_title = query

    with conn() as c:
        # --- 1. Check Library (titles + files) ---
        # Try exact match first, then LIKE
        sql = "SELECT id, title, year, media_type FROM titles WHERE (title = ? OR title LIKE ?)"
        args = [clean_title, f"%{clean_title}%"]
        if year:
            sql += " AND year=?"
            args.append(str(year))
        
        candidates = c.execute(sql + " LIMIT 10", args).fetchall()
        for t in candidates:
            # If a specific season was requested, check if it exists in files
            if season_num is not None:
                ready = c.execute(
                    "SELECT id FROM files WHERE title_id=? AND (season=? OR filename LIKE ?) AND is_ready>=0 LIMIT 1",
                    (t["id"], season_num, f"%S{season_num:02d}%")
                ).fetchone()
            else:
                # No specific season requested, check if ANY file exists (ready OR pending upload)
                ready = c.execute(
                    "SELECT id FROM files WHERE title_id=? AND is_ready>=0 LIMIT 1",
                    (t["id"],)
                ).fetchone()
            
            if ready:
                # Verify title isn't a partial match of something else (e.g. "Solo" matching "Solo Leveling")
                t_low = t["title"].lower()
                q_low = clean_title.lower()
                if q_low != t_low and q_low not in t_low and t_low not in q_low:
                    continue

                return {
                    "reason": "library", 
                    "title_id": t["id"], 
                    "title": t["title"],
                    "year": t["year"],
                    "media_type": t["media_type"],
                    "season": season_num
                }

        # --- 1b. Fallback: check files directly by filename (catches title_id=NULL downloads) ---
        fname_pattern = f"%{clean_title.replace(' ', '%')}%"
        file_candidates = c.execute(
            "SELECT id, filename, title_id FROM files WHERE filename LIKE ? AND is_ready>=0 LIMIT 5",
            (fname_pattern,)
        ).fetchall()
        for f in file_candidates:
            fn_low = f["filename"].lower()
            q_low = clean_title.lower()
            if q_low.replace(" ", "") not in fn_low.replace(".", "").replace("_", "").replace(" ", ""):
                continue
            if year and str(year) not in fn_low:
                continue
            return {
                "reason": "library",
                "title_id": f["title_id"],
                "title": clean_title,
                "year": year,
                "media_type": "movie",
                "season": season_num,
            }

        # --- 2. Check Active Queue ---
        queue_sql = "SELECT job_id, movie, status FROM queue WHERE status IN ('queued', 'processing', 'paused')"
        in_queue = c.execute(queue_sql).fetchall()
        
        for q in in_queue:
            q_movie = q["movie"].lower()
            q_clean = clean_title.lower()
            
            # Check if title matches
            if q_clean in q_movie:
                # Check year if provided
                if year and str(year) not in q_movie:
                    continue
                # Check season if provided
                if season_num is not None:
                    # Look for S01, S1, Season 1, etc.
                    q_season_pat = rf"(?:season|s)\s*0*{season_num}\b"
                    if not re.search(q_season_pat, q_movie, re.I):
                        continue
                
                return {
                    "reason": "queue", 
                    "job_id": q["job_id"], 
                    "status": q["status"], 
                    "movie": q["movie"]
                }
                
    return None
