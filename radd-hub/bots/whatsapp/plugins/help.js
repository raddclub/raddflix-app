'use strict';
const fmt     = require('../lib/format');
const library = require('../lib/library');
async function help({ sock, jid, ctx, role }) {
  return sock.sendMessage(jid, { text: fmt.helpText(role) }, { quoted: ctx });
}
async function menu(args)  { return help(args); }
async function greeting({ sock, jid, ctx, role, brand }) {
  const intro = role === 'admin'
    ? `Hi boss 👑 — type */menu* to see admin commands.`
    : role === 'verified'
      ? `Welcome back ✨ — type */find <title>* or */menu*.`
      : `Salam! Welcome to *${brand.name}*.\n\nType */menu* to see what I can do, or */price* to unlock downloads.`;
  return sock.sendMessage(jid, { text: intro + fmt.brandFooter() }, { quoted: ctx });
}
async function unknown({ sock, jid, ctx, intent }) {
  const txt = intent.args || '';
  return sock.sendMessage(jid, {
    text: `🤔 I'm not sure what you mean by "${txt.slice(0, 80)}".\n\n` +
          `Try */find ${txt.split(' ').slice(0, 3).join(' ') || 'iron man'}* to search the cloud, ` +
          `or */menu* to see all commands.`,
  }, { quoted: ctx });
}
async function count({ sock, jid, ctx, brand }) {
  const s = library.libraryStats();
  const kinds = Object.entries(s.by_kind).map(([k, c]) => `   • ${k}: ${c}`).join('\n');
  return sock.sendMessage(jid, {
    text: `📚 *${s.total}* titles in the ${brand.name} cloud (${fmt.fmtSize(s.total_size)})\n${kinds}` + fmt.brandFooter(),
  }, { quoted: ctx });
}
async function list({ sock, jid, ctx, role, brand }) {
  const rows = library.recentLibrary(10);
  if (!rows.length) {
    return sock.sendMessage(jid, { text: 'Library is empty.' + fmt.brandFooter() }, { quoted: ctx });
  }
  const tail = (role === 'verified' || role === 'admin')
    ? '\n\n_Reply */find <title>* to get the link._'
    : '\n\n' + fmt.premiumPitch('Send a title to download — Premium only');
  const body = `🆕 *Latest in ${brand.name} cloud:*\n\n` +
               rows.map(fmt.fmtListItem).join('\n') + tail + fmt.brandFooter();
  return sock.sendMessage(jid, { text: body }, { quoted: ctx });
}
module.exports = {
  name: 'help',
  version: '2.0.0',
  commands: [
    { intent: 'help',     role: 'free', handler: help },
    { intent: 'menu',     role: 'free', handler: menu },
    { intent: 'greeting', role: 'free', handler: greeting },
    { intent: 'count',    role: 'free', handler: count },
    { intent: 'list',     role: 'free', handler: list },
  ],
};