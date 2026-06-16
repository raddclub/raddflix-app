'use strict';
/* F3 — Telegram bot mirror.
 *
 * Mirrors the WhatsApp command surface (search / status / popular / trending /
 * recommend) onto Telegram so groups that don't use WhatsApp still get the
 * radd-hub experience.  Uses long-polling so it works behind any NAT.
 *
 * Required env:
 *   TELEGRAM_BOT_TOKEN      from @BotFather
 *   TELEGRAM_ADMIN_IDS      csv of chat ids that bypass the rate limit
 *   STREAM_API              defaults to http://localhost:5000
 */
const fetch = require('node-fetch');
const path  = require('path');
const Database = require('node:sqlite').DatabaseSync;

const TOKEN     = process.env.TELEGRAM_BOT_TOKEN || '';
const STREAM    = process.env.STREAM_API || 'http://localhost:5000/stream';
const ADMINS    = (process.env.TELEGRAM_ADMIN_IDS || '').split(',').map(s=>s.trim()).filter(Boolean);
const POLL_SEC  = 25;
const RATE_LIM  = parseInt(process.env.TG_RATE_LIMIT_PER_MIN || '12', 10);
const DB_PATH   = process.env.RADD_LIBRARY_DB ||
                  path.resolve(__dirname, '..', '..', 'data', 'radd_hub.db');

if (!TOKEN) {
  console.error('TELEGRAM_BOT_TOKEN is required');
  process.exit(1);
}

const API = `https://api.telegram.org/bot${TOKEN}`;

// ---- minimal in-memory rate limiter (per chat id) -------------------------
const _hits = new Map();
function _allow(chatId) {
  if (ADMINS.includes(String(chatId))) return true;
  const now = Date.now(), arr = (_hits.get(chatId) || []).filter(t => t > now - 60000);
  if (arr.length >= RATE_LIM) { _hits.set(chatId, arr); return false; }
  arr.push(now); _hits.set(chatId, arr); return true;
}

// ---- helpers --------------------------------------------------------------
async function tg(method, body) {
  const r = await fetch(`${API}/${method}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return r.json();
}
const send = (chat_id, text, extra = {}) =>
  tg('sendMessage', { chat_id, text, parse_mode: 'Markdown', disable_web_page_preview: true, ...extra });

function _openDb() {
  try { return new Database(DB_PATH, { readOnly: true }); } catch { return null; }
}

// ---- commands -------------------------------------------------------------
async function cmd_help(msg) {
  await send(msg.chat.id,
    '*radd-hub bot*\n' +
    '/search <title> — search the library\n' +
    '/status — your queued downloads\n' +
    '/popular — top-rated titles\n' +
    '/trending — latest uploads\n' +
    '/recommend — personalised suggestions');
}

async function cmd_search(msg, q) {
  if (!q) return send(msg.chat.id, 'usage: /search <title>');
  const base = process.env.STREAM_API || 'http://localhost:5000';
  const r = await fetch(`${base}/library/api/list?q=${encodeURIComponent(q)}&limit=10`, { timeout: 10000 });
  const d = await r.json();
  const items = d || [];
  if (!items.length) return send(msg.chat.id, 'no matches.');
  const body = items.map((x, i) =>
    `${i + 1}. *${x.title}* (${x.year || '?'})\n   /view_${x.id}`
  ).join('\n\n');
  await send(msg.chat.id, body);
}

async function cmd_popular(msg) {
  const db = _openDb();
  if (!db) return send(msg.chat.id, '⚠ library DB unavailable.');
  try {
    const rows = db.prepare(
      'SELECT title,year,rating FROM titles ' +
      'WHERE rating IS NOT NULL ORDER BY rating DESC LIMIT 10'
    ).all();
    if (!rows.length) return send(msg.chat.id, 'no rated titles yet.');
    await send(msg.chat.id, '🌟 *Top picks*\n\n' + rows.map((r, i) =>
      `${i+1}. *${r.title}* (${r.year || '?'}) ★${(+r.rating).toFixed(1)}`
    ).join('\n\n'));
  } finally { try { db.close(); } catch {} }
}

async function cmd_trending(msg) {
  const db = _openDb();
  if (!db) return send(msg.chat.id, '⚠ library DB unavailable.');
  try {
    const rows = db.prepare(
      'SELECT title,year FROM titles ' +
      'ORDER BY created_at DESC LIMIT 10'
    ).all();
    if (!rows.length) return send(msg.chat.id, 'no uploads yet.');
    await send(msg.chat.id, '📈 *Trending now*\n\n' + rows.map((r, i) =>
      `${i+1}. *${r.title}* (${r.year || '?'})`
    ).join('\n\n'));
  } finally { try { db.close(); } catch {} }
}

async function cmd_status(msg) {
  const db = _openDb();
  if (!db) return send(msg.chat.id, '⚠ library DB unavailable.');
  try {
    const rows = db.prepare('SELECT * FROM queue WHERE status NOT IN ("done", "error") ORDER BY updated_at DESC LIMIT 10').all();
    if (!rows.length) return send(msg.chat.id, 'queue is empty.');
    const body = rows.map(r => `• *${r.movie}* — ${r.status} (${Math.round(r.progress||0)}%)`).join('\n');
    await send(msg.chat.id, '📊 *Queue*\n\n' + body);
  } finally { try { db.close(); } catch {} }
}


async function cmd_recommend(msg) {
  try {
    const r = await fetch(`${STREAM}/api/library/recommendations?limit=10`, { timeout: 10000 });
    const d = await r.json();
    const items = d.items || [];
    if (!items.length) return send(msg.chat.id, 'no recommendations yet — add a few titles first.');
    await send(msg.chat.id, '🎯 *Recommended for you*\n\n' + items.map((x, i) => {
      const star = x.rating ? `★${(+x.rating).toFixed(1)}` : '';
      return `${i+1}. *${x.title}* (${x.year || '—'}) ${star}`;
    }).join('\n'));
  } catch (e) {
    await send(msg.chat.id, `recommendation service offline (${e.message}).`);
  }
}

// ---- dispatch -------------------------------------------------------------
async function dispatch(msg) {
  if (!msg.text) return;
  if (!_allow(msg.chat.id))
    return send(msg.chat.id, '⏳ slow down — rate limit (12/min).');
  const t = msg.text.trim();
  if (/^\/(start|help)\b/i.test(t)) return cmd_help(msg);
  let m = t.match(/^\/search\s+(.+)/i);   if (m) return cmd_search(msg, m[1]);
  if (/^\/popular\b/i.test(t))   return cmd_popular(msg);
  if (/^\/trending\b/i.test(t) || /^\/latest\b/i.test(t)) return cmd_trending(msg);
  if (/^\/status\b/i.test(t))    return cmd_status(msg);
  if (/^\/recommend\b/i.test(t)) return cmd_recommend(msg);
  // free-text => search
  return cmd_search(msg, t);
}

// ---- long-poll loop -------------------------------------------------------
async function loop() {
  let offset = 0;
  console.log('[telegram-bot] started, polling…');
  while (true) {
    try {
      const r = await fetch(`${API}/getUpdates?timeout=${POLL_SEC}&offset=${offset}`);
      const d = await r.json();
      for (const u of d.result || []) {
        offset = u.update_id + 1;
        const msg = u.message || u.channel_post;
        if (msg) await dispatch(msg).catch(e => console.error('dispatch:', e));
      }
    } catch (e) {
      console.error('poll error:', e.message);
      await new Promise(res => setTimeout(res, 3000));
    }
  }
}

loop();
