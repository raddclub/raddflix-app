'use strict';
const GREETINGS = new Set([
  'hi', 'hello', 'hey', 'salam', 'salaam', 'assalamualaikum', 'assalam',
  'aoa', 'as salaam', 'walaikumassalam', 'good morning', 'good evening',
  'good afternoon', 'gm', 'ge', 'sup', 'yo', 'hola',
]);
const HELP_WORDS = new Set(['help', '?', '/help', 'commands', 'cmds']);
const MENU_WORDS = new Set(['menu', 'start', '/start', 'main']);
const KEYWORD_COMMANDS = {
  count:        'count',
  list:         'list',
  library:      'list',
  new:          'list',
  catalog:      'list',
  queue:        'queue',
  status:       'queue',
  cloud:        'queue',
  downloading:  'queue',
  price:        'price',
  plan:         'price',
  premium:      'price',
  subscribe:    'price',
  pay:          'price',
  latest:       'latest',
  trending:     'trending',
  request:      'request',
  me:           'me',
  whoami:       'me',
  account:      'me',
  quota:        'quota',
  refer:        'refer',
  invite:       'refer',
  rewards:      'refer',
  leaderboard:  'leaderboard',
  top:          'top',
  random:       'random',
  surprise:     'random',
  lucky:        'random',
  recommend:    'recommend',
  recommendations: 'recommend',
};
const SEARCH_VERBS  = /^(?:\/?)(find|search|get|movie|drama|series|show|anime|cartoon)\s+/i;
const FORCE_VERB    = /^(?:\/force|\/f)\s+(.+)$/i;
const TRAILER_VERB  = /^(?:\/?)(trailer|preview|teaser)\s+/i;
const DOWNLOAD_VERB = /^(?:\/?)(download|dl)\s+/i;
const REFER_VERB    = /^(?:\/?)refer(?:r(?:al)?)?\s+(\S+)/i;
const ACTOR_VERB    = /^(?:\/actor|actor|cast)\s+(.+)$/i;
const GENRE_VERB    = /^(?:\/genre|genre)\s+(.+)$/i;
const DIRECTOR_VERB = /^(?:\/director|director)\s+(.+)$/i;
const SIMILAR_VERB  = /^(?:\/similar|similar|like)\s+(.+)$/i;
const YEAR_VERB     = /^(?:\/year|year)\s+(\d{4})$/i;
const RELOGIN_RE    = /^\/relogin$/i;
const OTP_RE        = /^\/otp(?:\s+(\d{3,8}))?$/i;
const ADMIN_RE      = /^\/admin\b/i;
const SLASH_CMD_RE  = /^\/([a-z][a-z0-9_-]*)\b\s*(.*)$/i;
const FORCE_BANG    = /^!(.+)$/;
function parse(text) {
  if (!text) return { name: 'noop', args: '' };
  const cleaned = String(text).trim();
  if (!cleaned) return { name: 'noop', args: '' };
  const lower = cleaned.toLowerCase();
  if (ADMIN_RE.test(cleaned))   return { name: 'admin',   args: cleaned };
  if (RELOGIN_RE.test(cleaned)) return { name: 'relogin', args: '' };
  const otp = cleaned.match(OTP_RE);
  if (otp) return { name: 'otp', args: otp[1] || '' };
  const refer = cleaned.match(REFER_VERB);
  if (refer) return { name: 'refer.bind', args: refer[1] };
  if (/^\d{1,3}$/.test(cleaned)) return { name: 'pick', args: cleaned };
  if (lower === 'all')           return { name: 'all',  args: '' };
  if (HELP_WORDS.has(lower)) return { name: 'help',    args: '' };
  if (MENU_WORDS.has(lower)) return { name: 'menu',    args: '' };
  if (GREETINGS.has(lower))  return { name: 'greeting', args: '' };
  if (KEYWORD_COMMANDS[lower]) return { name: KEYWORD_COMMANDS[lower], args: '' };
  const fv = cleaned.match(FORCE_VERB);
  if (fv) return { name: 'find', args: fv[1].trim(), force: true };
  const bang = cleaned.match(FORCE_BANG);
  if (bang) return { name: 'find', args: bang[1].trim(), force: true };
  let m;
  m = cleaned.match(ACTOR_VERB);
  if (m) return { name: 'actor', args: m[1].trim() };
  m = cleaned.match(GENRE_VERB);
  if (m) return { name: 'genre', args: m[1].trim() };
  m = cleaned.match(DIRECTOR_VERB);
  if (m) return { name: 'director', args: m[1].trim() };
  m = cleaned.match(SIMILAR_VERB);
  if (m) return { name: 'similar', args: m[1].trim() };
  m = cleaned.match(YEAR_VERB);
  if (m) return { name: 'year', args: m[1].trim() };
  m = cleaned.match(SEARCH_VERBS);
  if (m) return { name: 'find', args: cleaned.slice(m[0].length).trim() };
  m = cleaned.match(TRAILER_VERB);
  if (m) return { name: 'trailer', args: cleaned.slice(m[0].length).trim() };
  m = cleaned.match(DOWNLOAD_VERB);
  if (m) return { name: 'download', args: cleaned.slice(m[0].length).trim() };
  m = cleaned.match(SLASH_CMD_RE);
  if (m) {
    const cmd = m[1].toLowerCase();
    const args = (m[2] || '').trim();
    if (KEYWORD_COMMANDS[cmd]) return { name: KEYWORD_COMMANDS[cmd], args };
    return { name: cmd, args };
  }
  return { name: 'unknown', args: cleaned };
}
module.exports = { parse };