/**
 * RaddFlix WhatsApp OTP Bot — index.js
 * 
 * Uses @whiskeysockets/baileys to connect to WhatsApp.
 * Exposes an HTTP API on port 3000 for OTP delivery.
 * 
 * HTTP API:
 *   POST /api/send-message  { jid, text }  → { ok, sent }
 *   GET  /api/status                        → { connected, running, phone, pairing_code }
 *   GET  /api/qr                            → { qr_available, pairing_code, connected }
 *   POST /api/start                         → start bot
 *   POST /api/stop                          → stop bot
 *
 * File-based IPC (for Python whatsapp.py send_message()):
 *   Polls /tmp/radd_bot_cmd/*.in.json every 500ms
 *   Writes /tmp/radd_bot_cmd/*.out.json response
 *
 * Pairing code (preferred over QR for headless server):
 *   Write phone number to ./pairing-number.txt before starting
 *   Bot reads it on connect and requests pairing code
 *
 * State:
 *   ./bot-state.json  — { connected, bot_number, pairing_code }
 *   ./auth_info/      — Baileys session credentials
 *   ./bot-debug.log   — rolling debug log
 */

'use strict';

const { default: makeWASocket, DisconnectReason, useMultiFileAuthState, fetchLatestBaileysVersion, makeCacheableSignalKeyStore } = require('@whiskeysockets/baileys');
const express = require('express');
const fs      = require('fs');
const path    = require('path');
const pino    = require('pino');
const os      = require('os');

// ── Config ────────────────────────────────────────────────────────────────────
const BOT_DIR       = __dirname;
const AUTH_DIR      = path.join(BOT_DIR, 'auth_info');
const STATE_FILE    = path.join(BOT_DIR, 'bot-state.json');
const DEBUG_LOG     = path.join(BOT_DIR, 'bot-debug.log');
const PAIRING_FILE  = path.join(BOT_DIR, 'pairing-number.txt');
const CMD_DIR       = path.join(os.tmpdir(), 'radd_bot_cmd');
const HTTP_PORT     = parseInt(process.env.WA_BOT_PORT || '3000', 10);

// ── Logging ───────────────────────────────────────────────────────────────────
const logStream = fs.createWriteStream(DEBUG_LOG, { flags: 'a' });
function log(level, ...args) {
  const msg = `[${new Date().toISOString()}] [${level}] ${args.join(' ')}\n`;
  process.stdout.write(msg);
  logStream.write(msg);
}
const logger = pino({ level: 'silent' }); // suppress Baileys noise in production

// ── State ─────────────────────────────────────────────────────────────────────
let state = { connected: false, bot_number: '', pairing_code: null };
let sock  = null;
let reconnectTimer = null;

function saveState(update = {}) {
  Object.assign(state, update);
  try { fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2)); } catch (_) {}
}

function loadState() {
  try {
    if (fs.existsSync(STATE_FILE)) {
      Object.assign(state, JSON.parse(fs.readFileSync(STATE_FILE, 'utf8')));
    }
  } catch (_) {}
}

loadState();

// ── Message queue ─────────────────────────────────────────────────────────────
const _pendingMessages = []; // { jid, text, resolve, reject }

async function sendMessage(jid, text) {
  if (!sock || !state.connected) {
    throw new Error('WhatsApp not connected');
  }
  await sock.sendMessage(jid, { text });
  log('INFO', `Message sent to ${jid.slice(0, 8)}...`);
}

// ── Baileys connection ─────────────────────────────────────────────────────────
async function connectToWhatsApp() {
  if (reconnectTimer) { clearTimeout(reconnectTimer); reconnectTimer = null; }

  log('INFO', 'Connecting to WhatsApp...');

  const { state: authState, saveCreds } = await useMultiFileAuthState(AUTH_DIR);
  const { version } = await fetchLatestBaileysVersion();
  log('INFO', `Baileys version: ${version.join('.')}`);

  sock = makeWASocket({
    version,
    auth: {
      creds: authState.creds,
      keys:  makeCacheableSignalKeyStore(authState.keys, logger),
    },
    logger,
    printQRInTerminal: false,
    generateHighQualityLinkPreview: false,
    browser: ['RaddFlix Bot', 'Chrome', '120.0.0'],
  });

  // ── Pairing code ─────────────────────────────────────────────────────────
  if (!authState.creds.registered) {
    if (fs.existsSync(PAIRING_FILE)) {
      const phone = fs.readFileSync(PAIRING_FILE, 'utf8').trim()
        .replace(/\D/g, '');
      if (phone.length >= 10) {
        log('INFO', `Requesting pairing code for phone: ${phone.slice(0,4)}...`);
        // Wait for socket to be ready before requesting pairing code
        await new Promise(r => setTimeout(r, 2000));
        try {
          const code = await sock.requestPairingCode(phone);
          log('INFO', `PAIRING CODE: ${code}`);
          saveState({ pairing_code: code });
        } catch (e) {
          log('WARN', `Pairing code error: ${e.message}`);
        }
      }
    }
  }

  // ── Events ────────────────────────────────────────────────────────────────
  sock.ev.on('creds.update', saveCreds);

  sock.ev.on('connection.update', async (update) => {
    const { connection, lastDisconnect, qr } = update;

    if (qr) {
      log('INFO', 'QR code generated (scan in WhatsApp → Linked Devices)');
      try {
        const QRCode = require('qrcode');
        const qrPath = path.join(BOT_DIR, 'whatsapp-qr.png');
        await QRCode.toFile(qrPath, qr, { type: 'png', width: 300 });
        log('INFO', `QR saved to ${qrPath}`);
      } catch (e) {
        log('WARN', `QR save failed: ${e.message}`);
      }
    }

    if (connection === 'open') {
      const jid    = sock.user?.id || '';
      const number = jid.split(':')[0].split('@')[0];
      log('INFO', `Connected! Bot number: ${number}`);
      saveState({ connected: true, bot_number: number, pairing_code: null });
      // Flush any queued messages
      while (_pendingMessages.length > 0) {
        const item = _pendingMessages.shift();
        try {
          await sock.sendMessage(item.jid, { text: item.text });
          item.resolve(true);
        } catch (e) {
          item.reject(e);
        }
      }
    }

    if (connection === 'close') {
      const code    = lastDisconnect?.error?.output?.statusCode;
      const loggedOut = code === DisconnectReason.loggedOut;
      log('WARN', `Connection closed. Code: ${code}. LoggedOut: ${loggedOut}`);
      saveState({ connected: false });

      if (loggedOut) {
        log('INFO', 'Logged out — clearing auth. Re-link via admin panel.');
        try { fs.rmSync(AUTH_DIR, { recursive: true, force: true }); } catch (_) {}
      } else {
        // Reconnect after 5s
        log('INFO', 'Reconnecting in 5s...');
        reconnectTimer = setTimeout(connectToWhatsApp, 5000);
      }
    }
  });

  sock.ev.on('messages.upsert', ({ messages }) => {
    for (const msg of messages) {
      if (!msg.key.fromMe && msg.message) {
        const from = msg.key.remoteJid;
        const text = msg.message?.conversation || msg.message?.extendedTextMessage?.text || '';
        if (text) log('INFO', `Received from ${from?.slice(0,8)}: ${text.slice(0,50)}`);
      }
    }
  });
}

// ── HTTP Server ────────────────────────────────────────────────────────────────
const app = express();
app.use(express.json());

app.post('/api/send-message', async (req, res) => {
  const { jid, text } = req.body || {};
  if (!jid || !text) return res.status(400).json({ ok: false, error: 'jid and text required' });

  if (!state.connected || !sock) {
    return res.status(503).json({ ok: false, error: 'Bot not connected to WhatsApp' });
  }

  try {
    await sock.sendMessage(jid, { text: String(text) });
    log('INFO', `HTTP: sent message to ${jid.slice(0, 8)}...`);
    return res.json({ ok: true, sent: true });
  } catch (e) {
    log('ERROR', `HTTP send error: ${e.message}`);
    return res.status(500).json({ ok: false, error: e.message });
  }
});

app.get('/api/status', (req, res) => {
  res.json({
    ok:           true,
    connected:    state.connected,
    running:      true,
    phone:        state.bot_number || '',
    pairing_code: state.pairing_code || null,
  });
});

app.get('/api/qr', (req, res) => {
  const qrPath = path.join(BOT_DIR, 'whatsapp-qr.png');
  res.json({
    ok:           true,
    connected:    state.connected,
    running:      true,
    qr_available: fs.existsSync(qrPath),
    pairing_code: state.pairing_code || null,
    phone:        state.bot_number || '',
  });
});

app.post('/api/stop', (req, res) => {
  log('INFO', 'Stop requested via HTTP');
  res.json({ ok: true, message: 'Bot shutting down' });
  setTimeout(() => process.exit(0), 500);
});

app.get('/health', (req, res) => {
  res.json({ ok: true, connected: state.connected, phone: state.bot_number });
});

// ── File-based IPC (for Python whatsapp.py compatibility) ─────────────────────
function ensureCmdDir() {
  try { fs.mkdirSync(CMD_DIR, { recursive: true }); } catch (_) {}
}

async function pollCmdDir() {
  ensureCmdDir();
  try {
    const files = fs.readdirSync(CMD_DIR).filter(f => f.endsWith('.in.json'));
    for (const fname of files) {
      const inPath  = path.join(CMD_DIR, fname);
      const outPath = path.join(CMD_DIR, fname.replace('.in.json', '.out.json'));
      let cmd;
      try {
        cmd = JSON.parse(fs.readFileSync(inPath, 'utf8'));
        fs.unlinkSync(inPath);
      } catch (_) { continue; }

      if (cmd.cmd === 'send' && cmd.jid && cmd.text && state.connected && sock) {
        try {
          await sock.sendMessage(cmd.jid, { text: String(cmd.text) });
          fs.writeFileSync(outPath, JSON.stringify({ id: cmd.id, sent: true }));
          log('INFO', `IPC: sent to ${cmd.jid.slice(0,8)}`);
        } catch (e) {
          fs.writeFileSync(outPath, JSON.stringify({ id: cmd.id, sent: false, error: e.message }));
        }
      } else {
        fs.writeFileSync(outPath, JSON.stringify({
          id: cmd.id, sent: false,
          error: state.connected ? 'unknown cmd' : 'not connected'
        }));
      }
    }
  } catch (_) {}
  setTimeout(pollCmdDir, 500);
}

// ── Start ─────────────────────────────────────────────────────────────────────
app.listen(HTTP_PORT, '127.0.0.1', () => {
  log('INFO', `HTTP server listening on port ${HTTP_PORT}`);
});

ensureCmdDir();
setTimeout(pollCmdDir, 1000);
connectToWhatsApp().catch(e => {
  log('ERROR', `Initial connect failed: ${e.message}`);
  // Will retry via connection.update event
});

process.on('SIGTERM', () => { log('INFO', 'SIGTERM received, shutting down'); process.exit(0); });
process.on('SIGINT',  () => { log('INFO', 'SIGINT received, shutting down');  process.exit(0); });
