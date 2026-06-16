'use strict';
const fetch   = require('node-fetch');
const fmt     = require('../lib/format');
const library = require('../lib/library');

const STREAM_API = process.env.STREAM_API || 'http://localhost:5000';

async function recommend({ sock, jid, ctx, brand }) {
  let items = [];
  const botKey = process.env.BOT_API_KEY || '';
  try {
    const r = await fetch(`${STREAM_API}/api/library/recommendations?limit=10`, {
      headers: botKey ? { 'X-Bot-Key': botKey } : {},
      timeout: 10000
    });
    if (r.ok) {
      const d = await r.json();
      items = d.items || [];
    }
  } catch {}

  if (!items.length) {
    const topRated = library.getTopRated(8);
    if (!topRated.length) {
      return sock.sendMessage(jid, {
        text: `🎯 *Recommendations*\n\nNothing in the library yet — search for a movie to get started!` + fmt.brandFooter(),
      }, { quoted: ctx });
    }
    const lines = [`🎯 *Recommended for You:*`, ''];
    topRated.forEach((r, i) => {
      const title  = r.tmdb_title || r.name || 'Unknown';
      const year   = r.tmdb_year ? ` (${r.tmdb_year})` : '';
      const rating = r.tmdb_rating ? ` ★${parseFloat(r.tmdb_rating).toFixed(1)}` : '';
      lines.push(`${i + 1}. *${title}*${year}${rating}`);
    });
    lines.push('', `_Type any title to download it!_`);
    return sock.sendMessage(jid, { text: lines.join('\n') + fmt.brandFooter() }, { quoted: ctx });
  }

  const lines = [`🎯 *Recommended for You:*`, ''];
  items.forEach((x, i) => {
    const star = x.rating ? ` ★${(+x.rating).toFixed(1)}` : '';
    const year = x.year ? ` (${x.year})` : '';
    lines.push(`${i + 1}. *${x.title}*${year}${star}`);
    if (x.why) lines.push(`   _${x.why}_`);
  });
  lines.push('', `_Type any title to get it!_`);
  return sock.sendMessage(jid, { text: lines.join('\n') + fmt.brandFooter() }, { quoted: ctx });
}

async function suggest({ sock, jid, ctx, intent, brand }) {
  const q = (intent.args || '').trim();
  if (!q) return recommend({ sock, jid, ctx, intent, brand });
  const hits = library.searchLibrary(q, 5);
  if (!hits.length) {
    return sock.sendMessage(jid, {
      text: `🤔 No suggestions found for *"${q}"*.\n\nTry */similar ${q}* for TMDB recommendations!` + fmt.brandFooter(),
    }, { quoted: ctx });
  }
  const lines = [`💡 *You might also like:*`, ''];
  hits.forEach((r, i) => {
    const title  = r.tmdb_title || r.name || 'Unknown';
    const year   = r.tmdb_year ? ` (${r.tmdb_year})` : '';
    const rating = r.tmdb_rating ? ` ★${parseFloat(r.tmdb_rating).toFixed(1)}` : '';
    lines.push(`${i + 1}. *${title}*${year}${rating}`);
  });
  lines.push('', `_Type any title to download it!_`);
  return sock.sendMessage(jid, { text: lines.join('\n') + fmt.brandFooter() }, { quoted: ctx });
}

module.exports = {
  name: 'recommend',
  version: '3.0.0',
  commands: [
    { intent: 'recommend', role: 'free', handler: recommend },
    { intent: 'suggest',   role: 'free', handler: suggest },
    { intent: 'watchlist', role: 'free', handler: recommend },
  ],
};
