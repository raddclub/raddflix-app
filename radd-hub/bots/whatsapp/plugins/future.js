'use strict';
const fmt = require('../lib/format');
function comingSoon(kind) {
  return async ({ sock, jid, ctx, brand }) => {
    return sock.sendMessage(jid, {
      text: `🚧 *${kind}*  is coming soon to ${brand.name}.\n\n` +
            `Subscribe to */price* to get notified the moment it launches — ` +
            `Premium members get early access.` + fmt.brandFooter(),
    }, { quoted: ctx });
  };
}
module.exports = {
  name: 'future',
  version: '0.1.0',
  commands: [
    { intent: 'apps',     role: 'free', handler: comingSoon('Apps catalog') },
    { intent: 'software', role: 'free', handler: comingSoon('Software downloads') },
    { intent: 'books',    role: 'free', handler: comingSoon('Books / PDFs') },
    { intent: 'yt',       role: 'free', handler: comingSoon('YouTube downloader') },
    { intent: 'youtube',  role: 'free', handler: comingSoon('YouTube downloader') },
    { intent: 'music',    role: 'free', handler: comingSoon('Music library') },
    { intent: 'games',    role: 'free', handler: comingSoon('Games catalog') },
  ],
};