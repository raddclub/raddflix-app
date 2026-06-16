'use strict';
const fmt     = require('../lib/format');
const quota   = require('../lib/quota');
const rewards = require('../lib/rewards');
const db      = require('../lib/db');
async function me({ sock, jid, ctx, role, brand, helpers }) {
  const info = rewards.getMine(helpers.senderJid);
  const q    = quota.statusFor(helpers.senderJid, role);
  const lines = [
    `👤 *Your ${brand.name} account*`,
    '',
    `🎟  Tier:  *${role.toUpperCase()}*`,
    `📊  ${quota.formatQuota(q)}`,
    `💎  Points: ${info.points}`,
    `👥  Referral code: *${info.referral_code}*`,
    info.referrer_jid ? `🤝  You joined via someone else.` : '',
    role === 'free' ? '\n' + fmt.premiumPitch('Upgrade to unlock downloads and the full catalog') : '',
  ].filter(Boolean);
  return sock.sendMessage(jid, { text: lines.join('\n') + fmt.brandFooter() }, { quoted: ctx });
}
async function quotaCmd({ sock, jid, ctx, role, helpers }) {
  const q = quota.statusFor(helpers.senderJid, role);
  return sock.sendMessage(jid, {
    text: `📊 *Daily quota*\n\n${quota.formatQuota(q)}\n\nResets at midnight (server time).` + fmt.brandFooter(),
  }, { quoted: ctx });
}
async function refer({ sock, jid, ctx, brand, helpers }) {
  const info = rewards.getMine(helpers.senderJid);
  return sock.sendMessage(jid, { text: rewards.buildReferralMessage(brand, info) + fmt.brandFooter() }, { quoted: ctx });
}
async function bindRefer({ sock, jid, ctx, intent, brand, helpers }) {
  const code = (intent.args || '').trim().toUpperCase();
  if (!code) {
    return sock.sendMessage(jid, { text: 'Usage: */refer <CODE>*' }, { quoted: ctx });
  }
  const ok = rewards.bindReferrerByCode(helpers.senderJid, code);
  if (!ok) {
    return sock.sendMessage(jid, {
      text: `❌ Invalid code, your own code, or you already have a referrer.\n\nYour code: *${rewards.getMine(helpers.senderJid).referral_code}*` + fmt.brandFooter(),
    }, { quoted: ctx });
  }
  return sock.sendMessage(jid, {
    text: `✅ Referral bound! Both you and your friend are getting bonus quota.` + fmt.brandFooter(),
  }, { quoted: ctx });
}
async function leaderboard({ sock, jid, ctx, brand }) {
  const rows = rewards.leaderboard(10);
  return sock.sendMessage(jid, { text: rewards.buildLeaderboardMessage(brand, rows) + fmt.brandFooter() }, { quoted: ctx });
}
async function price({ sock, jid, ctx, brand }) {
  return sock.sendMessage(jid, { text: fmt.premiumPitch(`${brand.name} Premium`) + fmt.brandFooter() }, { quoted: ctx });
}
module.exports = {
  name: 'account',
  version: '2.0.0',
  commands: [
    { intent: 'me',          role: 'free', handler: me },
    { intent: 'quota',       role: 'free', handler: quotaCmd },
    { intent: 'refer',       role: 'free', handler: refer },
    { intent: 'refer.bind',  role: 'free', handler: bindRefer },
    { intent: 'leaderboard', role: 'free', handler: leaderboard },
    { intent: 'price',       role: 'free', handler: price },
  ],
};