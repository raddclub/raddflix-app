'use strict';
const fetch = require('node-fetch');
const STREAM_API  = process.env.STREAM_API || 'http://localhost:5000';
const BOT_API_KEY = process.env.BOT_API_KEY || '';
const TIMEOUT     = 12000;

// Build headers for every request — include the bot API key so Flask
// lets the bot through @auth.login_required without a browser session.
function _headers(extra = {}) {
  const h = { ...extra };
  if (BOT_API_KEY) h['X-Bot-Key'] = BOT_API_KEY;
  return h;
}

async function _post(path, body) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), TIMEOUT);
  let r;
  try {
    r = await fetch(`${STREAM_API}${path}`, {
      method:  'POST',
      headers: _headers({ 'Content-Type': 'application/json' }),
      body:    JSON.stringify(body || {}),
      signal:  ctrl.signal,
    });
  } finally { clearTimeout(t); }
  let j = null;
  try { j = await r.json(); } catch {}
  return { ok: r.ok, status: r.status, body: j };
}

async function _get(path) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), TIMEOUT);
  let r;
  try {
    r = await fetch(`${STREAM_API}${path}`, {
      headers: _headers(),
      signal:  ctrl.signal,
    });
  } finally { clearTimeout(t); }
  let j = null;
  try { j = await r.json(); } catch {}
  return { ok: r.ok, status: r.status, body: j };
}

async function queueAdd(movieName, opts = {}) {
  // Queue lives in the /stream/ blueprint at /stream/api/queue
  const r = await _post('/stream/api/queue', { movie: movieName, ...opts });
  if (!r.ok) return null;
  const body = r.body || {};
  if (body.job_id) return { job_id: body.job_id, skipped: [], ok: true };
  return body;
}

async function queueGet() {
  const r = await _get('/stream/api/queue');
  if (!r.ok) return [];
  if (Array.isArray(r.body)) return r.body;
  if (r.body && Array.isArray(r.body.jobs)) return r.body.jobs;
  return [];
}

async function submitOtp(otp) {
  const r = await _post('/api/otp/submit', { otp });
  return { ok: r.ok && r.body && r.body.ok !== false, error: r.body && r.body.error };
}

async function otpStatus() {
  const r = await _get('/api/otp/status');
  return r.ok ? r.body : { pending: false };
}

async function libraryHas(query) {
  const r = await _get(`/api/library/has?q=${encodeURIComponent(query)}`);
  if (!r.ok) return null;
  return r.body;
}

async function tmdbCheck(query) {
  const path = query ? `/api/tmdb/check?q=${encodeURIComponent(query)}` : '/api/tmdb/check';
  const r = await _get(path);
  if (!r.ok) return { found: null };
  return r.body || { found: null };
}

async function tmdbRecommendations(tmdbId, mediaType, title, year) {
  try {
    let url;
    if (tmdbId) {
      url = `/api/tmdb/recommendations?tmdb_id=${tmdbId}&media_type=${encodeURIComponent(mediaType || 'movie')}`;
    } else if (title) {
      url = `/api/tmdb/recommendations?title=${encodeURIComponent(title)}${year ? `&year=${year}` : ''}`;
    } else {
      return [];
    }
    const r = await _get(url);
    if (r.ok && r.body && Array.isArray(r.body.results)) return r.body.results;
    return [];
  } catch { return []; }
}

module.exports = {
  queueAdd,
  queueGet,
  submitOtp,
  otpStatus,
  libraryHas,
  tmdbCheck,
  tmdbRecommendations,
  STREAM_API,
  BOT_API_KEY,
};
