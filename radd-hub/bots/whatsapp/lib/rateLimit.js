'use strict';
/**
 * Per-user (per phone number) rate limiter for the WhatsApp bot.
 * Audit S4: prevents accidental message-flood / abuse.
 *
 * Default: 12 messages per rolling minute (overridable via env).
 *
 *   const rl = require('./rateLimit');
 *   if (!rl.allow(senderJid)) { sock.sendMessage(...); return; }
 *
 * State is held in-memory (a Map<jid, number[]> of recent timestamps);
 * acceptable trade-off for a single-process Node bot.  Memory is bounded
 * to last MAX_TRACKED senders; oldest is evicted LRU-style.
 */
const WINDOW_MS  = 60 * 1000;                                          // 1 minute
const MAX_PER_WIN = parseInt(process.env.BOT_RATE_LIMIT_PER_MIN || '12', 10);
const MAX_TRACKED = 5000;
const ADMIN_BYPASS = (process.env.BOT_RATE_LIMIT_ADMIN_BYPASS || '1') !== '0';

const _hits = new Map();             // jid -> number[] (epoch ms)
const _violations = new Map();       // jid -> number  (count)

function _gc(jid) {
  const now = Date.now();
  const arr = _hits.get(jid) || [];
  const cutoff = now - WINDOW_MS;
  let i = 0;
  while (i < arr.length && arr[i] < cutoff) i++;
  if (i > 0) arr.splice(0, i);
  if (arr.length === 0) {
    _hits.delete(jid);
  } else {
    _hits.set(jid, arr);
  }
  return arr;
}

function allow(jid, role) {
  if (!jid) return true;
  if (ADMIN_BYPASS && role === 'admin') return true;
  if (_hits.size >= MAX_TRACKED) {
    // crude LRU: drop one
    const firstKey = _hits.keys().next().value;
    if (firstKey) _hits.delete(firstKey);
  }
  const arr = _gc(jid);
  if (arr.length >= MAX_PER_WIN) {
    _violations.set(jid, (_violations.get(jid) || 0) + 1);
    return false;
  }
  arr.push(Date.now());
  _hits.set(jid, arr);
  return true;
}

function status(jid) {
  const arr = _gc(jid);
  return {
    used: arr.length,
    limit: MAX_PER_WIN,
    remaining: Math.max(0, MAX_PER_WIN - arr.length),
    resetInMs: arr.length ? Math.max(0, WINDOW_MS - (Date.now() - arr[0])) : 0,
    violations: _violations.get(jid) || 0,
  };
}

function reset(jid) {
  _hits.delete(jid);
  _violations.delete(jid);
}

module.exports = { allow, status, reset, WINDOW_MS, MAX_PER_WIN };
