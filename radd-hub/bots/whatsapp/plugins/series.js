'use strict';
const multipart = require('../lib/multipart');
const fmt       = require('../lib/format');
async function listSelection({ sock, jid, ctx }) {
  const last = multipart.pendingSelections.get(jid);
  if (!last) {
    return sock.sendMessage(jid, { text: 'No pending series selection. Run */find <title>* first.' }, { quoted: ctx });
  }
  const lines = [
    `📺 Pending selection (${last.rows.length} parts):`,
    '',
    ...last.rows.map((r, i) => `*${i + 1})*  ${r.name}  ·  ${fmt.fmtSize(r.size_bytes)}`),
    '',
    '_Reply with the number or *all* to receive every link._',
  ];
  return sock.sendMessage(jid, { text: lines.join('\n') + fmt.brandFooter() }, { quoted: ctx });
}
module.exports = {
  name: 'series',
  version: '2.0.0',
  commands: [
    { intent: 'parts',    role: 'verified', handler: listSelection },
    { intent: 'episodes', role: 'verified', handler: listSelection },
  ],
};