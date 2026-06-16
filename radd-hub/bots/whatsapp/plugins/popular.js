'use strict';
const library = require('../lib/library');
const fmt     = require('../lib/format');

async function popular({ sock, jid, ctx, brand }) {
  const rows = library.getTopRated(10);
  if (!rows.length) {
    return sock.sendMessage(jid, {
      text: `🌟 *Top Picks*\n\nLibrary is empty. Ask for a movie to get started!` + fmt.brandFooter(),
    }, { quoted: ctx });
  }
  const lines = [`🌟 *Top Picks in ${brand.name}:*`, ''];
  rows.forEach((r, i) => {
    const title  = r.tmdb_title || r.name || 'Unknown';
    const year   = r.tmdb_year ? ` (${r.tmdb_year})` : '';
    const rating = r.tmdb_rating ? ` ★${parseFloat(r.tmdb_rating).toFixed(1)}` : '';
    const url    = r.share_url || r.download_url || '';
    lines.push(`${i + 1}. *${title}*${year}${rating}`);
    if (url) lines.push(`   ${url}`);
  });
  lines.push('', '_Type any title above to get it!_');
  return sock.sendMessage(jid, { text: lines.join('\n') + fmt.brandFooter() }, { quoted: ctx });
}

async function topTrending({ sock, jid, ctx, brand }) {
  const rows = library.recentLibrary(10);
  if (!rows.length) {
    return sock.sendMessage(jid, {
      text: `📈 *Trending Now*\n\nNothing uploaded yet. Check back soon!` + fmt.brandFooter(),
    }, { quoted: ctx });
  }
  const lines = [`📈 *Trending Now in ${brand.name}:*`, ''];
  rows.forEach((r, i) => {
    const title  = r.tmdb_title || r.name || 'Unknown';
    const year   = r.tmdb_year ? ` (${r.tmdb_year})` : '';
    const rating = r.tmdb_rating ? ` ★${parseFloat(r.tmdb_rating).toFixed(1)}` : '';
    const url    = r.share_url || r.download_url || '';
    lines.push(`${i + 1}. *${title}*${year}${rating}`);
    if (url) lines.push(`   ${url}`);
  });
  lines.push('', '_Send any title to download it!_');
  return sock.sendMessage(jid, { text: lines.join('\n') + fmt.brandFooter() }, { quoted: ctx });
}

module.exports = {
  name: 'popular',
  version: '3.0.0',
  commands: [
    { intent: 'popular', role: 'free', handler: popular },
  ],
};
