'use strict';
const fmt    = require('../lib/format');
const stream = require('../lib/streamApi');
const db     = require('../lib/db');

function _bar(p) {
  p = Math.max(0, Math.min(100, Math.round(p || 0)));
  const filled = Math.round(p / 10);
  return '▓'.repeat(filled) + '░'.repeat(10 - filled) + ` ${p}%`;
}

async function status({ sock, jid, ctx, helpers }) {
  try {
    let jobs = [];
    try {
      jobs = await stream.queueGet();
    } catch (e) {
      if (helpers?.debug) helpers.debug('status queueGet error: ' + e.message);
    }
    if (!Array.isArray(jobs)) jobs = [];

    const active = jobs.filter(j =>
      j && j.status && ['queued', 'running', 'downloading', 'searching', 'scraping', 'processing']
        .includes(String(j.status).toLowerCase())
    );

    if (!active.length) {
      let recentSearches = [];
      try {
        const sJid = helpers?.senderJid || '';
        recentSearches = db.db.prepare(
          `SELECT query, ts FROM bot_search_history WHERE jid = ? ORDER BY ts DESC LIMIT 5`
        ).all(sJid);
      } catch (dbErr) {
        if (helpers?.debug) helpers.debug('status db error: ' + dbErr.message);
      }

      const lines = [
        `📊 *Queue Status*`, '',
        `✅ No active downloads right now.`,
      ];
      if (recentSearches && recentSearches.length) {
        lines.push('', `📝 *Your recent searches:*`);
        recentSearches.forEach(r => lines.push(`  • _${r.query}_`));
      }
      lines.push('', `_Type a movie name to search or queue a download._`);
      return sock.sendMessage(jid, { text: lines.join('\n') + fmt.brandFooter() }, { quoted: ctx });
    }

    const lines = [`📊 *Download Queue (${active.length} active)*`, ''];
    active.slice(0, 8).forEach(j => {
      const title = j.movie || j.name || j.query || '(unknown)';
      const s     = String(j.status).toUpperCase();
      const pct   = Math.round(j.progress || 0);
      lines.push(`• *${title}*  [${s}]`);
      lines.push(`   ${_bar(pct)}`);
      if (j.message) lines.push(`   _${String(j.message).slice(0, 80)}_`);
    });
    if (active.length > 8) lines.push(`\n_... and ${active.length - 8} more_`);
    lines.push('', `_I will send links here when done. ✅_`);

    return sock.sendMessage(jid, { text: lines.join('\n') + fmt.brandFooter() }, { quoted: ctx });
  } catch (e) {
    if (helpers?.debug) helpers.debug('status command error: ' + e.stack);
    // fallback message
    return sock.sendMessage(jid, { text: '📊 *Queue Status*\n\nService is busy. Try again in a moment.' }, { quoted: ctx });
  }
}

async function myQueue({ sock, jid, ctx, helpers }) {
  const rows = db.db.prepare(
    `SELECT query, ts FROM bot_search_history WHERE jid = ? ORDER BY ts DESC LIMIT 10`
  ).all(helpers.senderJid || '');

  if (!rows.length) {
    return sock.sendMessage(jid, {
      text: `📋 *My Queue*\n\nYou haven't searched for anything yet.\n\nType a movie name to start!` + fmt.brandFooter(),
    }, { quoted: ctx });
  }
  const lines = [`📋 *Your Recent Requests:*`, ''];
  rows.forEach((r, i) => {
    const ago = Math.round((Date.now() / 1000 - r.ts) / 60);
    const t   = ago < 60 ? `${ago}m ago` : `${Math.round(ago / 60)}h ago`;
    lines.push(`${i + 1}. _${r.query}_ (${t})`);
  });
  lines.push('', `_Type any name to check if it's ready!_`);
  return sock.sendMessage(jid, { text: lines.join('\n') + fmt.brandFooter() }, { quoted: ctx });
}

module.exports = {
  name: 'status',
  version: '3.0.0',
  commands: [
    { intent: 'status',   role: 'free', handler: status },
    { intent: 'myqueue',  role: 'free', handler: myQueue },
    { intent: 'mydownloads', role: 'free', handler: myQueue },
  ],
};
