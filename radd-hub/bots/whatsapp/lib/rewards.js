'use strict';
const db = require('./db');
const REFERRAL_BONUS_MB = 5120;     
const REFERRAL_POINTS   = 100;
const STREAK_DAILY_MB   = 50;
const STREAK_DAILY_PTS  = 5;
function getMine(jid) {
  const u = db.getUser(jid);
  const code = db.ensureReferralCode(jid);
  const mine = u || db.getUser(jid);
  return {
    role:           mine.role,
    points:         mine.points || 0,
    referral_code:  code,
    referrer_jid:   mine.referrer_jid || '',
    daily_quota_mb: mine.daily_quota_mb,
    used_today_mb:  mine.used_today_mb || 0,
  };
}
function bindReferrerByCode(jid, code) {
  const ok = db.setReferrerByCode(jid, code);
  if (ok) db.audit('reward.referral.bind', jid, `code=${code}`);
  return ok;
}
function awardDailyStreak(jid) {
  const u = db.getUser(jid);
  db.db.prepare(`UPDATE bot_users SET points = points + ?, daily_quota_mb = daily_quota_mb + ? WHERE jid = ?`)
    .run(STREAK_DAILY_PTS, STREAK_DAILY_MB, u.jid);
  db.audit('reward.streak.daily', jid, `+${STREAK_DAILY_MB} MB / +${STREAK_DAILY_PTS} pts`);
}
function leaderboard(limit = 10) {
  return db.topReferrers(limit);
}
function buildReferralMessage(brand, info) {
  const url = brand.publicUrl
    ? `${brand.publicUrl.replace(/\/+$/, '')}/r/${info.referral_code}`
    : `(ask the admin for the public URL)`;
  return [
    `🎁 *Your ${brand.name} rewards*`,
    '',
    `👥 *Referral code:*  ${info.referral_code}`,
    `🔗 *Share link:*  ${url}`,
    '',
    `💎 *Your points:*  ${info.points}`,
    info.referrer_jid ? `🤝 You joined via someone else's invite.` : `_Share your code so the bot binds new joiners to you automatically._`,
    '',
    `*How rewards work:*`,
    `  • Every friend that joins with your code → *+${REFERRAL_POINTS} points* and *+${REFERRAL_BONUS_MB / 1024} GB / day* quota for you forever.`,
    `  • Every day you use the bot → *+${STREAK_DAILY_MB} MB* extra daily quota.`,
    `  • Top referrer of the week gets *1 free Premium month*.`,
  ].join('\n');
}
function buildLeaderboardMessage(brand, rows) {
  if (!rows.length) return `📊 No leaderboard entries yet — be the first!`;
  const lines = [`🏆 *${brand.name} top referrers*`, ''];
  rows.forEach((r, i) => {
    const tag = (r.pushname || r.jid || 'anon').slice(0, 24);
    lines.push(`*${i + 1}.* ${tag}  ·  ${r.referrals} invites  ·  ${r.points} pts`);
  });
  return lines.join('\n');
}
module.exports = {
  getMine,
  bindReferrerByCode,
  awardDailyStreak,
  leaderboard,
  buildReferralMessage,
  buildLeaderboardMessage,
  REFERRAL_BONUS_MB,
  REFERRAL_POINTS,
  STREAK_DAILY_MB,
  STREAK_DAILY_PTS,
};