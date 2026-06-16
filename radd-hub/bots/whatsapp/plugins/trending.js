'use strict';
const library = require('../lib/library');
const fmt     = require('../lib/format');
const fetch   = require('node-fetch');
const stream  = require('../lib/streamApi');

async function latest({ sock, jid, ctx, brand }) {
  const rows = library.getLatestToday(10);
  if (!rows.length) {
    return sock.sendMessage(jid, { 
        text: `📅 *Today's Updates*\n\nNo new movies added today yet. Check back soon! ⏳` + fmt.brandFooter() 
    }, { quoted: ctx });
  }
  const body = `📅 *Today's Latest Releases:*\n\n` +
               rows.map(r => `• *${r.tmdb_title || r.name}*${r.tmdb_year ? ` (${r.tmdb_year})` : ''}`).join('\n') +
               `\n\n_Send the name to get the link!_` + fmt.brandFooter();
  return sock.sendMessage(jid, { text: body }, { quoted: ctx });
}
async function trending({ sock, jid, ctx, brand }) {
  try {
    let apiKey = process.env.TMDB_KEY || '';
    if (!apiKey) {
      const r = await stream.tmdbCheck(); // No query = key check
      apiKey = r.api_key || '';
    }
    if (!apiKey) throw new Error('No API key');
    const res = await fetch(`https://api.themoviedb.org/3/trending/movie/day?api_key=${apiKey}`);
    const data = await res.json();
    const top = data.results.slice(0, 5);
    if (!top || !top.length) return sock.sendMessage(jid, { text: '❌ Could not fetch trending movies.' });
    const pollOptions = top.map(m => `${m.title} (${(m.release_date || '').split('-')[0]})`);
    return sock.sendMessage(jid, {
      poll: {
        name: `🔥 *Trending Today* — Which one should we upload next?`,
        values: pollOptions,
        selectableCount: 1
      }
    }, { quoted: ctx });
  } catch (e) {
    return sock.sendMessage(jid, { text: '⚠️ Trending service unavailable right now.' });
  }
}
async function requestPoll({ sock, jid, ctx, intent }) {
    const movie = (intent.args || '').trim();
    if (!movie) return sock.sendMessage(jid, { text: '❌ Usage: */request <movie name>*' });
    return sock.sendMessage(jid, {
        poll: {
            name: `🙋 *User Request:* Should we download "${movie}"?`,
            values: ['👍 Yes, please!', '👎 No, skip it'],
            selectableCount: 1
        }
    }, { quoted: ctx });
}
module.exports = {
  name: 'trending',
  version: '1.0.0',
  commands: [
    { intent: 'latest',   role: 'free', handler: latest },
    { intent: 'trending', role: 'free', handler: trending },
    { intent: 'request',  role: 'free', handler: requestPoll },
  ],
};