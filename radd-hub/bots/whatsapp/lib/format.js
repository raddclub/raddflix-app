'use strict';
const fs    = require('fs');
const path  = require('path');
const fetch = require('node-fetch');
const link4 = require('./link4');
const USERS_FILE = path.join(__dirname, '..', 'users.json');
function loadUsers() {
  try { return JSON.parse(fs.readFileSync(USERS_FILE, 'utf8')); }
  catch { return { admins: [], verified: [], blocked: [], settings: {} }; }
}
function settings() { return loadUsers().settings || {}; }
function fmtSize(val) {
  let n = Number(val || 0);
  if (n <= 0) return '0 B';
  const u = ['B','KB','MB','GB','TB'];
  let i = 0;
  while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
  return `${n.toFixed(n < 10 ? 2 : 1)} ${u[i]}`;
}
function brand() {
  const s = settings();
  return {
    name:    s.brand_name  || 'Radd Movies',
    bot:     s.bot_name    || 'Radd',
    owner:   s.owner_name  || 'Rehan Radd',
    price:   s.price_amount || 500,
    currency: s.currency    || 'PKR',
    period:  s.price_period || 'month',
    pay:     s.payment_instructions || '',
    pitch:   Array.isArray(s.premium_pitch_lines) ? s.premium_pitch_lines : [],
    publicUrl: s.public_url || '',
  };
}
function brandFooter() {
  const b = brand();
  return `\n\n✨ *${b.name}* — _Always for you_`;
}
function premiumPitch(why) {
  const b = brand();
  const lines = [
    `🌟 *Upgrade to ${b.name} Premium*`,
    why ? `_${why}_` : '',
    '',
    ...(b.pitch || []),
    '',
    `💸 *${b.currency} ${b.price} / ${b.period}*`,
    b.pay ? `\n${b.pay}` : '',
  ].filter(Boolean);
  return lines.join('\n');
}
const _posterCache = new Map();
function posterUrl(p) {
  if (!p) return '';
  if (/^https?:\/\//.test(p)) return p;
  const cleaned = String(p).replace(/^\/+/, '');
  return `https://image.tmdb.org/t/p/w500/${cleaned}`;
}
async function fetchPoster(url) {
  if (!url) return null;
  if (_posterCache.has(url)) return _posterCache.get(url);
  try {
    const r = await fetch(url, { timeout: 8000 });
    if (!r.ok) return null;
    const buf = await r.buffer();
    _posterCache.set(url, buf);
    return buf;
  } catch { return null; }
}
async function getDownloadLink(row, role = 'free') {
  if (!row) return '';
  if (role === 'admin' && row.share_url) {
    return row.share_url;
  }
  if (row.share_url) {
    try {
      const link = await link4.getLink4ByShareUrl(row.share_url, row.name);
      if (link) return link;
    } catch (e) {
      console.warn(`[format] link4 failed for "${row.name}": ${e.message}`);
    }
  }
  return row.download_url || row.share_url || '';
}
const safeDownloadLink = getDownloadLink;
async function fmtUploadCaption(r, role = 'free') {
  const title = r.tmdb_title
    ? `${r.tmdb_title}${r.tmdb_year ? ` (${r.tmdb_year})` : ''}`
    : (r.name || 'Untitled');
  const finalLink = await getDownloadLink(r, role);
  const linkLabel = role === 'admin'
    ? '*Admin Folder Link:*'
    : '*Watch / Download:*';
  const rating = r.tmdb_rating ? `⭐ ${parseFloat(r.tmdb_rating).toFixed(1)}/10` : '';
  const size   = r.size_bytes  ? `💾 ${fmtSize(r.size_bytes)}` : '';
  const kind   = r.mediatype || r.media_type || 'file';
  const genres = r.genres_csv
    ? `🎭 ${r.genres_csv.split(',').slice(0, 4).map(g => g.trim()).filter(Boolean).join(' · ')}`
    : '';
  const director = r.director ? `🎬 _Dir: ${r.director}_` : '';
  const cast = r.cast_names
    ? `👥 _${r.cast_names.split(',').slice(0, 4).map(c => c.trim()).filter(Boolean).join(', ')}_`
    : '';
  const epInfo = (r.season && r.episode)
    ? `📺 Season ${r.season} Episode ${r.episode}`
    : '';
  const lines = [
    `🎬 *${title}*`,
    epInfo,
    [rating, size, kind].filter(Boolean).join('  ·  '),
    genres,
    director,
    cast,
    finalLink
      ? `\n🔗 ${linkLabel}\n${finalLink}`
      : '\n🔗 _Link unavailable — try again in a minute._',
    r.tmdb_overview
      ? `\n_${String(r.tmdb_overview).slice(0, 220)}${r.tmdb_overview.length > 220 ? '…' : ''}_`
      : '',
  ].filter(Boolean);
  return lines.join('\n') + brandFooter();
}
function fmtListItem(r) {
  const title = r.tmdb_title || r.name;
  const year  = r.tmdb_year ? ` (${r.tmdb_year})` : '';
  return `• *${title}*${year}  _${fmtSize(r.size_bytes)}_`;
}
async function sendBranded(sock, jid, row, caption, ctx) {
  const url = posterUrl(row && row.tmdb_poster);
  const buf = await fetchPoster(url);
  if (buf) {
    return sock.sendMessage(jid, { image: buf, caption }, { quoted: ctx });
  }
  return sock.sendMessage(jid, { text: caption }, { quoted: ctx });
}
function helpText(role) {
  const b = brand();
  const SEP = `┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄`;
  const lines = [
    `╔══════════════════════╗`,
    `║  🎬  ${b.name.toUpperCase().slice(0,16).padEnd(16)}  ║`,
    `╚══════════════════════╝`,
    ``,
  ];

  if (role === 'free') {
    lines.push(
      `🔓 *How It Works*`,
      SEP,
      `Just type a movie or series name.`,
      `We'll search our cloud library instantly.`,
      ``,
      `💎 *Want to download?*`,
      `→ Type */price* to unlock Premium`,
      ``,
    );
  }

  if (role === 'verified' || role === 'admin') {
    lines.push(
      `💎 *PREMIUM — Quick Start*`,
      SEP,
      `✦ Type *any movie name* → get the link`,
      `✦ Type it *twice* → force re-search`,
      `✦ */quota* → check your daily usage`,
      `✦ */download <id>* → refresh a link`,
      ``,
    );
  }

  lines.push(
    `🔍 *SEARCH*`,
    SEP,
    `• Just type a title name`,
    `• */find <name>* — explicit search`,
    `• *!<name>*  or  */force <name>* — skip cache`,
    ``,
    `📺 *BROWSE LIBRARY*`,
    SEP,
    `• */latest*  — today's new additions`,
    `• */list*  — newest 10 in cloud`,
    `• */top*  — highest-rated titles`,
    `• */random*  — surprise me 🎲`,
    ``,
    `🎯 *DISCOVER*`,
    SEP,
    `• */actor <name>*  — films by actor`,
    `• */genre <name>*  — e.g. Action, Drama`,
    `• */director <name>*  — by director`,
    `• */year <year>*  — by release year`,
    `• */similar <title>*  — "more like this"`,
    ``,
    `ℹ️ *INFO & STATUS*`,
    SEP,
    `• */trailer <name>*  — watch trailer`,
    `• */trending*  — vote for next upload`,
    `• */queue*  — pending downloads`,
    `• */count*  — library size`,
    `• */me*  — your account info`,
    `• */price*  — plans & pricing`,
    ``,
  );

  if (role === 'admin') {
    lines.push(
      `👑 *ADMIN*`,
      SEP,
      `• */admin*  — management dashboard`,
      `• */otp <code>*  — submit JazzDrive OTP`,
      `• */relogin*  — refresh cloud session`,
      `• */status*  — system health check`,
      ``,
    );
  }

  lines.push(`━━━━━━━━━━━━━━━━━━━━`);
  return lines.join('\n') + brandFooter();
}
module.exports = {
  settings,
  brand,
  brandFooter,
  premiumPitch,
  fmtSize,
  posterUrl,
  fetchPoster,
  fmtUploadCaption,
  fmtListItem,
  sendBranded,
  helpText,
  safeDownloadLink,    
  getDownloadLink,
};