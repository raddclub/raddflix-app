const {
  default: makeWASocket,
  useMultiFileAuthState,
  DisconnectReason,
  fetchLatestBaileysVersion,
} = require('@whiskeysockets/baileys');
const SQLite3 = require('better-sqlite3');
const fetch     = require('node-fetch');
const pino      = require('pino');
const qrTerm    = require('qrcode-terminal');
const QRCode    = require('qrcode');
const path      = require('path');
const fs        = require('fs');
const os        = require('os');
const rolesLib        = require('./lib/roles');
const botDb           = require('./lib/db');
const { PluginManager } = require('./lib/pluginManager');
const intent          = require('./lib/intent');
const _rateLimit      = require('./lib/rateLimit');                 // audit S4
const library         = require('./lib/library');
const ROOT         = path.resolve(__dirname, '..');
const STREAM_API   = process.env.STREAM_API || 'http://localhost:5000';
const DBGEN_API    = process.env.DBGEN_API || 'http://localhost:5002';
const FLIXPRO_API  = process.env.FLIXPRO_API || 'http://localhost:5001';
const AUTH_DIR     = path.join(__dirname, 'auth_info');
const QR_PNG       = path.join(__dirname, 'whatsapp-qr.png');
const REQ_DB       = path.join(__dirname, 'requests.db');
const USERS_FILE   = path.join(__dirname, 'users.json');
const STATE_FILE   = path.join(__dirname, 'bot-state.json');
const RELINK_FILE      = path.join(__dirname, '.relink');
const PAIRING_NUM_FILE = path.join(__dirname, 'pairing-number.txt');
const PAIRING_REQ_FILE = path.join(__dirname, '.pairing-request'); 
let _currentSock   = null;
let _currentMsisdn = '';
let _pairingCodeRef = { value: null, requested: false }; 
let _persistedBotNum = '';
let _persistedBotLid = '';
const _seenMsgIds = new Set();
setInterval(() => { if (_seenMsgIds.size > 1000) _seenMsgIds.clear(); }, 5 * 60_000);
const TMP            = os.tmpdir();
const OTP_PENDING    = path.join(TMP, 'radd_flix_otp_pending.json'); 
const OTP_DMD        = path.join(TMP, 'radd_bot_last_otp_dmd.txt');  
const SESSION_DEAD   = path.join(TMP, 'radd_flix_session_dead.json');  
const SESSION_ALIVE  = path.join(TMP, 'radd_flix_session_alive.json'); 
const DEAD_DMD       = path.join(TMP, 'radd_bot_last_dead_dmd.txt');   
const WEBCMD_DIR     = path.join(TMP, 'radd_bot_cmd');                 
try { fs.mkdirSync(WEBCMD_DIR, { recursive: true }); } catch {}
try { if (fs.existsSync(OTP_DMD))  fs.unlinkSync(OTP_DMD); } catch {}
try { if (fs.existsSync(DEAD_DMD)) fs.unlinkSync(DEAD_DMD); } catch {}
const reqDb = new SQLite3(REQ_DB);
reqDb.exec(`CREATE TABLE IF NOT EXISTS pending (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  jid TEXT NOT NULL, user TEXT, requester_jid TEXT,
  query TEXT NOT NULL, norm TEXT NOT NULL,
  job_id TEXT, msg_id TEXT, msg_participant TEXT,
  created_at INTEGER NOT NULL, notified INTEGER DEFAULT 0
);`);
try { reqDb.exec(`ALTER TABLE pending ADD COLUMN requester_jid TEXT`); } catch {}
try { reqDb.exec(`CREATE TABLE IF NOT EXISTS bot_status_index (
  fingerprint TEXT PRIMARY KEY,
  user_jid TEXT,
  title TEXT,
  state TEXT,
  progress_pct REAL DEFAULT 0,
  detail TEXT,
  created_at INTEGER,
  updated_at INTEGER
)`); } catch {}
const DEBUG_LOG = path.join(__dirname, 'bot-debug.log');
function debug(m) {
  const line = `[${new Date().toISOString()}] ${m}`;
  console.log(line);
}
function loadUsers() {
  try { return JSON.parse(fs.readFileSync(USERS_FILE, 'utf8')); }
  catch { return { admins: [], verified: [], blocked: [], settings: {} }; }
}
function saveUsers(u) {
  fs.writeFileSync(USERS_FILE, JSON.stringify(u, null, 2));
}
function jidNumber(j) { return (j || '').split('@')[0].split(':')[0]; }
function numberToJid(n) {
  const clean = String(n || '').replace(/[^\d]/g, '');
  return clean + '@s.whatsapp.net';
}
function settings()   { return loadUsers().settings || {}; }
let _lastDisconnect = null;
let _lastStatusReportAt = 0;
const _serviceState = {};      
let   _serviceMonitorBooted = false;
function _disconnectReasonName(code) {
  const map = {
    401: 'loggedOut',
    408: 'timedOut',
    411: 'multideviceMismatch',
    428: 'connectionClosed',
    440: 'connectionReplaced',
    500: 'badSession',
    503: 'restartRequired',
    515: 'streamError',
  };
  return map[code] || `code ${code || 'unknown'}`;
}
async function _hubFetch(url, options = {}) {
  const botKey = process.env.BOT_API_KEY || '';
  const headers = {
    ...options.headers,
    ...(botKey ? { 'X-Bot-Key': botKey } : {}),
  };
  return fetch(url, { ...options, headers });
}

async function _httpProbe(url, timeoutMs = 2500) {
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), timeoutMs);
    const res = await _hubFetch(url, { signal: ctrl.signal, timeout: timeoutMs });
    clearTimeout(t);
    return { ok: res.ok, status: res.status };
  } catch (e) {
    return { ok: false, status: 0, error: e.message || String(e) };
  }
}
async function checkAllServices() {
  // Use /api/ping (no auth) for the liveness check, and /api/status (auth
  // handled via X-Bot-Key header in _httpProbe) for the hub-status check.
  const checks = await Promise.all([
    _httpProbe(`${STREAM_API}/api/ping`),
    _httpProbe(`${STREAM_API}/api/status`),
  ]);
  return {
    raddHub:   checks[0],
    hubStatus: checks[1],
  };
}
function _statusLine(label, probe) {
  const icon = probe.ok ? '✅' : '❌';
  const detail = probe.ok ? `${probe.status}` : (probe.error ? 'down' : `HTTP ${probe.status}`);
  return `${icon} ${label} — ${detail}`;
}
function buildStatusReport(status, botJid) {
  const ts = new Date().toLocaleString('en-GB', { hour12: false });
  const num = jidNumber(botJid);
  const lines = [
    `🤖 *${brand().name} bot is ONLINE*`,
    `📞 Number: +${num}`,
    `🕒 Time:   ${ts}`,
  ];
  if (_lastDisconnect) {
    const d = _lastDisconnect;
    lines.push(``,
      `⚠️ *Previous disconnect:*`,
      `   • Reason: ${d.reason} (code ${d.code})`,
      `   • Detail: ${d.message}`,
      `   • At:     ${d.at}`,
    );
    if (d.reason === 'connectionReplaced') {
      lines.push(`   • Hint: another WhatsApp Web session took over this bot. Keep only one active bot session.`);
    }
    _lastDisconnect = null; 
  }
  lines.push(``,
    `*Service status:*`,
    _statusLine('Radd Hub v3', status.raddHub),
    _statusLine('Hub Status',  status.hubStatus),
  );
  return lines.join('\n');
}
function startServiceMonitor(getSock, getBotJid) {
  if (_serviceMonitorBooted) return;
  _serviceMonitorBooted = true;
  const LABELS = {
    raddHub:   'Radd Hub v3',
    hubStatus: 'Hub Status',
  };
  const tick = async () => {
    try {
      const status = await checkAllServices();
      const flips = [];
      for (const key of Object.keys(LABELS)) {
        const now = !!status[key].ok;
        const prev = _serviceState[key];
        if (prev === undefined) {
          _serviceState[key] = now;
          continue;
        }
        if (prev !== now) {
          flips.push({ key, label: LABELS[key], up: now, probe: status[key] });
          _serviceState[key] = now;
        }
      }
      if (!flips.length) return;
      const sock = getSock?.();
      const botJid = getBotJid?.();
      if (!sock || !botJid) return;
      const targets = resolveAdminTargets(botJid);
      if (!targets.length) return;
      const ts = new Date().toLocaleString('en-GB', { hour12: false });
      const lines = [`🔔 *Service alert* — ${ts}`];
      for (const f of flips) {
        if (f.up) {
          lines.push(`✅ ${f.label} is back UP (HTTP ${f.probe.status})`);
        } else {
          lines.push(`❌ ${f.label} went DOWN (${f.probe.error || 'HTTP ' + f.probe.status})`);
        }
      }
      const text = lines.join('\n');
      const send = sock._realSendMessage || sock.sendMessage.bind(sock);
      for (const jid of targets) {
        try {
          await send(jid, { text }, { skipDelay: true });
          debug(`[STATUS] Service-flip alert sent to ${jid}`);
        } catch (e) {
          debug(`[STATUS] Flip alert DM failed for ${jid}: ${e.message || e}`);
        }
      }
    } catch (e) {
      debug(`[STATUS] Monitor tick error: ${e.message || e}`);
    }
  };
  setTimeout(() => { tick(); setInterval(tick, 60_000); }, 30_000);
  debug('[STATUS] Service monitor started (60s interval).');
}
function resolveAdminTargets(botJid) {
  const targets = new Set();
  try {
    const u = loadUsers();
    for (const a of (u.admins || [])) targets.add(a);
  } catch {}
  try {
    const env = String(process.env.BOT_ADMIN_NUMBERS || '').trim();
    if (env) {
      for (const raw of env.split(',')) {
        const n = raw.replace(/[^\d]/g, '');
        if (n.length >= 10) targets.add(numberToJid(n));
      }
    }
  } catch {}
  if (targets.size === 0 && botJid) {
    const num = jidNumber(botJid);
    if (num) targets.add(numberToJid(num));
  }
  return Array.from(targets);
}
function writeBotState(state, detail = '') {
  try {
    fs.writeFileSync(STATE_FILE, JSON.stringify({
      connected: !!state.connected,
      running: !!state.running,
      pairing_code: _pairingCodeRef.value || null,
      bot_number: _persistedBotNum || '',
      bot_lid: _persistedBotLid || '',
      last_disconnect: _lastDisconnect,
      updated_at: Date.now(),
    }, null, 2));
  } catch {}
  try {
    const now = Math.floor(Date.now() / 1000);
    reqDb.exec(`CREATE TABLE IF NOT EXISTS bot_status_kv (
      key TEXT PRIMARY KEY,
      value TEXT,
      updated_at INTEGER
    )`);
    reqDb.prepare(`
      INSERT INTO bot_status_index
        (fingerprint, user_jid, title, state, progress_pct, detail, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(fingerprint) DO UPDATE SET
        user_jid = excluded.user_jid,
        title = excluded.title,
        state = excluded.state,
        progress_pct = excluded.progress_pct,
        detail = excluded.detail,
        updated_at = excluded.updated_at
    `).run(
      'wa-bot-state',
      state.user_jid || '',
      'WhatsApp bot',
      state.connected ? 'connected' : (state.running ? 'connecting' : 'stopped'),
      state.connected ? 100 : 0,
      detail || '',
      now,
      now,
    );
    reqDb.prepare(`
      INSERT INTO bot_status_kv (key, value, updated_at)
      VALUES (?, ?, ?)
      ON CONFLICT(key) DO UPDATE SET
        value = excluded.value,
        updated_at = excluded.updated_at
    `).run('wa_state', state.connected ? 'connected' : (state.running ? 'connecting' : 'closed'), now);
  } catch {}
}
const norm = s => (s || '').toLowerCase()
  .replace(/\b(19|20)\d{2}\b/g, ' ')
  .replace(/[^a-z0-9 ]+/g, ' ')
  .replace(/\s+/g, ' ').trim();
const tokens = s => norm(s).split(' ').filter(w => w.length > 1);
function fmtSize(val) {
  let n = Number(val || 0);
  if (n <= 0) return '0 B';
  const u = ['B','KB','MB','GB','TB']; let i = 0;
  while (n >= 1024 && i < u.length-1) { n /= 1024; i++; }
  return `${n.toFixed(n < 10 && i > 0 ? 1 : 0)} ${u[i]}`;
}
function searchLibrary(query, limit = 20) {
  return library.searchLibrary(query, limit);
}
function recentLibrary(limit = 10) {
  return library.recentLibrary ? library.recentLibrary(limit) : library.searchLibrary('', limit);
}
function libraryStats() {
  return library.libraryStats ? library.libraryStats() : { total: 0, by_kind: {}, total_size: 0 };
}
async function flixSession() {
  try {
    const r = await _hubFetch(`${STREAM_API}/api/jazzdrive/status`, { timeout: 4000 });
    if (r.ok) {
      const d = await r.json();
      const exp = Number(d.expires_at || 0);
      return {
        msisdn: d.msisdn || '',
        logged_in: d.status === 'connected' && (exp === 0 || exp > Date.now()/1000),
        hours_left: exp ? Math.max(0, ((exp - Date.now()/1000) / 3600)).toFixed(1) : '0',
      };
    }
  } catch {}
  return { msisdn: process.env.JAZZDRIVE_MSISDN || '', logged_in: false, hours_left: '0' };
}
async function streamQueueAdd(movieName) {
  const r = await _hubFetch(`${STREAM_API}/api/queue/add`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name: movieName }),
  });
  if (!r.ok) throw new Error(`queue add HTTP ${r.status}`);
  const j = await r.json();
  return (j.added && j.added[0] && j.added[0].id) || j.job_id || null;
}
async function streamQueueGet() {
  try {
    const r = await _hubFetch(`${STREAM_API}/stream/api/queue`);
    const j = await r.json();
    return j.queue || j.jobs || [];
  } catch { return []; }
}
async function streamSubmitOtp(otp) {
  const r = await _hubFetch(`${STREAM_API}/api/otp/submit`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ otp }),
  });
  return r.json().catch(() => ({ ok: false, error: 'invalid response' }));
}
async function streamOtpStatus() {
  try { return await (await _hubFetch(`${STREAM_API}/api/otp/status`)).json(); }
  catch { return { pending: false }; }
}
function posterUrl(p) {
  if (!p) return null;
  if (/^https?:\/\//.test(p)) return p;
  if (p.startsWith('/')) return `https://image.tmdb.org/t/p/w500${p}`;
  return `https://image.tmdb.org/t/p/w500/${p}`;
}
async function fetchPoster(url) {
  if (!url) return null;
  try {
    const r = await fetch(url, { timeout: 8000 });
    if (!r.ok) return null;
    const buf = await r.buffer();
    if (!buf || buf.length < 1000) return null;
    return buf;
  } catch { return null; }
}
function brand() {
  const s = settings();
  return {
    name:  s.brand_name  || 'Radd Movies',
    bot:   s.bot_name    || 'Radd',
    owner: s.owner_name  || 'Rehan Radd',
    price: s.price_amount || 500,
    cur:   s.currency    || 'PKR',
    period: s.price_period || 'month',
    pitch: s.premium_pitch_lines || [],
    pay:   s.payment_instructions || '',
  };
}
function brandFooter() {
  const b = brand();
  return `\n\n━━━━━━━━━━━━━━━━━\n🎬 *${b.name}*\n👤 by ${b.owner}\n💬 Powered by ${b.bot}`;
}
function premiumPitch(why) {
  const b = brand();
  const pitch = (b.pitch.length ? b.pitch.join('\n') : '') || '';
  return [
    `🔒 *${why || 'Premium feature — verification required'}*`,
    ``,
    `Join *${b.name} Premium* to unlock:`,
    pitch,
    ``,
    `💳 Only *${b.cur} ${b.price} / ${b.period}*`,
    ``,
    b.pay ? `📲 ${b.pay}` : '',
    ``,
    `Then ask the admin to verify you. ✅`,
  ].filter(Boolean).join('\n');
}
const _fmt = require('./lib/format');
async function fmtUploadCaption(r, role = 'verified') {
  return _fmt.fmtUploadCaption(r, role);
}
function fmtListItem(r) {
  const title = r.tmdb_title ? `${r.tmdb_title}${r.tmdb_year ? ` (${r.tmdb_year})` : ''}` : r.name;
  return `• ${title}  _(${fmtSize(r.size_bytes)})_`;
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
  const lines = [
    `🎬 *WELCOME TO ${b.name.toUpperCase()}*`,
    `_Your easy movie downloader_`,
    ``,
    `*How to use:*`,
    `Just send me the name of any movie or series!`,
    `Example: *Iron Man* or *Avatar*`,
    ``,
    `*Simple Commands:*`,
    `• *help*   — Show this message`,
    `• *list*   — See new movies added`,
    `• *queue*  — See what is downloading`,
    `• *price*  — How to get Premium`,
    ``,
    `👥 *Groups:* Just tag me @${b.bot} + movie name.`,
  ];
  if (role === 'admin') {
    lines.push(
      ``,
      `⭐ *ADMIN CONTROLS* (Only you can see this)`,
      `• */admin list* — See all members`,
      `• */admin verify 03xx* — Make someone Premium`,
      `• */admin block 03xx*  — Block someone`,
      `• */admin stats* — See total movies`,
      `• */admin broadcast Hello* — Message all members`,
      `• */otp 1234* — Submit login code`,
      `• */relogin* — Fix Jazz Drive login`,
      ``,
      `_Tip: You can also reply to someone's message and type "/admin verify" to make them Premium._`,
    );
  }
  return lines.join('\n');
}
function resolveTargetNumber(arg, ctx) {
  let a = '';
  if (!arg) {
    const ci = ctx?.message?.extendedTextMessage?.contextInfo;
    if (ci?.participant) a = jidNumber(ci.participant);
  } else {
    a = String(arg).replace(/[^\d]/g, '');
  }
  if (!a) return null;
  if (a.startsWith('03') && a.length === 11) a = '92' + a.slice(1);
  return a;
}
async function handleAdmin(sock, jid, text, ctx, botJid, botLid) {
  const parts = text.trim().split(/\s+/);
  parts.shift(); 
  const sub = (parts.shift() || '').toLowerCase();
  const arg = parts.join(' ');
  const u = loadUsers();
  const reply = (t) => {
    debug(`[REPLY] To ${jidNumber(jid)}: ${t.slice(0, 50)}`);
    return sock.sendMessage(jid, { text: t }, { quoted: ctx });
  };
  switch (sub) {
    case 'list': {
      const fmt = a => a.length ? a.map(x => `  • ${jidNumber(x)}`).join('\n') : '  _(none)_';
      return reply(`👑 *Admins*\n${fmt(u.admins)}\n\n✅ *Verified*\n${fmt(u.verified)}\n\n🚫 *Blocked*\n${fmt(u.blocked)}`);
    }
    case 'verify': {
      const n = resolveTargetNumber(arg, ctx);
      if (!n) return reply('❌ Usage: */admin verify 923xxxxxxxxx* (or reply to a message)');
      const j = numberToJid(n);
      const b = brand();
      if (!u.verified.some(x => jidNumber(x) === n)) u.verified.push(j);
      u.blocked = u.blocked.filter(x => jidNumber(x) !== n);
      saveUsers(u);
      const welcome = [
        `🎊 *Congratulations!* 🎊`,
        ``,
        `You have been verified as a *Premium Member* of *${b.name}*.`,
        ``,
        `🚀 *What you can do now:*`,
        `• Send any movie name to get direct links.`,
        `• Request movies not in cloud (we'll download them).`,
        `• No more premium pitch messages.`,
        ``,
        `Enjoy the show! 🍿`,
        brandFooter()
      ].join('\n');
      try { 
        await sock.sendMessage(j, { text: welcome }); 
        debug(`[ADMIN] Sent welcome to ${n}`);
      } catch (e) {
        debug(`[ERROR] Could not send welcome to ${n}: ${e.message}`);
      }
      return reply(`✅ *Success!* ${n} is now verified and has received the welcome message.`);
    }
    case 'unverify': {
      const n = resolveTargetNumber(arg, ctx);
      if (!n) return reply('Usage: */admin unverify 923xxxxxxxxx*');
      u.verified = u.verified.filter(x => jidNumber(x) !== n);
      saveUsers(u);
      return reply(`Removed verification from ${n}`);
    }
    case 'block': {
      const n = resolveTargetNumber(arg, ctx);
      if (!n) return reply('Usage: */admin block 923xxxxxxxxx*');
      const j = numberToJid(n);
      if (!u.blocked.some(x => jidNumber(x) === n)) u.blocked.push(j);
      u.verified = u.verified.filter(x => jidNumber(x) !== n);
      saveUsers(u);
      return reply(`🚫 Blocked ${n}`);
    }
    case 'unblock': {
      const n = resolveTargetNumber(arg, ctx);
      if (!n) return reply('Usage: */admin unblock 923xxxxxxxxx*');
      u.blocked = u.blocked.filter(x => jidNumber(x) !== n);
      saveUsers(u);
      return reply(`Unblocked ${n}`);
    }
    case 'addadmin': {
      const n = resolveTargetNumber(arg, ctx);
      if (!n) return reply('Usage: */admin addadmin 923xxxxxxxxx*');
      const j = numberToJid(n);
      if (!u.admins.some(x => jidNumber(x) === n)) u.admins.push(j);
      saveUsers(u);
      return reply(`👑 ${n} is now an admin.`);
    }
    case 'price': {
      const v = parseInt(arg, 10);
      if (!v || v < 1) return reply('Usage: */admin price 500*');
      u.settings = u.settings || {};
      u.settings.price_amount = v;
      saveUsers(u);
      return reply(`💰 Premium price set to ${u.settings.currency || 'PKR'} ${v} / ${u.settings.price_period || 'month'}`);
    }
    case 'stats': {
      const s = libraryStats();
      const q = await streamQueueGet();
      const active = q.filter(j => ['queued','running','downloading','searching'].includes(String(j.status).toLowerCase()));
      const sess = await flixSession();
      const lines = [
        `📊 *${brand().name} Stats*`,
        ``,
        `📚 Library: *${s.total}* titles  (${fmtSize(s.total_size)})`,
        ...Object.entries(s.by_kind).map(([k,c]) => `   • ${k}: ${c}`),
        ``,
        `⏳ Active downloads: *${active.length}*`,
        `📡 Jazz Drive: ${sess.logged_in ? '🟢 Active' : '🔴 Offline'}${sess.msisdn ? ` (${sess.msisdn})` : ''}`,
        ``,
        `👑 Admins: ${u.admins.length}   ✅ Verified: ${u.verified.length}   🚫 Blocked: ${u.blocked.length}`,
      ];
      return reply(lines.join('\n'));
    }
    case 'broadcast': {
      if (!arg) return reply('Usage: */admin broadcast Hello everyone!*');
      let sent = 0;
      for (const v of u.verified) {
        try { await sock.sendMessage(v, { text: `📢 *${brand().name}*\n\n${arg}${brandFooter()}` }); sent++; }
        catch {}
      }
      return reply(`📢 Broadcast sent to ${sent}/${u.verified.length} verified users.`);
    }
    case 'brand': {
      if (!arg) return reply('Usage: */admin brand Radd Movies*');
      u.settings = u.settings || {};
      u.settings.brand_name = arg;
      saveUsers(u);
      return reply(`🎨 Brand name → *${arg}*`);
    }
    case 'botname': {
      if (!arg) return reply('Usage: */admin botname Radd Bot*');
      u.settings = u.settings || {};
      u.settings.bot_name = arg;
      saveUsers(u);
      return reply(`🤖 Bot name → *${arg}*`);
    }
    case 'owner': {
      if (!arg) return reply('Usage: */admin owner Rehan Radd*');
      u.settings = u.settings || {};
      u.settings.owner_name = arg;
      saveUsers(u);
      return reply(`👤 Owner name → *${arg}*`);
    }
    case 'currency': {
      if (!arg) return reply('Usage: */admin currency PKR*');
      u.settings = u.settings || {};
      u.settings.currency = arg.toUpperCase();
      saveUsers(u);
      return reply(`💱 Currency → *${u.settings.currency}*`);
    }
    case 'period': {
      if (!arg) return reply('Usage: */admin period month*');
      u.settings = u.settings || {};
      u.settings.price_period = arg.toLowerCase();
      saveUsers(u);
      return reply(`📅 Billing period → *${u.settings.price_period}*`);
    }
    case 'pay': {
      if (!arg) return reply('Usage: */admin pay JazzCash 03xxxxxxxxx (Rehan Radd)*');
      u.settings = u.settings || {};
      u.settings.payment_instructions = arg;
      saveUsers(u);
      return reply(`💳 Payment instructions updated:\n${arg}`);
    }
    case 'pitch': {
      const subSub = (parts.shift() || '').toLowerCase();
      const rest   = parts.join(' ');
      u.settings = u.settings || {};
      u.settings.premium_pitch_lines = u.settings.premium_pitch_lines || [];
      if (subSub === 'add') {
        if (!rest) return reply('Usage: */admin pitch add 🎬 Latest movies in HD*');
        u.settings.premium_pitch_lines.push(rest);
        saveUsers(u);
        return reply(`✅ Added pitch line.  (${u.settings.premium_pitch_lines.length} total)`);
      }
      if (subSub === 'clear') {
        u.settings.premium_pitch_lines = [];
        saveUsers(u);
        return reply('🧹 All pitch lines cleared.');
      }
      if (subSub === 'list' || !subSub) {
        const list = u.settings.premium_pitch_lines;
        if (!list.length) return reply('_(no pitch lines yet)_  Use */admin pitch add <line>*');
        return reply(`✨ *Premium pitch lines* (${list.length}):\n${list.map((x,i)=>`${i+1}. ${x}`).join('\n')}`);
      }
      return reply('Usage: */admin pitch add|clear|list ...*');
    }
    case 'queue': {
      const q = await streamQueueGet();
      if (!q.length) return reply('📭 Queue is empty.');
      const lines = q.slice(0, 20).map(j =>
        `• ${j.title || j.movie || j.name || '(?)'}  [${j.status || '?'}]`);
      return reply(`📋 *Download queue* (${q.length}):\n${lines.join('\n')}`);
    }
    case 'restart': {
      try {
        fs.writeFileSync(path.join(__dirname, '.relink'), String(Date.now()));
        return reply(
          `🔄 Re-link triggered.\n\n` +
          `Open the admin page in your browser to scan the new QR:\n` +
          `→ http://localhost:5000/admin\n\n` +
          `Or watch the *Workflow logs* for the QR ASCII.`,
        );
      } catch (e) { return reply(`❌ ${e.message}`); }
    }
    case 'link': {
      if (!arg) {
        return reply(
          'Usage: */admin link Iron Man 2008*\n' +
          '_Searches the cloud catalog and replies with the per-file Download URL._',
        );
      }
      const hits = searchLibrary(arg, 5);
      const want = tokens(arg);
      const top = hits[0];
      const goodMatch = top && top._score >= Math.max(1, Math.ceil(want.length * 0.6));
      if (!goodMatch) {
        const sess = await flixSession();
        return reply(
          `🔍 *"${arg}"* is not in the cloud yet.\n` +
          `📡 Jazz Drive: ${sess.logged_in ? '🟢 Active' : '🔴 Offline'}\n\n` +
          `_Tip: send the title without "/admin link" (or use any verified number) to add it to the download queue._`,
        );
      }
      let caption = `🔗 *Admin lookup*\n\n` + await fmtUploadCaption(top, 'admin');
      if (hits.length > 1) {
        const more = hits
          .slice(1, 4)
          .filter(r => r._score > 0)
          .map(r => `• ${r.tmdb_title || r.name}`);
        if (more.length) caption += `\n\n_Other matches:_\n${more.join('\n')}`;
      }
      return sendBranded(sock, jid, top, caption, ctx);
    }
    default:
      return reply(`Unknown admin command. Send *help* to see all options.`);
  }
}
const pluginManager = new PluginManager();
function recordPendingRequest({ jid, user, requesterJid, query, jobId, msgId, msgParticipant }) {
  reqDb.prepare(`INSERT INTO pending (jid, user, requester_jid, query, norm, job_id, msg_id, msg_participant, created_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`).run(
    jid, user || '', requesterJid || '', query, norm(query), jobId || null,
    msgId || null, msgParticipant || null,
    Math.floor(Date.now() / 1000),
  );
}
try { botDb.mirrorUsersJson(); } catch (e) { console.warn('[boot] users.json mirror failed:', e.message); }
async function handleRequest(sock, jid, text, ctx, senderJid, botJid, botLid) {
  if (jid && jid.endsWith('@lid')) {
    const resolved = botDb.resolveAlias(jid);
    if (resolved && !resolved.endsWith('@lid')) jid = resolved;
  }
  const effectiveJid = botDb.resolveAlias(senderJid);
  if (rolesLib.isBlocked(effectiveJid)) return; 
  const cleaned = (text || '').trim();
  if (!cleaned) return;
  const role = rolesLib.getRole(effectiveJid, botJid, botLid);
  try { 
    botDb.touchUser(effectiveJid, ctx?.pushName || '');
    botDb.setRole(effectiveJid, role); 
  } catch {}
  const parsed = intent.parse(cleaned);
  if (parsed.name === 'noop') return;
  const helpers = {
    senderJid: effectiveJid,
    botJid,
    botLid,
    recordPendingRequest,
    legacyHandleAdmin: handleAdmin,
    pluginManager,
    brand: brand(),
    debug,
  };
  try {
    const r = await pluginManager.dispatch({ sock, jid, ctx, intent: parsed, role, helpers });
    if (!r.handled) {
      debug(`[INTENT] no handler for "${parsed.name}" — dispatching as unknown`);
      await pluginManager.dispatch({
        sock, jid, ctx,
        intent: { name: 'unknown', args: parsed.args || cleaned },
        role, helpers,
      });
    }
  } catch (e) {
    debug(`[ERROR] handleRequest error for "${text}": ${e.stack}`);
  }
}

async function notifyLoop(sock, botJid, botLid) {
  try { botDb.mirrorUsersJson(); } catch {}
  try {
    const weekAgo = Math.floor(Date.now() / 1000) - (7 * 24 * 3600);
    reqDb.prepare(`DELETE FROM pending WHERE notified > 0 OR created_at < ?`).run(weekAgo);
  } catch (e) {
    debug(`[JANITOR] Cleanup failed: ${e.message}`);
  }
  const pending = reqDb.prepare(`SELECT * FROM pending WHERE notified = 0 ORDER BY id ASC`).all();
  if (!pending.length) return;
  let fullQueue = [];
  try {
    const r = await _hubFetch(`${STREAM_API}/stream/api/queue`);
    const j = await r.json();
    fullQueue = j.queue || j.jobs || [];
  } catch (e) {
    debug(`[NOTIFY] Could not fetch queue: ${e.message}`);
  }
  const recent = recentLibrary(50);
  for (const p of pending) {
    if (p.job_id) {
      const job = fullQueue.find(j => j.id === p.job_id);
      if (job && (job.status === 'error' || job.status === 'cancelled')) {
        reqDb.prepare(`UPDATE pending SET notified = 3 WHERE id = ?`).run(p.id);
        const errReason = job.error || 'Unknown error during download.';
        try {
          await sock.sendMessage(p.jid, {
            text: `⚠️ *Download Failed*\n\n` +
                  `Title: *${p.query}*\n` +
                  `Status: ${job.status}\n` +
                  `Reason: ${errReason}\n\n` +
                  `Please try again with a different name or check the spelling.` +
                  brandFooter()
          });
        } catch {}
        continue;
      }
    }
    if (Date.now()/1000 - p.created_at > 6 * 3600) {
      reqDb.prepare(`UPDATE pending SET notified = 2 WHERE id = ?`).run(p.id);
      try { await sock.sendMessage(p.jid, { text: `😞 Sorry, *"${p.query}"* couldn't be downloaded after 6 hours. Try a different name or year.${brandFooter()}` }); } catch {}
      continue;
    }
    const wantToks = tokens(p.query);
    const hit = recent.find(r => {
      const hay = norm(`${r.name} ${r.tmdb_title || ''}`);
      const hits = wantToks.filter(t => hay.includes(t)).length;
      return hits >= Math.max(1, Math.ceil(wantToks.length * 0.6));
    });
    if (hit) {
      reqDb.prepare(`UPDATE pending SET notified = 1 WHERE id = ?`).run(p.id);
      try {
        const userRole = rolesLib.getRole(p.requester_jid || p.jid, botJid, botLid);
        const caption = `🎉 *Ready!* Your title *"${p.query}"* is in the cloud.\n\n` + 
                        await fmtUploadCaption(hit, userRole) +
                        `\n\n_Note: Direct links expire after 4 hours. If it stops working, just search for the title again to get a fresh link._`;
        await sendBranded(sock, p.jid, hit, caption, p.msg_id ? {
          key: { remoteJid: p.jid, id: p.msg_id, fromMe: false, participant: p.msg_participant },
          message: { conversation: p.query },
        } : undefined);
      } catch {}
    }
  }
}
let _pluginsRegistered = false;
function registerPluginsOnce() {
  if (_pluginsRegistered) return;
  _pluginsRegistered = true;
  const ctx = { legacyHandleAdmin: handleAdmin, pluginManager };
  pluginManager.registerDir(path.join(__dirname, 'plugins'), ctx);
  console.log(`[plugins] ${pluginManager.list().length} plugin(s) loaded.`);
}
async function start() {
  registerPluginsOnce();
  const { state, saveCreds } = await useMultiFileAuthState(AUTH_DIR);
  const { version } = await fetchLatestBaileysVersion();
  let msisdn = '';
  try {
    const saved = fs.readFileSync(PAIRING_NUM_FILE, 'utf8').trim().replace(/[^\d]/g, '');
    if (saved.length >= 10) {
      msisdn = saved.startsWith('03') && saved.length === 11
        ? '92' + saved.slice(1)
        : saved;
    }
  } catch {}
  if (!msisdn) {
    // Fall back to env var (set by hub from DB settings)
    const envMsisdn = (process.env.JAZZDRIVE_MSISDN || '').replace(/[^\d]/g, '');
    if (envMsisdn.length >= 10) {
      msisdn = envMsisdn.startsWith('03') && envMsisdn.length === 11
        ? '92' + envMsisdn.slice(1)
        : envMsisdn;
    }
  }
  if (msisdn) debug(`[PAIR] Using phone number: ${msisdn} for pairing`);
  const sock = makeWASocket({
    version, auth: state, printQRInTerminal: false,
    logger: pino({ level: 'silent' }),
    browser: ["Ubuntu", "Chrome", "20.0.04"],
    syncFullHistory: false,
    connectTimeoutMs: 60000,
    keepAliveIntervalMs: 30000,
  });
  const realSendMessage = sock.sendMessage.bind(sock);
  sock._realSendMessage = realSendMessage;
  const delay = (ms) => new Promise(res => setTimeout(res, ms));
  sock.sendMessage = async (jid, content, options = {}) => {
    if (jid.endsWith('@newsletter') || content.poll || options.skipDelay) {
        return realSendMessage(jid, content, options);
    }
    const ms = Math.floor(Math.random() * 2500) + 1500;
    await delay(ms);
    try {
      await sock.sendPresenceUpdate('composing', jid);
      const textLen = content.text?.length || content.caption?.length || 0;
      const typingMs = Math.min(3000, Math.max(1000, (textLen / 20) * 1000));
      await delay(typingMs);
      await sock.sendPresenceUpdate('paused', jid);
    } catch (e) {}
    return realSendMessage(jid, content, options);
  };
  _pairingCodeRef = { value: null, requested: false };
  _currentSock   = sock;
  _currentMsisdn = msisdn;
  if (msisdn && !sock.authState?.creds?.registered) {
    setTimeout(async () => {
      if (_pairingCodeRef.requested || sock.authState?.creds?.registered) return;
      _pairingCodeRef.requested = true;
      try {
        debug(`[PAIR] Auto-requesting pairing code for +${msisdn}...`);
        const raw  = await sock.requestPairingCode(msisdn);
        const code = raw.replace(/[^A-Z0-9]/gi, '').toUpperCase()
                        .replace(/^(.{4})(.{4})$/, '$1-$2') || raw;
        _pairingCodeRef.value = code;
        writeBotState({ connected: false, running: true }, 'pairing-code-auto');
        const banner = '═'.repeat(46);
        console.log(`\n${banner}`);
        console.log(`🔗  WhatsApp PAIRING CODE for +${msisdn}`);
        console.log(`🔗  Code:  ${code}`);
        console.log(`🔗  Valid for ~60 seconds. Enter it on your phone:`);
        console.log(`🔗     WhatsApp → Settings → Linked Devices → Link a device → Link with phone number`);
        console.log(`${banner}\n`);
        setTimeout(() => {
          _pairingCodeRef.value = null;
          _pairingCodeRef.requested = false;
          writeBotState({ connected: false, running: true }, 'pairing-code-expired');
        }, 75_000);
      } catch (e) {
        debug(`❌ [PAIR] Auto requestPairingCode failed: ${e.message || e}`);
        _pairingCodeRef.requested = false;
      }
    }, 4000);
  }
  let botJid = null;
  let botLid = null;
  sock.ev.on('creds.update', saveCreds);
  sock.ev.on('connection.update', async (u) => {
    const { connection, lastDisconnect, qr } = u;
    if (qr) {
      console.log('\n📱 SCAN THIS QR (Settings → Linked Devices → Link a device):\n');
      qrTerm.generate(qr, { small: true });
      try { await QRCode.toFile(QR_PNG, qr, { width: 512 });
            console.log(`\n   QR also saved as image: ${QR_PNG}\n`); } catch {}
    }
    if (connection === 'open') {
      botJid = sock.user?.id || null;
      botLid = sock.user?.lid || null;
      if (botJid) _persistedBotNum = jidNumber(botJid);
      if (botLid) _persistedBotLid = jidNumber(botLid);
      _pairingCodeRef.value = null;
      _pairingCodeRef.requested = false;
      try { if (fs.existsSync(QR_PNG)) fs.unlinkSync(QR_PNG); } catch {}
      debug(`✅ ${brand().name} bot connected as ${botJid} (LID: ${botLid})`);
      const now = Date.now();
      if (now - _lastStatusReportAt > 15 * 60_000) {
        _lastStatusReportAt = now;
        try {
          setTimeout(async () => {
            try {
              const status = await checkAllServices();
              const text = buildStatusReport(status, botJid);
              const targets = resolveAdminTargets(botJid);
              if (!targets.length) {
                debug('[STATUS] No admin/owner JID resolved — skipping startup DM.');
                return;
              }
              for (const jid of targets) {
                try {
                  await realSendMessage(jid, { text }, { skipDelay: true });
                  debug(`[STATUS] Startup status sent to ${jid}`);
                } catch (e) {
                  debug(`[STATUS] Failed to DM ${jid}: ${e.message || e}`);
                }
              }
              for (const k of Object.keys(status)) _serviceState[k] = !!status[k].ok;
              startServiceMonitor(() => sock, () => botJid);
            } catch (e) {
              debug(`[STATUS] Startup notification error: ${e.message || e}`);
            }
          }, 3000);
        } catch (e) {
          debug(`[STATUS] Scheduling error: ${e.message || e}`);
        }
      } else {
        debug('[STATUS] Status report rate-limited (sent recently).');
        startServiceMonitor(() => sock, () => botJid);
      }
    }
    if (connection === 'close') {
      const code = lastDisconnect?.error?.output?.statusCode;
      const shouldReconnect = code !== DisconnectReason.loggedOut;
      try {
        _lastDisconnect = {
          code: code || 0,
          reason: _disconnectReasonName(code),
          message: lastDisconnect?.error?.message || lastDisconnect?.error?.output?.payload?.message || 'unknown',
          at: new Date().toISOString(),
        };
      } catch {}
      debug(`⚠ Connection closed (code ${code}). Reconnect: ${shouldReconnect}`);
      if (code === 440) {
        debug('⚠ connectionReplaced (440) detected. Another active session exists. STOPPING to avoid spam loop.');
        try {
          fs.writeFileSync(STATE_FILE, JSON.stringify({
            connected: false,
            bot_number: _persistedBotNum || '',
            bot_lid: _persistedBotLid || '',
            last_disconnect: _lastDisconnect,
            updated_at: Date.now(),
          }, null, 2));
        } catch {}
        // Do NOT auto-restart on 440. Let the user or manager handle it.
        process.exit(0); 
      }
      if (shouldReconnect) {
        setTimeout(start, code === 440 ? 15000 : 3000);
      } else {
        if (code === 401) {
          debug('❌ Session logged out (401). Wiping auth_info and restarting to show new QR...');
          try {
            for (const f of fs.readdirSync(AUTH_DIR)) {
              try { fs.unlinkSync(path.join(AUTH_DIR, f)); } catch {}
            }
          } catch {}
          setTimeout(start, 2000);
        } else {
          debug(`Attempting reconnect after code ${code}...`);
          setTimeout(start, 3000);
        }
      }
    }
  });
  sock.ev.on('messages.upsert', async (ev) => {
    if (ev.type !== 'notify') return;
    for (const msg of ev.messages) {
      try {
        if (!msg.message) continue;
        const msgId = msg.key.id;
        if (msgId && _seenMsgIds.has(msgId)) continue;
        if (msgId) _seenMsgIds.add(msgId);
        // ----- audit S4: per-user rate-limit (12/min default) ----------
        const _rlSender = msg.key.participant || msg.key.remoteJid || '';
        if (_rlSender && !msg.key.fromMe) {
          let _role = 'user';
          try {
            const _admins = (process.env.BOT_ADMIN_JIDS || '').split(',').map(s=>s.trim()).filter(Boolean);
            if (_admins.includes(_rlSender)) _role = 'admin';
          } catch (_) {}
          if (!_rateLimit.allow(_rlSender, _role)) {
            const st = _rateLimit.status(_rlSender);
            if (st.violations <= 3) {
              try {
                await sock.sendMessage(msg.key.remoteJid, {
                  text: `⏳ Slow down — you've sent ${st.used}/${st.limit} messages in the last minute. ` +
                        `Try again in ${Math.ceil(st.resetInMs/1000)}s.`
                });
              } catch (_) {}
            }
            continue;
          }
        }
        const jid = msg.key.remoteJid;
        const isGroup = jid.endsWith('@g.us');
        const myNum = jidNumber(botJid || '') || _persistedBotNum;
        const myLid = jidNumber(botLid || '') || _persistedBotLid;
        const remoteNum = jidNumber(jid || '');
        const fromMe = !!msg.key.fromMe;
        const m = msg.message;
        const text = (m.conversation || m.extendedTextMessage?.text || m.imageMessage?.caption || '').trim();
        if (!text) continue;
        const senderJid = fromMe ? (botJid || jid) : (msg.key.participant || jid);
        if (!senderJid) continue;
        const part = msg.key.participant || '';
        if (jid.endsWith('@lid') && part.endsWith('@s.whatsapp.net')) botDb.saveAlias(jid, part);
        if (part.endsWith('@lid') && jid.endsWith('@s.whatsapp.net')) botDb.saveAlias(part, jid);
        const isSelfChat = (remoteNum === myNum || remoteNum === myLid || jidNumber(senderJid) === myNum || jidNumber(senderJid) === myLid);
        debug(`[MSG] From ${jidNumber(senderJid)} (fromMe: ${fromMe}, selfChat: ${isSelfChat}, group: ${isGroup}) : ${text.slice(0, 50)}`);
        if (fromMe) {
            if (isSelfChat || text.startsWith('/')) {
            } else {
                debug(`[SKIP] Ignoring my own message in non-self-chat: ${text.slice(0,20)}`);
                continue;
            }
        }
        const mentionedJids = m.extendedTextMessage?.contextInfo?.mentionedJid || [];
        const mentionsMe = (!!myNum && (mentionedJids.some(j => j.startsWith(myNum)) || text.includes(`@${myNum}`))) ||
                           (!!myLid && (mentionedJids.some(j => j.startsWith(myLid)) || text.includes(`@${myLid}`)));
        const repliedAuthor = m.extendedTextMessage?.contextInfo?.participant || '';
        const repliedToMe = (!!myNum && repliedAuthor.startsWith(myNum)) ||
                            (!!myLid && repliedAuthor.startsWith(myLid));
        const cleaned = text
          .replace(new RegExp(`@${myNum}`, 'g'), '')
          .replace(new RegExp(`@${myLid}`, 'g'), '')
          .replace(/^\s*@\S+\s*/g, '')
          .trim();
        if (isGroup && !mentionsMe && !repliedToMe) {
            debug(`[SKIP] Not mentioned in group: ${jid}`);
            continue;
        }
        debug(`[PROC] Processing: ${cleaned.slice(0, 30)}`);
        await handleRequest(sock, jid, cleaned, msg, senderJid, botJid, botLid);
      } catch (e) {
        debug(`[ERROR] Handler error: ${e.message}`);
      }
    }
  });
  setInterval(() => notifyLoop(sock, botJid, botLid).catch(() => {}), 20_000);
  setInterval(() => {
    try {
      let libraryTotal = 0;
      try { libraryTotal = library.libraryStats().total || 0; } catch (e) {  }
      fs.writeFileSync(STATE_FILE, JSON.stringify({
        connected: !!botJid,
        bot_number: jidNumber(botJid || ''),
        pairing_code: _pairingCodeRef.value,
        pairing_number: (_pairingCodeRef.value && msisdn) ? msisdn : null,
        library_total: libraryTotal,
        ts: Date.now() / 1000,
      }));
    } catch (e) {
      debug(`[HEARTBEAT ERROR] ${e.message}`);
    }
  }, 4000);
  setInterval(async () => {
    if (!fs.existsSync(RELINK_FILE)) return;
    try { fs.unlinkSync(RELINK_FILE); } catch {}
    console.log('🔄 Re-link requested from admin panel — wiping saved login.');
    try { await sock.logout(); } catch {}
    try { sock.end(); } catch {}
    try {
      for (const f of fs.readdirSync(AUTH_DIR)) {
        try { fs.unlinkSync(path.join(AUTH_DIR, f)); } catch {}
      }
    } catch {}
    botJid = null;
    setTimeout(() => start().catch(e => console.error('relink start error:', e.message)), 1500);
  }, 3000);
  setInterval(async () => {
    if (!botJid) return;
    const pending = await streamOtpStatus();
    if (!pending || !pending.pending) return;
    const stamp = String(pending.started_at || 0);
    let lastDmd = '';
    try { lastDmd = fs.readFileSync(OTP_DMD, 'utf8').trim(); } catch {}
    if (!stamp || stamp === lastDmd) return;
    const secsLeft = pending.seconds_left || 0;
    const text =
      `📲 *Jazz Drive needs an OTP*\n\n` +
      `Number: *${pending.msisdn || 'unknown'}*\n` +
      `Expires in: ~${Math.ceil(secsLeft/60)} min\n\n` +
      `Reply here with: */otp 1234*\n\n` +
      `_Or — if your phone has the SMS Forwarder set up, the bot is reading the SMS automatically right now and you can ignore this._`;
    const u = loadUsers();
    const targets = new Set([botJid, ...(u.admins || [])]);
    for (const j of targets) {
      if (!j) continue;
      try { await sock.sendMessage(j, { text }); }
      catch (e) { console.error('OTP DM failed:', j, e.message); }
    }
    try { fs.writeFileSync(OTP_DMD, stamp); } catch {}
    console.log(`📲 OTP alert DM'd to ${targets.size} admin(s).`);
  }, 30_000);
  setInterval(async () => {
    if (!botJid) return;
    if (!fs.existsSync(SESSION_DEAD)) return;
    let dead;
    try { dead = JSON.parse(fs.readFileSync(SESSION_DEAD, 'utf8')); }
    catch { return; }
    const stamp = String(dead.started_at || 0);
    let lastDmd = '';
    try { lastDmd = fs.readFileSync(DEAD_DMD, 'utf8').trim(); } catch {}
    if (!stamp || stamp === lastDmd) return;
    const stage = dead.stage || 'upload';
    const why   = (dead.error || 'unknown').slice(0, 200);
    const text  =
      `🚨 *Jazz Drive session is DEAD*\n\n` +
      `Heartbeat failed at: *${stage}*\n` +
      `Reason: ${why}\n\n` +
      `Reply */relogin* to clear the saved login, then */otp 1234* with the SMS code Jazz sends you.`;
    const u = loadUsers();
    const targets = new Set([botJid, ...(u.admins || [])]);
    for (const j of targets) {
      if (!j) continue;
      try { await sock.sendMessage(j, { text }); }
      catch (e) { console.error('DEAD DM failed:', j, e.message); }
    }
    try { fs.writeFileSync(DEAD_DMD, stamp); } catch {}
    console.log(`🚨 Session-dead alert DM'd to ${targets.size} admin(s).`);
  }, 30_000);
  setInterval(async () => {
    if (!botJid) return;
    let entries;
    try { entries = fs.readdirSync(WEBCMD_DIR); } catch { return; }
    for (const fn of entries) {
      if (!fn.endsWith('.in.json')) continue;
      const inPath = path.join(WEBCMD_DIR, fn);
      let req; try { req = JSON.parse(fs.readFileSync(inPath, 'utf8')); }
      catch { try { fs.unlinkSync(inPath); } catch {} continue; }
      try { fs.unlinkSync(inPath); } catch {}
      const rid = req.id || fn.replace('.in.json', '');
      const cmd = String(req.cmd || '').trim();
      const ts_in = req.ts || Math.floor(Date.now() / 1000);
      const virtualJid = `webcmd-${rid}@web.local`;
      const vSock = makeVirtualSock(sock, virtualJid);
      try {
        if (req.cmd === 'send') {
          // Direct send-message command from Python hub's send_message()
          const targetJid = String(req.jid || '').trim();
          const textToSend = String(req.text || '').trim();
          if (targetJid && textToSend) {
            const realSend = sock._realSendMessage || sock.sendMessage.bind(sock);
            await realSend(targetJid, { text: textToSend }, { skipDelay: true });
            vSock.captured.push(`✓ sent to ${targetJid}`);
          } else {
            vSock.captured.push(`❌ send: missing jid or text`);
          }
        } else if (/^\/admin\b/i.test(cmd)) {
          await handleAdmin(vSock, virtualJid, cmd, undefined, botJid, botLid);
        } else {
          await handleRequest(vSock, virtualJid, cmd, undefined, virtualJid, botJid, botLid);
        }
      } catch (e) {
        debug(`[WEBCMD ERROR] ${e.message}`);
        vSock.captured.push(`❌ Bot error: ${e.message}`);
      } finally {
        const outPath = path.join(WEBCMD_DIR, `${rid}.out.json`);
        try {
          fs.writeFileSync(outPath, JSON.stringify({
            id: rid, ts_in,
            ts_out: Math.floor(Date.now() / 1000),
            lines: vSock.captured.length ? vSock.captured : [`(no response from bot command: ${cmd})`],
          }));
        } catch (e) { console.error('webcmd write failed:', e.message); }
      }
    }
    try {
      const now = Date.now();
      for (const fn of entries) {
        if (!fn.endsWith('.out.json')) continue;
        const p = path.join(WEBCMD_DIR, fn);
        try {
          const st = fs.statSync(p);
          if (now - st.mtimeMs > 60_000) fs.unlinkSync(p);
        } catch {}
      }
    } catch {}
  }, 1_000);
}
function makeVirtualSock(realSock, virtualReplyJid) {
  const buf = [];
  return {
    captured: buf,
    user: realSock.user,
    sendPresenceUpdate: async () => {},
    readMessages: async () => {},
    sendMessage: async (jid, payload, opts) => {
      if (jid === virtualReplyJid) {
        if (typeof payload?.text === 'string') buf.push(payload.text);
        if (typeof payload?.caption === 'string') {
          buf.push((payload.image ? '🖼  ' : '') + payload.caption);
        }
        if (payload?.poll) {
          buf.push(`📊 *POLL:* ${payload.poll.name}\nOptions:\n${payload.poll.values.map(v => '  - ' + v).join('\n')}`);
        }
        return { key: { id: 'web-' + Date.now() } };
      }
      try { return await realSock.sendMessage(jid, payload, opts); }
      catch (e) { buf.push(`[fanout error to ${jidNumber(jid)}: ${e.message}]`); }
    },
  };
}
setInterval(async () => {
  if (!fs.existsSync(PAIRING_REQ_FILE)) return;
  try { fs.unlinkSync(PAIRING_REQ_FILE); } catch {}
  const sock   = _currentSock;
  const msisdn = _currentMsisdn;
  if (!sock || !msisdn) {
    console.error('[PAIR] Pairing requested but no socket/number available yet. Try again in a moment.');
    return;
  }
  if (_pairingCodeRef.requested) {
    console.log('[PAIR] Pairing code already pending — wait for it to appear or expire.');
    return;
  }
  _pairingCodeRef.requested = true;
  try {
    console.log(`[PAIR] On-demand pairing code requested for ${msisdn}...`);
    const raw  = await sock.requestPairingCode(msisdn);
    const code = raw.replace(/[^A-Z0-9]/gi, '').toUpperCase()
                    .replace(/^(.{4})(.{4})$/, '$1-$2') || raw;
    _pairingCodeRef.value = code;
    writeBotState({ connected: false, running: true }, 'pairing-code-ondemand');
    const banner = '═'.repeat(46);
    console.log(`\n${banner}`);
    console.log(`🔗  WhatsApp PAIRING CODE for +${msisdn}`);
    console.log(`🔗  Code:  ${code}`);
    console.log(`🔗  Valid for ~60 seconds. Enter it on your phone:`);
    console.log(`🔗     WhatsApp → Settings → Linked Devices → Link a device → Link with phone number`);
    console.log(`${banner}\n`);
    setTimeout(() => { _pairingCodeRef.value = null; _pairingCodeRef.requested = false; writeBotState({ connected: false, running: true }, 'pairing-code-expired'); }, 75_000);
  } catch (e) {
    const msg = e.message || String(e);
    console.error(`❌ [PAIR] requestPairingCode failed: ${msg}`);
    _pairingCodeRef.requested = false;
  }
}, 2000);
process.on('uncaughtException', (err) => {
  try { debug(`[UNCAUGHT] ${err?.message || err}`); } catch {}
  try { console.error('[UNCAUGHT]', err); } catch {}
});
process.on('unhandledRejection', (reason) => {
  try { debug(`[UNHANDLED] ${reason?.message || reason}`); } catch {}
  try { console.error('[UNHANDLED]', reason); } catch {}
});
start().catch(e => { console.error('Fatal:', e); process.exit(1); });