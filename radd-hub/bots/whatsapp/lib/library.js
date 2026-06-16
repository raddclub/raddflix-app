'use strict';
const path    = require('path');
const fs      = require('fs');
const SQLite3 = require('better-sqlite3');

const HUB_ROOT  = path.resolve(__dirname, '..', '..', '..');
const MEDIA_DB  = path.join(HUB_ROOT, 'data', 'radd_hub.db');

let _mediaDb = null;

function openMediaDb() {
  if (_mediaDb) return _mediaDb;
  if (!fs.existsSync(MEDIA_DB)) {
    console.error(`[library] Database not found: ${MEDIA_DB}`);
    return null;
  }
  try {
    _mediaDb = new SQLite3(MEDIA_DB, { readonly: true });
    return _mediaDb;
  } catch (e) {
    console.error(`[library] Database open failed: ${e.message}`);
    return null;
  }
}

const norm = s => (s || '').toLowerCase()
  .replace(/\b(19|20)\d{2}\b/g, ' ')
  .replace(/[^a-z0-9 ]+/g, ' ')
  .replace(/\s+/g, ' ').trim();

const tokens = s => norm(s).split(' ').filter(w => w.length > 1 || /^\d+$/.test(w));

function _mediaDbSearch(query, limit = 20) {
  const d = openMediaDb();
  if (!d) return [];
  const want = tokens(query);
  if (!want.length) return [];

  const pct = want.map(() => 'LOWER(t.title) LIKE ?').join(' AND ');
  const castPct = want.map(() => 'LOWER(t.cast_names) LIKE ?').join(' AND ');
  const filePct = want.map(() => 'LOWER(f.filename) LIKE ?').join(' AND ');
  
  const params = [];
  want.forEach(t => params.push(`%${t}%`)); 
  want.forEach(t => params.push(`%${t}%`)); 
  want.forEach(t => params.push(`%${t}%`)); 

  try {
    const rows = d.prepare(`
      SELECT t.id AS title_id, t.title AS tmdb_title, t.year AS tmdb_year,
             t.rating AS tmdb_rating, t.poster AS tmdb_poster, t.overview AS tmdb_overview,
             t.cast_names, t.director, t.genres_csv, t.media_type,
             f.filename AS name, f.size_bytes, f.share_url, f.share_key,
             f.download_url, f.remote_id, f.remote_file_id, f.season, f.episode,
             f.fingerprint, f.folder_path, f.source
      FROM files f
      LEFT JOIN titles t ON f.title_id = t.id
      WHERE f.is_ready = 1 AND (
        (t.id IS NOT NULL AND ((${pct}) OR (${castPct})))
        OR (${filePct})
      )
      ORDER BY COALESCE(t.rating, 0) DESC, f.uploaded_at DESC
      LIMIT ?`).all(...params, limit * 5);

    const scored = rows.map(r => {
      const hay = norm(`${r.tmdb_title || ''} ${r.name}`);
      const sc = want.filter(t => hay.includes(t)).length;
      return { ...r, _score: sc, _source: 'media_db' };
    }).filter(r => r._score > 0)
      .sort((a, b) => b._score - a._score || (b.tmdb_rating || 0) - (a.tmdb_rating || 0));

    return scored.slice(0, limit);
  } catch (e) {
    console.error(`[library] Search error: ${e.message}`);
    return [];
  }
}

function searchLibrary(query, limit = 20) {
  return _mediaDbSearch(query, limit);
}

function searchByActor(actorName, limit = 15) {
  const d = openMediaDb();
  if (!d) return [];
  try {
    const rows = d.prepare(`
      SELECT t.id AS title_id, t.title AS tmdb_title, t.year AS tmdb_year,
             t.rating AS tmdb_rating, t.poster AS tmdb_poster, t.overview AS tmdb_overview,
             t.cast_names, t.director, t.genres_csv, t.media_type,
             f.filename AS name, f.size_bytes, f.share_url, f.download_url,
             f.remote_id, f.remote_file_id, f.season, f.episode, f.fingerprint
      FROM titles t
      JOIN files f ON f.title_id = t.id AND f.is_ready = 1
      WHERE LOWER(t.cast_names) LIKE ?
      ORDER BY t.rating DESC LIMIT ?
    `).all(`%${actorName.toLowerCase()}%`, limit);
    return rows.map(r => ({...r, _source: 'media_db'}));
  } catch { return []; }
}

function searchByGenre(genre, limit = 15) {
  const d = openMediaDb();
  if (!d) return [];
  try {
    const rows = d.prepare(`
      SELECT t.id AS title_id, t.title AS tmdb_title, t.year AS tmdb_year,
             t.rating AS tmdb_rating, t.poster AS tmdb_poster, t.overview AS tmdb_overview,
             t.cast_names, t.director, t.genres_csv, t.media_type,
             f.filename AS name, f.size_bytes, f.share_url, f.download_url,
             f.remote_id, f.remote_file_id, f.season, f.episode, f.fingerprint
      FROM titles t
      JOIN files f ON f.title_id = t.id AND f.is_ready = 1
      WHERE LOWER(t.genres_csv) LIKE ?
      ORDER BY t.rating DESC LIMIT ?
    `).all(`%${genre.toLowerCase()}%`, limit);
    return rows.map(r => ({...r, _source: 'media_db'}));
  } catch { return []; }
}

function searchByDirector(directorName, limit = 15) {
  const d = openMediaDb();
  if (!d) return [];
  try {
    const rows = d.prepare(`
      SELECT t.id AS title_id, t.title AS tmdb_title, t.year AS tmdb_year,
             t.rating AS tmdb_rating, t.poster AS tmdb_poster, t.overview AS tmdb_overview,
             t.cast_names, t.director, t.genres_csv, t.media_type,
             f.filename AS name, f.size_bytes, f.share_url, f.download_url,
             f.remote_id, f.remote_file_id, f.season, f.episode, f.fingerprint
      FROM titles t
      JOIN files f ON f.title_id = t.id AND f.is_ready = 1
      WHERE LOWER(t.director) LIKE ?
      ORDER BY t.rating DESC LIMIT ?
    `).all(`%${directorName.toLowerCase()}%`, limit);
    return rows.map(r => ({...r, _source: 'media_db'}));
  } catch { return []; }
}

function searchByYear(year, limit = 15) {
  const d = openMediaDb();
  if (!d) return [];
  try {
    const rows = d.prepare(`
      SELECT t.id AS title_id, t.title AS tmdb_title, t.year AS tmdb_year,
             t.rating AS tmdb_rating, t.poster AS tmdb_poster, t.genres_csv,
             t.cast_names, t.director, t.media_type,
             f.filename AS name, f.size_bytes, f.share_url, f.download_url,
             f.remote_id, f.remote_file_id, f.season, f.episode, f.fingerprint
      FROM titles t
      JOIN files f ON f.title_id = t.id AND f.is_ready = 1
      WHERE t.year = ?
      ORDER BY t.rating DESC LIMIT ?
    `).all(year, limit);
    return rows.map(r => ({...r, _source: 'media_db'}));
  } catch { return []; }
}

function getTopRated(limit = 10) {
  const d = openMediaDb();
  if (!d) return [];
  try {
    const rows = d.prepare(`
      SELECT t.id AS title_id, t.title AS tmdb_title, t.year AS tmdb_year,
             t.rating AS tmdb_rating, t.poster AS tmdb_poster, t.genres_csv,
             t.media_type, f.filename AS name, f.size_bytes, f.share_url, f.download_url,
             f.fingerprint
      FROM titles t
      JOIN files f ON f.title_id = t.id AND f.is_ready = 1
      WHERE t.rating > 7.0
      ORDER BY t.rating DESC LIMIT ?`).all(limit);
    return rows.map(r => ({...r, _source: 'media_db'}));
  } catch { return []; }
}

function getRandomTitle() {
  const d = openMediaDb();
  if (!d) return null;
  try {
    const r = d.prepare(`
      SELECT t.id AS title_id, t.title AS tmdb_title, t.year AS tmdb_year,
             t.rating AS tmdb_rating, t.poster AS tmdb_poster, t.genres_csv,
             t.overview AS tmdb_overview, t.media_type,
             f.filename AS name, f.size_bytes, f.share_url, f.download_url,
             f.fingerprint
      FROM titles t
      JOIN files f ON f.title_id = t.id AND f.is_ready = 1
      WHERE t.id IN (SELECT id FROM titles ORDER BY RANDOM() LIMIT 1)
      LIMIT 1`).get();
    return r ? {...r, _source: 'media_db'} : null;
  } catch { return null; }
}

function recentLibrary(limit = 10) {
  const d = openMediaDb();
  if (!d) return [];
  try {
    const rows = d.prepare(`
      SELECT t.title AS tmdb_title, t.year AS tmdb_year, f.filename AS name,
             f.size_bytes, f.share_url, f.download_url, f.uploaded_at, f.fingerprint
      FROM files f
      LEFT JOIN titles t ON f.title_id = t.id
      WHERE f.is_ready = 1
      ORDER BY f.uploaded_at DESC LIMIT ?`).all(limit);
    return rows.map(r => ({...r, _source: 'media_db'}));
  } catch { return []; }
}

function getLatestToday(limit = 5) {
  const d = openMediaDb();
  if (!d) return [];
  try {
    const dayAgo = Math.floor(Date.now() / 1000) - (24 * 3600);
    const rows = d.prepare(`
      SELECT t.title AS tmdb_title, t.year AS tmdb_year, f.filename AS name,
             f.size_bytes, f.uploaded_at
      FROM files f
      LEFT JOIN titles t ON f.title_id = t.id
      WHERE f.is_ready = 1 AND f.uploaded_at > ?
      ORDER BY f.uploaded_at DESC LIMIT ?`).all(dayAgo, limit);
    return rows.length ? rows : recentLibrary(limit);
  } catch { return recentLibrary(limit); }
}

function libraryStats() {
  const d = openMediaDb();
  if (!d) return { total_files: 0, total_size: 0, last_upload: 0 };
  try {
    const r = d.prepare(`
      SELECT COUNT(*) AS total_files, SUM(size_bytes) AS total_size,
             MAX(uploaded_at) AS last_upload
      FROM files WHERE is_ready = 1`).get();
    return {
      total_files: r.total_files || 0,
      total_size: r.total_size || 0,
      last_upload: r.last_upload || 0
    };
  } catch { return { total_files: 0, total_size: 0, last_upload: 0 }; }
}

function findGroupEpisodes(parentGroupId) {
  const d = openMediaDb();
  if (!d || !parentGroupId) return [];
  try {
    const rows = d.prepare(`
      SELECT fingerprint, filename AS name, season, episode, size_bytes, share_url,
             download_url, remote_id, remote_file_id
      FROM files
      WHERE title_id = ? AND is_ready = 1
      ORDER BY COALESCE(season, 0), COALESCE(episode, 0), filename`).all(parentGroupId);
    return rows;
  } catch { return []; }
}

function findByContentKey(contentKey) {
  const d = openMediaDb();
  if (!d || !contentKey) return [];
  try {
    return d.prepare(`
      SELECT f.fingerprint, f.filename AS name, f.season, f.episode, f.size_bytes,
             f.share_url, f.download_url, f.remote_id, f.remote_file_id,
             t.title AS tmdb_title, t.year AS tmdb_year, t.poster AS tmdb_poster
      FROM files f
      LEFT JOIN titles t ON f.title_id = t.id
      WHERE f.fingerprint = ?
      ORDER BY COALESCE(f.season, 0), COALESCE(f.episode, 0)`).all(contentKey);
  } catch { return []; }
}

function flixSession() {
  const d = openMediaDb();
  if (!d) return { logged_in: false, hours_left: 0, msisdn: '' };
  try {
    const acct = d.prepare(
      `SELECT msisdn, validation_key, jsessionid, token_expires_at FROM accounts WHERE is_active=1 LIMIT 1`
    ).get();
    if (!acct || !acct.validation_key) return { logged_in: false, hours_left: 0, msisdn: '' };
    const exp = Number(acct.token_expires_at || 0);
    const hoursLeft = exp > 0 ? Math.max(0, (exp - Date.now() / 1000) / 3600) : 0;
    return {
      logged_in: !!acct.validation_key && (exp === 0 || exp > Date.now() / 1000),
      hours_left: Math.round(hoursLeft * 10) / 10,
      msisdn: acct.msisdn || '',
    };
  } catch { return { logged_in: false, hours_left: 0, msisdn: '' }; }
}

module.exports = {
  norm,
  tokens,
  openMediaDb,
  searchLibrary,
  searchByActor,
  searchByGenre,
  searchByDirector,
  searchByYear,
  getTopRated,
  getRandomTitle,
  recentLibrary,
  getLatestToday,
  libraryStats,
  findGroupEpisodes,
  findByContentKey,
  flixSession,
  paths: { MEDIA_DB },
};
