'use strict';
const db = require('./db');
const DEFAULTS = { admin: -1, verified: 10240, free: 0, blocked: 0 };
function ensureBaseline(jid, role) {
  const u = db.getUser(jid);
  if (!u) return;
  const baseline = DEFAULTS[role];
  if (baseline === undefined) return;
  if (baseline === -1) return;
  if (u.daily_quota_mb == null || u.daily_quota_mb === 0) {
    db.setQuota(jid, baseline);
  }
}
function statusFor(jid, role) {
  ensureBaseline(jid, role);
  const s = db.quotaStatus(jid);
  if (role === 'admin') {
    return { ...s, daily_quota_mb: -1, remaining_mb: -1, unlimited: true };
  }
  return { ...s, unlimited: false };
}
function formatQuota(s) {
  if (s.unlimited) return 'Unlimited (admin)';
  const used  = (s.used_today_mb / 1024).toFixed(2);
  const total = (s.daily_quota_mb / 1024).toFixed(2);
  const left  = (Math.max(0, s.daily_quota_mb - s.used_today_mb) / 1024).toFixed(2);
  return `${used} / ${total} GB used today  (${left} GB left)`;
}
function check(jid, role, sizeBytes) {
  if (role === 'admin') return { ok: true, status: statusFor(jid, role) };
  if (role === 'free' || role === 'blocked') {
    return { ok: false, reason: 'role', status: statusFor(jid, role) };
  }
  ensureBaseline(jid, role);
  const r = db.canDownload(jid, sizeBytes);
  return r;
}
function consume(jid, role, sizeBytes, fingerprint, title) {
  if (role === 'admin') return { ok: true };
  if (role === 'free' || role === 'blocked') return { ok: false, reason: 'role' };
  ensureBaseline(jid, role);
  const r = db.consumeQuota(jid, sizeBytes, fingerprint, title);
  if (!r.ok) return { ok: false, reason: 'quota', status: r };
  return { ok: true };
}
function record(jid, sizeBytes, fingerprint, title) {
  db.recordDownload(jid, sizeBytes, fingerprint, title);
}
module.exports = { check, consume, record, statusFor, formatQuota, DEFAULTS };