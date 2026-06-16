'use strict';
const path           = require('path');
const fs             = require('fs');
const SQLite3 = require('better-sqlite3');
const BOT_DB_PATH = path.join(__dirname, '..', 'bot.db');
const USERS_FILE  = path.join(__dirname, '..', 'users.json');
const db = new SQLite3(BOT_DB_PATH);
db.exec(`
  CREATE TABLE IF NOT EXISTS bot_users (
    jid              TEXT PRIMARY KEY,
    role             TEXT NOT NULL DEFAULT 'free',
    daily_quota_mb   INTEGER NOT NULL DEFAULT 10240,
    used_today_mb    INTEGER NOT NULL DEFAULT 0,
    quota_reset_date TEXT,
    points           INTEGER NOT NULL DEFAULT 0,
    referrer_jid     TEXT,
    referral_code    TEXT UNIQUE,
    pushname         TEXT,
    joined_at        INTEGER,
    last_seen_at     INTEGER
  );
  CREATE INDEX IF NOT EXISTS idx_bu_role ON bot_users(role);
  CREATE INDEX IF NOT EXISTS idx_bu_referrer ON bot_users(referrer_jid);
  CREATE TABLE IF NOT EXISTS bot_audit (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    ts        INTEGER NOT NULL,
    jid       TEXT,
    event     TEXT NOT NULL,
    detail    TEXT
  );
  CREATE INDEX IF NOT EXISTS idx_audit_ts ON bot_audit(ts);
  CREATE INDEX IF NOT EXISTS idx_audit_jid ON bot_audit(jid);
  CREATE TABLE IF NOT EXISTS bot_quota_log (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    ts           INTEGER NOT NULL,
    jid          TEXT NOT NULL,
    bytes        INTEGER NOT NULL,
    fingerprint  TEXT,
    title        TEXT
  );
  CREATE INDEX IF NOT EXISTS idx_qlog_jid_ts ON bot_quota_log(jid, ts);
  CREATE TABLE IF NOT EXISTS bot_trailers (
    content_key  TEXT PRIMARY KEY,
    title        TEXT,
    youtube_key  TEXT,
    fetched_at   INTEGER
  );
  CREATE TABLE IF NOT EXISTS bot_settings (
    key   TEXT PRIMARY KEY,
    value TEXT
  );
  CREATE TABLE IF NOT EXISTS jid_aliases (
    lid TEXT PRIMARY KEY,
    pn  TEXT NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_ja_pn ON jid_aliases(pn);
  CREATE TABLE IF NOT EXISTS bot_search_history (
    id     INTEGER PRIMARY KEY AUTOINCREMENT,
    jid    TEXT NOT NULL,
    query  TEXT NOT NULL,
    ts     INTEGER NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_bsh_jid_query ON bot_search_history(jid, query);
`);
function jidNumber(j) { return (j || '').split('@')[0].split(':')[0]; }
function todayStr() {
  const d = new Date();
  return d.toISOString().slice(0, 10);
}
function saveAlias(lid, pn) {
  if (!lid || !pn || !lid.endsWith('@lid')) return;
  const normPn = jidNumber(pn) + '@s.whatsapp.net';
  db.prepare(`INSERT OR REPLACE INTO jid_aliases (lid, pn) VALUES (?, ?)`).run(lid, normPn);
}
function resolveAlias(jid) {
  if (!jid || !jid.endsWith('@lid')) return jid;
  const row = db.prepare(`SELECT pn FROM jid_aliases WHERE lid = ?`).get(jid);
  return row ? row.pn : jid;
}
function loadUsersJson() {
  try { return JSON.parse(fs.readFileSync(USERS_FILE, 'utf8')); }
  catch { return { admins: [], verified: [], blocked: [], settings: {} }; }
}
function mirrorUsersJson() {
  const u = loadUsersJson();
  const sets = (list, role) => {
    for (const x of (list || [])) {
      const jid = String(x);
      const norm = jidNumber(jid) + '@s.whatsapp.net';
      db.prepare(`INSERT INTO bot_users (jid, role, joined_at) VALUES (?, ?, ?)
                  ON CONFLICT(jid) DO UPDATE SET role = excluded.role`)
        .run(norm, role, Math.floor(Date.now() / 1000));
    }
  };
  sets(u.admins,   'admin');
  sets(u.verified, 'verified');
  sets(u.blocked,  'blocked');
}
function touchUser(jid, pushname) {
  if (!jid) return;
  const norm = jidNumber(jid) + '@s.whatsapp.net';
  db.prepare(`INSERT INTO bot_users (jid, pushname, joined_at, last_seen_at)
              VALUES (?, ?, ?, ?)
              ON CONFLICT(jid) DO UPDATE SET
                pushname     = COALESCE(excluded.pushname, bot_users.pushname),
                last_seen_at = excluded.last_seen_at`)
    .run(norm, pushname || null, Math.floor(Date.now() / 1000), Math.floor(Date.now() / 1000));
}
function getUser(jid) {
  const norm = jidNumber(jid) + '@s.whatsapp.net';
  let row = db.prepare(`SELECT * FROM bot_users WHERE jid = ?`).get(norm);
  if (!row) {
    db.prepare(`INSERT INTO bot_users (jid, role, joined_at, last_seen_at)
                VALUES (?, 'free', ?, ?)`)
      .run(norm, Math.floor(Date.now() / 1000), Math.floor(Date.now() / 1000));
    row = db.prepare(`SELECT * FROM bot_users WHERE jid = ?`).get(norm);
  }
  return row;
}
function setRole(jid, role) {
  if (!['admin', 'verified', 'free', 'blocked'].includes(role)) {
    throw new Error(`invalid role: ${role}`);
  }
  const norm = jidNumber(jid) + '@s.whatsapp.net';
  db.prepare(`INSERT INTO bot_users (jid, role) VALUES (?, ?)
              ON CONFLICT(jid) DO UPDATE SET role = excluded.role`)
    .run(norm, role);
}
function setQuota(jid, dailyQuotaMb) {
  const norm = jidNumber(jid) + '@s.whatsapp.net';
  db.prepare(`INSERT INTO bot_users (jid, daily_quota_mb) VALUES (?, ?)
              ON CONFLICT(jid) DO UPDATE SET daily_quota_mb = excluded.daily_quota_mb`)
    .run(norm, Math.max(0, Math.floor(dailyQuotaMb)));
}
function listUsers(role) {
  if (role) {
    return db.prepare(`SELECT * FROM bot_users WHERE role = ? ORDER BY last_seen_at DESC`).all(role);
  }
  return db.prepare(`SELECT * FROM bot_users ORDER BY last_seen_at DESC`).all();
}
function audit(event, jid, detail) {
  db.prepare(`INSERT INTO bot_audit (ts, jid, event, detail) VALUES (?, ?, ?, ?)`)
    .run(Math.floor(Date.now() / 1000), jid || null, event, detail ? String(detail).slice(0, 1000) : null);
}
function _resetIfNeeded(user) {
  const today = todayStr();
  if (user.quota_reset_date !== today) {
    db.prepare(`UPDATE bot_users SET used_today_mb = 0, quota_reset_date = ? WHERE jid = ?`)
      .run(today, user.jid);
    user.used_today_mb = 0;
    user.quota_reset_date = today;
  }
  return user;
}
function quotaStatus(jid) {
  const u = _resetIfNeeded(getUser(jid));
  return {
    role:           u.role,
    daily_quota_mb: u.daily_quota_mb,
    used_today_mb:  u.used_today_mb,
    remaining_mb:   Math.max(0, u.daily_quota_mb - u.used_today_mb),
    reset_date:     u.quota_reset_date,
    points:         u.points || 0,
  };
}
function canDownload(jid, sizeBytes) {
  const u = _resetIfNeeded(getUser(jid));
  if (u.role === 'admin') return { ok: true, status: quotaStatus(jid) };
  if (u.role === 'free' || u.role === 'blocked') {
    return { ok: false, reason: 'role', status: quotaStatus(jid) };
  }
  const sizeMb = Math.ceil(Number(sizeBytes || 0) / (1024 * 1024));
  if (u.used_today_mb + sizeMb > u.daily_quota_mb) {
    return { ok: false, reason: 'quota', need_mb: sizeMb, status: quotaStatus(jid) };
  }
  return { ok: true, need_mb: sizeMb, status: quotaStatus(jid) };
}
function recordDownload(jid, sizeBytes, fingerprint, title) {
  const sizeMb = Math.ceil(Number(sizeBytes || 0) / (1024 * 1024));
  const u = _resetIfNeeded(getUser(jid));
  db.prepare(`UPDATE bot_users SET used_today_mb = used_today_mb + ? WHERE jid = ?`)
    .run(sizeMb, u.jid);
  db.prepare(`INSERT INTO bot_quota_log (ts, jid, bytes, fingerprint, title)
              VALUES (?, ?, ?, ?, ?)`)
    .run(Math.floor(Date.now() / 1000), u.jid, Number(sizeBytes || 0), fingerprint || null, title || null);
}
function consumeQuota(jid, sizeBytes, fingerprint, title) {
  const sizeMb = Math.ceil(Number(sizeBytes || 0) / (1024 * 1024));
  const norm = jidNumber(jid) + '@s.whatsapp.net';
  db.exec('BEGIN TRANSACTION');
  try {
    let u = db.prepare(`SELECT * FROM bot_users WHERE jid = ?`).get(norm);
    if (!u) {
      db.prepare(`INSERT INTO bot_users (jid, role, joined_at) VALUES (?, 'free', ?)`).run(norm, Math.floor(Date.now()/1000));
      u = db.prepare(`SELECT * FROM bot_users WHERE jid = ?`).get(norm);
    }
    const today = todayStr();
    if (u.quota_reset_date !== today) {
      db.prepare(`UPDATE bot_users SET used_today_mb = 0, quota_reset_date = ? WHERE jid = ?`).run(today, norm);
      u.used_today_mb = 0;
    }
    if (u.role !== 'admin' && u.used_today_mb + sizeMb > u.daily_quota_mb) {
      db.exec('ROLLBACK');
      return { ok: false, used: u.used_today_mb, total: u.daily_quota_mb };
    }
    db.prepare(`UPDATE bot_users SET used_today_mb = used_today_mb + ? WHERE jid = ?`).run(sizeMb, norm);
    db.prepare(`INSERT INTO bot_quota_log (ts, jid, bytes, fingerprint, title) VALUES (?, ?, ?, ?, ?)`)
      .run(Math.floor(Date.now() / 1000), norm, Number(sizeBytes || 0), fingerprint || null, title || null);
    db.exec('COMMIT');
    return { ok: true, used: u.used_today_mb + sizeMb, total: u.daily_quota_mb };
  } catch (e) {
    db.exec('ROLLBACK');
    throw e;
  }
}
function trailerGet(contentKey) {
  if (!contentKey) return null;
  return db.prepare(`SELECT * FROM bot_trailers WHERE content_key = ?`).get(contentKey) || null;
}
function trailerPut(contentKey, title, youtubeKey) {
  if (!contentKey) return;
  db.prepare(`INSERT INTO bot_trailers (content_key, title, youtube_key, fetched_at)
              VALUES (?, ?, ?, ?)
              ON CONFLICT(content_key) DO UPDATE SET
                title       = excluded.title,
                youtube_key = excluded.youtube_key,
                fetched_at  = excluded.fetched_at`)
    .run(contentKey, title || null, youtubeKey || null, Math.floor(Date.now() / 1000));
}
function _genCode(jid) {
  const base = jidNumber(jid).slice(-4);
  const rand = Math.random().toString(36).slice(2, 6).toUpperCase();
  return `R${base}${rand}`;
}
function ensureReferralCode(jid) {
  const u = getUser(jid);
  if (u.referral_code) return u.referral_code;
  let code = _genCode(jid);
  for (let i = 0; i < 5; i++) {
    try {
      db.prepare(`UPDATE bot_users SET referral_code = ? WHERE jid = ?`).run(code, u.jid);
      return code;
    } catch {
      code = _genCode(jid);
    }
  }
  return code;
}
function setReferrerByCode(jid, code) {
  if (!code) return false;
  const ref = db.prepare(`SELECT jid FROM bot_users WHERE referral_code = ?`).get(code);
  if (!ref) return false;
  const u = getUser(jid);
  if (u.referrer_jid) return false;        
  if (ref.jid === u.jid) return false;      
  db.prepare(`UPDATE bot_users SET referrer_jid = ? WHERE jid = ?`).run(ref.jid, u.jid);
  db.prepare(`UPDATE bot_users SET points = points + 100, daily_quota_mb = daily_quota_mb + 5120 WHERE jid = ?`)
    .run(ref.jid);
  audit('referral.bind', u.jid, `referrer=${ref.jid} code=${code}`);
  return true;
}
function topReferrers(limit = 10) {
  return db.prepare(`
    SELECT u.jid, u.pushname, u.points, COUNT(r.jid) AS referrals
    FROM bot_users u
    LEFT JOIN bot_users r ON r.referrer_jid = u.jid
    GROUP BY u.jid
    HAVING referrals > 0 OR u.points > 0
    ORDER BY referrals DESC, u.points DESC
    LIMIT ?`).all(limit);
}
function getSetting(key, fallback = null) {
  const r = db.prepare(`SELECT value FROM bot_settings WHERE key = ?`).get(key);
  if (!r) return fallback;
  try { return JSON.parse(r.value); } catch { return r.value; }
}
function setSetting(key, value) {
  const v = typeof value === 'string' ? value : JSON.stringify(value);
  db.prepare(`INSERT INTO bot_settings (key, value) VALUES (?, ?)
              ON CONFLICT(key) DO UPDATE SET value = excluded.value`)
    .run(key, v);
}
const _normQuery = q => (q || '').toLowerCase().replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim();
function recordSearch(jid, query) {
  if (!jid || !query) return;
  const norm = jidNumber(jid) + '@s.whatsapp.net';
  const nq   = _normQuery(query);
  db.prepare(`INSERT INTO bot_search_history (jid, query, ts) VALUES (?, ?, ?)`)
    .run(norm, nq, Math.floor(Date.now() / 1000));
  db.prepare(`DELETE FROM bot_search_history WHERE jid = ? AND id NOT IN
              (SELECT id FROM bot_search_history WHERE jid = ? ORDER BY ts DESC LIMIT 200)`)
    .run(norm, norm);
}
function isRepeatSearch(jid, query, windowSec = 600) {
  if (!jid || !query) return false;
  const norm = jidNumber(jid) + '@s.whatsapp.net';
  const nq   = _normQuery(query);
  const since = Math.floor(Date.now() / 1000) - windowSec;
  const row = db.prepare(
    `SELECT id FROM bot_search_history WHERE jid = ? AND query = ? AND ts >= ? ORDER BY ts DESC LIMIT 1`
  ).get(norm, nq, since);
  return !!row;
}
module.exports = {
  db,
  jidNumber,
  mirrorUsersJson,
  touchUser,
  resolveAlias,
  getUser,
  setRole,
  setQuota,
  listUsers,
  audit,
  quotaStatus,
  canDownload,
  recordDownload,
  consumeQuota,
  trailerGet,
  trailerPut,
  ensureReferralCode,
  setReferrerByCode,
  topReferrers,
  getSetting,
  setSetting,
  recordSearch,
  isRepeatSearch,
  saveAlias,
};