'use strict';
const path  = require('path');
const fs    = require('fs');
const fetch = require('node-fetch');
const db_lib = require('./db');
function _tmdbKey() {
  try {
    const val = db_lib.getSetting ? db_lib.getSetting('TMDB_KEY') : '';
    if (val) return val;
  } catch {}
  return process.env.TMDB_KEY || '';
}
async function _tmdbSearch(query, kind) {
  const key = _tmdbKey();
  if (!key) return null;
  const ep = kind === 'tv' ? 'tv' : 'movie';
  const url = `https://api.themoviedb.org/3/search/${ep}?api_key=${encodeURIComponent(key)}&query=${encodeURIComponent(query)}&include_adult=false`;
  try {
    const r = await fetch(url, { timeout: 8000 });
    if (!r.ok) return null;
    const j = await r.json();
    return (j.results && j.results[0]) || null;
  } catch { return null; }
}
async function _tmdbVideos(id, kind) {
  const key = _tmdbKey();
  if (!key) return [];
  const ep = kind === 'tv' ? 'tv' : 'movie';
  const url = `https://api.themoviedb.org/3/${ep}/${id}/videos?api_key=${encodeURIComponent(key)}`;
  try {
    const r = await fetch(url, { timeout: 8000 });
    if (!r.ok) return [];
    const j = await r.json();
    return Array.isArray(j.results) ? j.results : [];
  } catch { return []; }
}
function _pickTrailer(videos) {
  if (!videos || !videos.length) return null;
  const yt = videos.filter(v => (v.site || '').toLowerCase() === 'youtube');
  const tr = yt.filter(v => (v.type || '').toLowerCase() === 'trailer' && v.official);
  if (tr[0]) return tr[0];
  const any = yt.filter(v => (v.type || '').toLowerCase() === 'trailer');
  if (any[0]) return any[0];
  return yt[0] || null;
}
async function lookupTrailer({ contentKey, title, year, kind = 'movie' }) {
  if (!title) return null;
  if (contentKey) {
    const cached = db.trailerGet(contentKey);
    if (cached && cached.youtube_key) {
      return { youtube_key: cached.youtube_key, title: cached.title, cached: true };
    }
  }
  const q = year ? `${title} ${year}` : title;
  const result = await _tmdbSearch(q, kind);
  if (!result) {
    return { youtube_key: '', title, search_url: `https://www.youtube.com/results?search_query=${encodeURIComponent(q + ' trailer')}` };
  }
  const videos = await _tmdbVideos(result.id, kind);
  const t = _pickTrailer(videos);
  const youtubeKey = t ? t.key : '';
  if (contentKey) db.trailerPut(contentKey, title, youtubeKey);
  return {
    youtube_key: youtubeKey,
    title:       result.title || result.name || title,
    overview:    result.overview || '',
    poster:      result.poster_path || '',
    cached:      false,
    search_url:  `https://www.youtube.com/results?search_query=${encodeURIComponent(q + ' trailer')}`,
  };
}
function buildTrailerMessage(t, brandFooter) {
  if (!t || (!t.youtube_key && !t.search_url)) {
    return `Sorry, I couldn't find a trailer for that title.${brandFooter || ''}`;
  }
  const url = t.youtube_key
    ? `https://www.youtube.com/watch?v=${t.youtube_key}`
    : t.search_url;
  const lines = [
    `🎞 *Trailer — ${t.title}*`,
    t.overview ? `\n_${String(t.overview).slice(0, 220)}${t.overview.length > 220 ? '…' : ''}_` : '',
    '',
    `▶️ ${url}`,
  ].filter(Boolean);
  return lines.join('\n') + (brandFooter || '');
}
module.exports = { lookupTrailer, buildTrailerMessage };