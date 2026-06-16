'use strict';
const trailers = require('../lib/trailers');
const fmt      = require('../lib/format');
const library  = require('../lib/library');
async function trailer({ sock, jid, ctx, intent, role, brand }) {
  const q = (intent.args || '').trim();
  if (!q) {
    return sock.sendMessage(jid, { text: 'Usage: */trailer <title>*  e.g. */trailer iron man 2008*' }, { quoted: ctx });
  }
  const hit = library.searchLibrary(q, 1)[0];
  const t = await trailers.lookupTrailer({
    contentKey: hit && hit.fingerprint,
    title:      (hit && (hit.tmdb_title || hit.name)) || q,
    year:       hit && hit.tmdb_year,
    kind:       hit && (hit.mediatype === 'tv' || hit.mediatype === 'series' || hit.mediatype === 'drama') ? 'tv' : 'movie',
  });
  let body = trailers.buildTrailerMessage(t, fmt.brandFooter());
  if (role === 'free' && hit) {
    body += `\n\n` + fmt.premiumPitch(`Already have *${hit.tmdb_title || hit.name}* in the cloud — Premium gets you the full file`);
  } else if (role === 'free') {
    body += `\n\n` + fmt.premiumPitch('Premium members can download the full title');
  }
  return sock.sendMessage(jid, { text: body }, { quoted: ctx });
}
module.exports = {
  name: 'trailers',
  version: '2.0.0',
  commands: [
    { intent: 'trailer', role: 'free', handler: trailer },
  ],
};