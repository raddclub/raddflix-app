'use strict';
const fs   = require('fs');
const path = require('path');
const db   = require('./db');
const USERS_FILE = path.join(__dirname, '..', 'users.json');
function jidNumber(j) { return (j || '').split('@')[0].split(':')[0]; }
function loadUsers() {
  try { return JSON.parse(fs.readFileSync(USERS_FILE, 'utf8')); }
  catch { return { admins: [], verified: [], blocked: [], settings: {} }; }
}
function isInList(jid, list) {
  const n = jidNumber(jid);
  return (list || []).some(x => jidNumber(x) === n);
}
function isBlocked(jid)  { return isInList(jid, loadUsers().blocked);  }
function isVerified(jid, botJid, botLid) {
  const resolvedJid = db.resolveAlias(jid); 
  const n = jidNumber(resolvedJid);
  if (botJid && jidNumber(botJid) === n) return true;
  if (botLid && jidNumber(botLid) === n) return true;
  const u = loadUsers();
  return isInList(resolvedJid, u.verified) || isInList(resolvedJid, u.admins);
}
function isAdmin(jid, botJid, botLid) {
  const resolvedJid = db.resolveAlias(jid); 
  const n = jidNumber(resolvedJid);
  if (botJid && jidNumber(botJid) === n) return true;
  if (botLid && jidNumber(botLid) === n) return true;
  return isInList(resolvedJid, loadUsers().admins);
}
function getRole(jid, botJid, botLid) {
  const resolvedJid = db.resolveAlias(jid); 
  if (isBlocked(resolvedJid))  return 'blocked';
  if (isAdmin(resolvedJid, botJid, botLid))    return 'admin';
  if (isVerified(resolvedJid, botJid, botLid)) return 'verified';
  return 'free';
}
const RANK = { blocked: -1, free: 0, verified: 1, admin: 2 };
function meetsRole(have, need) {
  return (RANK[have] ?? -1) >= (RANK[need] ?? -1);
}
module.exports = {
  jidNumber,
  isBlocked,
  isVerified,
  isAdmin,
  getRole,
  meetsRole,
  RANK,
};