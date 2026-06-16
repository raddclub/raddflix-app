'use strict';
const library = require('./library');
const fmt     = require('./format');
const pendingSelections = new Map();   
const TTL_MS = 10 * 60 * 1000;
function _setSelection(jid, rows) {
  pendingSelections.set(jid, { rows, expires_at: Date.now() + TTL_MS });
}
function getSelection(jid, idx) {
  const entry = pendingSelections.get(jid);
  if (!entry) return null;
  if (Date.now() > entry.expires_at) { pendingSelections.delete(jid); return null; }
  const i = parseInt(idx, 10);
  if (!Number.isFinite(i) || i < 1 || i > entry.rows.length) return null;
  return entry.rows[i - 1];
}
function clearSelection(jid) { pendingSelections.delete(jid); }
function isMultipart(row) {
  if (!row) return false;
  if (row.season != null || row.episode != null) return true;
  const m = (row.media_type || row.mediatype || '').toLowerCase();
  return m === 'tv' || m === 'series' || m === 'drama' || m === 'show';
}
function _label(r) {
  const sz = fmt.fmtSize(r.size_bytes);
  if (r.season != null && r.episode != null) {
    return `S${String(r.season).padStart(2,'0')}E${String(r.episode).padStart(2,'0')}  ·  ${sz}`;
  }
  if (r.season != null)  return `Season ${r.season}  ·  ${sz}`;
  if (r.episode != null) return `Part ${r.episode}  ·  ${sz}`;
  const name = r.name || r.tmdb_title || 'unknown';
  return `${name}  ·  ${sz}`;
}
function expand(row) {
  let related = [];
  if (row.title_id) {
    related = library.findGroupEpisodes(row.title_id);
  }
  if (!related.length && row.fingerprint) {
    related = library.findByContentKey(row.fingerprint);
  }
  if (!related.length) related = [row];
  return related;
}
function buildEpisodeMessage(row, jid) {
  const related = expand(row);
  if (related.length <= 1) return null;
  _setSelection(jid, related);
  const lines = [
    `📺 *${row.tmdb_title || row.name}*  — ${related.length} part${related.length > 1 ? 's' : ''} found`,
    '',
    ...related.map((r, i) => `*${i + 1})*  ${_label(r)}`),
    '',
    '_Reply with the number (e.g. *3*) to get that part\'s link._',
    '_Reply *all* to get the whole list of links at once._',
  ];
  return lines.join('\n') + fmt.brandFooter();
}
async function buildAllLinksMessage(row, role = 'verified') {
  const related = expand(row);
  if (!related.length) return null;
  const links = await Promise.all(
    related.map(r => fmt.getDownloadLink(r, role).catch(() => '')),
  );
  const lines = [
    `📦 *${row.tmdb_title || row.name}*  — full link bundle (${related.length} part${related.length > 1 ? 's' : ''})`,
    '',
    ...related.map((r, i) => `• ${_label(r)}\n  ${links[i] || '(link pending)'}`),
  ];
  return lines.join('\n') + fmt.brandFooter();
}
module.exports = {
  isMultipart,
  expand,
  buildEpisodeMessage,
  buildAllLinksMessage,
  getSelection,
  clearSelection,
  pendingSelections,
};