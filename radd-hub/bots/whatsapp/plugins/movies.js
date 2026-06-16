'use strict';
const fmt        = require('../lib/format');
const library    = require('../lib/library');
const stream     = require('../lib/streamApi');
const quota      = require('../lib/quota');
const multipart  = require('../lib/multipart');
const safety     = require('../lib/safety');
const db         = require('../lib/db');
function msgParticipant(ctx) {
  return ctx?.key?.participant || ctx?.key?.remoteJid || null;
}
function makeHelpers(helpers) {
  return {
    ...helpers,
    recordSearch:   (jid, q) => db.recordSearch(jid, q),
    isRepeatSearch: (jid, q) => db.isRepeatSearch(jid, q),
  };
}
function quotaExceeded(sock, jid, ctx, q) {
  return sock.sendMessage(jid, {
    text: `⛔ *Daily Limit Reached*\n\n` +
          `You have used your daily download quota.\n` +
          `📊 ${quota.formatQuota(q.status)}\n\n` +
          `_Limit resets at 12:00 AM midnight._` + fmt.brandFooter(),
  }, { quoted: ctx });
}
function fmtTitleList(rows, header, showMeta = true) {
  if (!rows.length) return null;
  const lines = [header, ''];
  const slice = rows.slice(0, 8);
  for (const r of slice) {
    const title = r.tmdb_title || r.name || 'Unknown';
    const year  = r.tmdb_year ? ` (${r.tmdb_year})` : '';
    const rating = r.tmdb_rating ? ` ⭐${parseFloat(r.tmdb_rating).toFixed(1)}` : '';
    const size  = showMeta && r.size_bytes ? `  💾 ${fmt.fmtSize(r.size_bytes)}` : '';
    lines.push(`🎬 *${title}*${year}${rating}${size}`);
    if (showMeta && r.genres_csv) {
      lines.push(`   _${r.genres_csv.split(',').slice(0,3).join(' · ')}_`);
    }
  }
  if (rows.length > 8) lines.push(`\n_... and ${rows.length - 8} more_`);
  return lines.join('\n');
}
async function actorSearch({ sock, jid, ctx, intent, role, helpers }) {
  const actor = (intent.args || '').trim();
  if (!actor) {
    return sock.sendMessage(jid, {
      text: `👥 *Actor Search*\n\nUsage: */actor <actor name>*\n\nExample: */actor Shah Rukh Khan*` + fmt.brandFooter()
    }, { quoted: ctx });
  }
  const hits = library.searchByActor(actor, 12);
  if (!hits.length) {
    return sock.sendMessage(jid, {
      text: `❌ No movies found with actor *"${actor}"* in our library.\n\n` +
            `💡 Try the exact English name as on TMDB.` + fmt.brandFooter()
    }, { quoted: ctx });
  }
  const msg = fmtTitleList(hits, `👥 *Movies with "${actor}":*`);
  return sock.sendMessage(jid, { text: msg + fmt.brandFooter() }, { quoted: ctx });
}
async function genreSearch({ sock, jid, ctx, intent, role, helpers }) {
  const genre = (intent.args || '').trim();
  const validGenres = ['Action','Adventure','Animation','Comedy','Crime','Documentary',
    'Drama','Family','Fantasy','History','Horror','Music','Mystery','Romance',
    'Science Fiction','Thriller','War','Western'];
  if (!genre) {
    return sock.sendMessage(jid, {
      text: `🎭 *Genre Search*\n\nUsage: */genre <genre name>*\n\n` +
            `Available genres:\n${validGenres.map(g => `• _${g}_`).join('\n')}` + fmt.brandFooter()
    }, { quoted: ctx });
  }
  const hits = library.searchByGenre(genre, 12);
  if (!hits.length) {
    const close = validGenres.filter(g => g.toLowerCase().includes(genre.toLowerCase().slice(0,4)));
    const suggest = close.length ? `\n\n💡 Did you mean: ${close.slice(0,3).map(g => `_${g}_`).join(', ')}?` : '';
    return sock.sendMessage(jid, {
      text: `❌ No *"${genre}"* movies found in library.${suggest}` + fmt.brandFooter()
    }, { quoted: ctx });
  }
  const msg = fmtTitleList(hits, `🎭 *${genre} Movies in Library:*`);
  return sock.sendMessage(jid, { text: msg + fmt.brandFooter() }, { quoted: ctx });
}
async function directorSearch({ sock, jid, ctx, intent, role, helpers }) {
  const director = (intent.args || '').trim();
  if (!director) {
    return sock.sendMessage(jid, {
      text: `🎬 *Director Search*\n\nUsage: */director <director name>*\n\nExample: */director Christopher Nolan*` + fmt.brandFooter()
    }, { quoted: ctx });
  }
  const hits = library.searchByDirector(director, 12);
  if (!hits.length) {
    return sock.sendMessage(jid, {
      text: `❌ No movies by *"${director}"* found in our library.` + fmt.brandFooter()
    }, { quoted: ctx });
  }
  const msg = fmtTitleList(hits, `🎬 *Movies by "${director}":*`);
  return sock.sendMessage(jid, { text: msg + fmt.brandFooter() }, { quoted: ctx });
}
async function similarMovies({ sock, jid, ctx, intent, role, helpers }) {
  const title = (intent.args || '').trim();
  if (!title) {
    return sock.sendMessage(jid, {
      text: `💡 *Similar Movies*\n\nUsage: */similar <movie title>*\n\nExample: */similar Inception*` + fmt.brandFooter()
    }, { quoted: ctx });
  }
  try {
    const tmdb = await stream.tmdbCheck(title);
    if (!tmdb || !tmdb.found || !tmdb.tmdb_id) {
      return sock.sendMessage(jid, {
        text: `❌ *"${title}"* not found on TMDB. Can't get recommendations.` + fmt.brandFooter()
      }, { quoted: ctx });
    }
    const recs = await stream.tmdbRecommendations(tmdb.tmdb_id, tmdb.media_type);
    if (!recs || !recs.length) {
      return sock.sendMessage(jid, {
        text: `🤷 No similar movies found for *"${title}"* on TMDB.` + fmt.brandFooter()
      }, { quoted: ctx });
    }
    const lines = [
      `💡 *Movies similar to "${tmdb.title || title}":*`, '',
      ...recs.slice(0, 8).map(r => {
        const year = r.year ? ` (${r.year})` : '';
        const rating = r.rating ? ` ⭐${parseFloat(r.rating).toFixed(1)}` : '';
        return `🎬 *${r.title}*${year}${rating}`;
      }),
      '',
      `_Type any title above to search/download it_`,
    ];
    return sock.sendMessage(jid, { text: lines.join('\n') + fmt.brandFooter() }, { quoted: ctx });
  } catch (e) {
    return sock.sendMessage(jid, {
      text: `⚠️ Could not fetch recommendations. Try again.` + fmt.brandFooter()
    }, { quoted: ctx });
  }
}
async function yearBrowse({ sock, jid, ctx, intent, role, helpers }) {
  const year = (intent.args || '').trim();
  if (!year || !/^\d{4}$/.test(year)) {
    return sock.sendMessage(jid, {
      text: `📅 *Browse by Year*\n\nUsage: */year <year>*\n\nExample: */year 2024*` + fmt.brandFooter()
    }, { quoted: ctx });
  }
  const hits = library.searchByYear(year, 12);
  if (!hits.length) {
    return sock.sendMessage(jid, {
      text: `❌ No movies from *${year}* in our library.` + fmt.brandFooter()
    }, { quoted: ctx });
  }
  const msg = fmtTitleList(hits, `📅 *Movies from ${year}:*`);
  return sock.sendMessage(jid, { text: msg + fmt.brandFooter() }, { quoted: ctx });
}
async function topRated({ sock, jid, ctx }) {
  const hits = library.getTopRated(10);
  if (!hits.length) {
    return sock.sendMessage(jid, {
      text: `📊 *Top Rated*\n\nLibrary is empty. Ask for a movie to get started!` + fmt.brandFooter()
    }, { quoted: ctx });
  }
  const lines = ['🏆 *Top Rated in Our Library:*', ''];
  hits.forEach((r, i) => {
    const title  = r.tmdb_title || r.name || 'Unknown';
    const year   = r.tmdb_year ? ` (${r.tmdb_year})` : '';
    const rating = r.tmdb_rating ? ` ⭐${parseFloat(r.tmdb_rating).toFixed(1)}` : '';
    const dir    = r.director ? `  🎬 ${r.director}` : '';
    lines.push(`${i+1}. *${title}*${year}${rating}${dir}`);
  });
  return sock.sendMessage(jid, { text: lines.join('\n') + fmt.brandFooter() }, { quoted: ctx });
}
async function randomMovie({ sock, jid, ctx, role, helpers }) {
  const h = makeHelpers(helpers);
  const row = library.getRandomTitle();
  if (!row) {
    return sock.sendMessage(jid, {
      text: `🎲 *Surprise Me!*\n\nLibrary is empty. Ask for a movie first!` + fmt.brandFooter()
    }, { quoted: ctx });
  }
  if (role === 'free') {
    const title = row.tmdb_title || row.name;
    const year  = row.tmdb_year ? ` (${row.tmdb_year})` : '';
    const genres = row.genres_csv ? `\n🎭 ${row.genres_csv.split(',').slice(0,3).join(', ')}` : '';
    return sock.sendMessage(jid, {
      text: `🎲 *How about:*\n\n` +
            `🎬 *${title}*${year}${genres}\n` +
            `⭐ ${row.tmdb_rating || '?'}/10\n\n` +
            `_Upgrade to Premium to watch it!_\n` +
            fmt.premiumPitch('Get instant download links') + fmt.brandFooter()
    }, { quoted: ctx });
  }
  const q = quota.consume(h.senderJid, role, row.size_bytes || 0, row.fingerprint, row.tmdb_title || row.name);
  if (!q.ok && q.reason === 'quota') return quotaExceeded(sock, jid, ctx, q);
  const caption = `🎲 *Surprise! Random Pick:*\n\n` + await fmt.fmtUploadCaption(row, role);
  return fmt.sendBranded(sock, jid, row, caption, ctx);
}
async function find({ sock, jid, ctx, role, intent, brand, helpers }) {
  const h     = makeHelpers(helpers);
  const raw   = (intent.args || '').trim();
  const force = !!(intent.force);
  const query = raw;
  if (!query) {
    return sock.sendMessage(jid, {
      text: `❌ Please send a movie or series name.\n\n` +
            `Examples:\n• *Iron Man*\n• *find Dark Knight*\n• *!Inception* _(force)_` +
            fmt.brandFooter()
    }, { quoted: ctx });
  }
  if (!safety.isSafe(query)) {
    return sock.sendMessage(jid, {
      text: `🚫 *Forbidden Content*\n\nSorry, I cannot process requests for adult content. 😇` +
            fmt.brandFooter()
    }, { quoted: ctx });
  }
  const hits     = library.searchLibrary(query);
  const want     = library.tokens(query);
  const top      = hits[0];
  const goodMatch = top && top._score >= Math.max(1, Math.ceil(want.length * 0.6));
  let suggestionText = '';
  if (!goodMatch) {
    const recent = library.recentLibrary(100);
    const titles = Array.from(new Set(recent.map(r => r.tmdb_title || r.name).filter(Boolean)));
    const suggestions = safety.getSuggestions(query, titles, 3);
    if (suggestions.length > 0) {
      suggestionText = `\n\n🤔 *Did you mean:*\n` + suggestions.map(s => `• _${s}_`).join('\n');
    }
  }
  if (role === 'free' || role === 'blocked') {
    if (goodMatch) {
      const title = top.tmdb_title
        ? `${top.tmdb_title}${top.tmdb_year ? ` (${top.tmdb_year})` : ''}`
        : top.name;
      const teaser = `✅ *YES! We have this.*\n\n` +
                     `🎬 *${title}*\n` +
                     (top.tmdb_rating ? `⭐ ${top.tmdb_rating}/10\n` : '') +
                     (top.genres_csv ? `🎭 ${top.genres_csv.split(',').slice(0,3).join(', ')}\n` : '') +
                     `💾 Size: ${fmt.fmtSize(top.size_bytes)}\n\n` +
                     `⚠️ *Links are for Premium members only.*\n` +
                     fmt.premiumPitch('Get the link instantly with Premium') +
                     fmt.brandFooter();
      return fmt.sendBranded(sock, jid, top, teaser, ctx);
    }
    return sock.sendMessage(jid, {
      text: `🔍 *"${query}"* is not in our cloud yet.${suggestionText}\n\n` +
            `🌟 *Premium members* can request any movie and we download it for them!\n` +
            fmt.premiumPitch('Get requesting power with Premium') +
            fmt.brandFooter(),
    }, { quoted: ctx });
  }
  if (goodMatch) {
    if (multipart.isMultipart(top)) {
      const msg = multipart.buildEpisodeMessage(top, jid);
      if (msg) return fmt.sendBranded(sock, jid, top, msg, ctx);
    }
    const q = quota.consume(h.senderJid, role, top.size_bytes || 0, top.fingerprint, top.tmdb_title || top.name);
    if (!q.ok && q.reason === 'quota') return quotaExceeded(sock, jid, ctx, q);
    let caption = `✅ *FOUND IN LIBRARY!*\n\n` + await fmt.fmtUploadCaption(top, role);
    if (hits.length > 1) {
      const others = hits.slice(1, 4).map(h => h.tmdb_title || h.name);
      caption += `\n\n_Also found: ${others.join(', ')}_`;
    }
    await fmt.sendBranded(sock, jid, top, caption, ctx);
    if (top.tmdb_rating && parseFloat(top.tmdb_rating) >= 6.0) {
      try {
        const tmdbId = top.title_id || null;
        if (tmdbId) {
          const recs = await stream.tmdbRecommendations(null, null, top.tmdb_title, top.tmdb_year);
          if (recs && recs.length >= 3) {
            const recLines = [
              `\n💡 *You might also like:*`,
              ...recs.slice(0, 5).map(r => {
                const yr = r.year ? ` (${r.year})` : '';
                const rt = r.rating ? ` ⭐${parseFloat(r.rating).toFixed(1)}` : '';
                return `• ${r.title}${yr}${rt}`;
              }),
              `_Type any title above to get it!_`,
            ];
            setTimeout(() => {
              sock.sendMessage(jid, { text: recLines.join('\n') + fmt.brandFooter() }, { quoted: ctx })
                .catch(() => {});
            }, 2000);
          }
        }
      } catch {}
    }
    return;
  }
  const isRepeat = h.isRepeatSearch(h.senderJid, query);
  const doForce  = force || isRepeat;
  if (!doForce) {
    await sock.sendMessage(jid, {
      text: `🔍 Checking *"${query}"*…`
    }, { quoted: ctx });
    let tmdb = null;
    try { tmdb = await stream.tmdbCheck(query); }
    catch { tmdb = { found: null }; }
    if (tmdb === null || tmdb.found === null) {
    } else if (tmdb.found === false) {
      h.recordSearch(h.senderJid, query);
      return sock.sendMessage(jid, {
        text: `🤔 *"${query}"* was not found on TMDB.\n\n` +
              `This could mean:\n` +
              `• The title spelling is different in English\n` +
              `• It's a very new or unreleased movie\n` +
              `• The name is slightly different on TMDB\n\n` +
              `💡 *Tips:*\n` +
              `• Try the exact English title\n` +
              `• Send *the same name again* to force-search anyway\n` +
              `• Or use *!${query}* to force immediately\n` +
              `• Or: */force ${query}*` +
              `${suggestionText}` +
              fmt.brandFooter(),
      }, { quoted: ctx });
    } else {
      const tmdbTitle = tmdb.title || query;
      const tmdbYear  = tmdb.year ? ` (${tmdb.year})` : '';
      const tmdbType  = tmdb.media_type === 'tv' ? '📺 Series' : '🎬 Movie';
      const rating    = tmdb.rating ? ` · ⭐ ${parseFloat(tmdb.rating).toFixed(1)}` : '';
      await sock.sendMessage(jid, {
        text: `✅ *Found on TMDB:* ${tmdbTitle}${tmdbYear}${rating}\n${tmdbType}\n\n⏬ Adding to download queue…`
      }, { quoted: ctx });
    }
    h.recordSearch(h.senderJid, query);
  } else if (isRepeat) {
    await sock.sendMessage(jid, {
      text: `🔁 *Force-searching "${query}"*\n_(You sent this twice — bypassing TMDB check)_`
    }, { quoted: ctx });
  }
  let result = null;
  try {
    result = await stream.queueAdd(query, doForce ? { force: true } : {});
  } catch (e) {
    return sock.sendMessage(jid, {
      text: '⚠️ Service busy. Please try again in 1 minute.' + fmt.brandFooter()
    }, { quoted: ctx });
  }
  if (result && result.skipped && result.skipped.length > 0) {
    const s = result.skipped[0];
    if (s.reason === 'already_in_library' && s.rows && s.rows.length > 0) {
      const row = s.rows[0];
      const q = quota.consume(h.senderJid, role, row.size_bytes || 0, row.fingerprint, row.tmdb_title || row.name);
      if (!q.ok && q.reason === 'quota') return quotaExceeded(sock, jid, ctx, q);
      let caption = `✅ *ALREADY IN LIBRARY!*\n\n` + await fmt.fmtUploadCaption(row, role);
      if (s.rows.length > 1) {
        caption += `\n\n_Also found: ${s.rows.slice(1, 4).map(h => h.tmdb_title || h.name).join(', ')}_`;
      }
      return fmt.sendBranded(sock, jid, row, caption, ctx);
    }
    if (s.reason === 'series_partially_exists') {
      const row = s.rows[0];
      const count = s.count || s.rows.length;
      const caption = `📂 *SERIES FOUND IN LIBRARY*\n\n` +
                      `Found *${count}* episode(s) of *${row.tmdb_title || row.name}* in cloud.\n\n` +
                      `Type the series name again to browse episodes. ✅` +
                      fmt.brandFooter();
      return fmt.sendBranded(sock, jid, row, caption, ctx);
    }
    if (s.reason === 'already_queued') {
      await sock.sendMessage(jid, {
        text: `⏳ *"${query}"* is already being downloaded!\n\n` +
              `Status: *${s.status}*\n` +
              `I will notify you when it's ready. ✅` +
              fmt.brandFooter()
      }, { quoted: ctx });
      return h.recordPendingRequest({
        jid, user: ctx?.pushName || '', requesterJid: h.senderJid,
        query, jobId: s.job_id, msgId: ctx?.key?.id || null,
        msgParticipant: msgParticipant(ctx),
      });
    }
  }
  const jobId = result && result.job_id ? result.job_id : null;
  h.recordPendingRequest({
    jid, user: ctx?.pushName || '', requesterJid: h.senderJid,
    query, jobId, msgId: ctx?.key?.id || null,
    msgParticipant: msgParticipant(ctx),
  });
  return sock.sendMessage(jid, {
    text: `📥 *Downloading:* "${query}"${suggestionText}\n\n` +
          `⏳ Usually ready in 10–20 minutes.\n` +
          `I will send the link here when it's done. ✅` +
          fmt.brandFooter(),
  }, { quoted: ctx });
}
async function pickEpisode({ sock, jid, ctx, intent, role, helpers }) {
  const arg = (intent.args || intent.name || '').toLowerCase();
  if (arg === 'all') {
    const last = multipart.pendingSelections.get(jid);
    if (!last) return sock.sendMessage(jid, { text: '❌ No series selected. Try searching again.' });
    const row = last.rows[0];
    const msg = await multipart.buildAllLinksMessage(row, role);
    return sock.sendMessage(jid, { text: msg || '(no parts found)' }, { quoted: ctx });
  }
  const row = multipart.getSelection(jid, arg);
  if (!row) return sock.sendMessage(jid, { text: '❌ Invalid selection. Send the number (1, 2, 3...).' });
  const q = quota.consume(helpers.senderJid, role, row.size_bytes || 0, row.fingerprint, row.name);
  if (!q.ok && q.reason === 'quota') {
    return sock.sendMessage(jid, { text: `⛔ Daily limit reached. ${quota.formatQuota(q.status)}` });
  }
  const caption = await fmt.fmtUploadCaption(row, role);
  return fmt.sendBranded(sock, jid, row, caption, ctx);
}
async function queueStatus({ sock, jid, ctx }) {
  const q = await stream.queueGet();
  const active = q.filter(j =>
    j && j.status && ['queued', 'running', 'downloading', 'searching', 'scraping'].includes(
      String(j.status).toLowerCase()
    )
  );
  const stats = library.libraryStats();
  const total = stats.total_files || stats.total || 0;
  const lines = [
    `📊 *Queue & Library Status*`, '',
    `📚 Library: *${total.toLocaleString()}* titles`,
    `⏳ Downloading: *${active.length}* item(s)`,
    active.length
      ? active.map(j => `  • ${j.name || j.query || j.movie} _(${j.status})_`).join('\n')
      : `  _Nothing downloading right now_`,
    '',
    `_Type a movie name to search · /random for a surprise!_`,
  ];
  return sock.sendMessage(jid, { text: lines.join('\n') + fmt.brandFooter() }, { quoted: ctx });
}
async function download({ sock, jid, ctx, role, intent, helpers }) {
  const id = (intent.args || '').trim();
  if (!id) return sock.sendMessage(jid, { text: 'Usage: */download <id>*' });
  const link = (helpers.brand.publicUrl || '').replace(/\/+$/, '') + `/d/${id}`;
  return sock.sendMessage(jid, { text: `🔗 *Your Link:* ${link}` + fmt.brandFooter() });
}
module.exports = {
  name: 'movies',
  version: '3.4.0',
  commands: [
    { intent: 'find',     role: 'free',     handler: find },
    { intent: 'unknown',  role: 'free',     handler: find },
    { intent: 'actor',    role: 'free',     handler: actorSearch },
    { intent: 'genre',    role: 'free',     handler: genreSearch },
    { intent: 'director', role: 'free',     handler: directorSearch },
    { intent: 'similar',  role: 'free',     handler: similarMovies },
    { intent: 'year',     role: 'free',     handler: yearBrowse },
    { intent: 'top',      role: 'free',     handler: topRated },
    { intent: 'random',   role: 'free',     handler: randomMovie },
    { intent: 'download', role: 'verified', handler: download },
    { intent: 'queue',    role: 'free',     handler: queueStatus },
    { intent: 'pick',     role: 'verified', handler: pickEpisode },
    { intent: 'all',      role: 'verified', handler: pickEpisode },
    { intent: 'similar2', role: 'free',     handler: similarMovies },
  ],
};