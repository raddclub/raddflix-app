'use strict';
const fetch = require('node-fetch');
const CLOUD = 'https://cloud.jazzdrive.com.pk';
const TTL_MS = 2 * 60 * 1000;
const TIMEOUT_MS = 12_000;
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ' +
           'AppleWebKit/537.36 (KHTML, like Gecko) ' +
           'Chrome/123.0.0.0 Safari/537.36';
const _cache = new Map();   
function extractShareKey(url) {
  if (!url) return null;
  const m = String(url).match(/\/(?:share-landing\/f|share\/f|f)\/([^\/?#]+)/);
  return m ? m[1] : null;
}
function _baseHeaders(shareKey) {
  return {
    'Accept':     'application/json, text/plain, */*',
    'Origin':     CLOUD,
    'Referer':    `${CLOUD}/share/f/${shareKey || ''}`,
    'User-Agent': UA,
  };
}
function _parseCookies(setCookieList) {
  if (!setCookieList || !setCookieList.length) return '';
  return setCookieList
    .map(c => String(c).split(';', 1)[0])
    .filter(Boolean)
    .join('; ');
}
async function _loginShare(shareKey) {
  const r = await fetch(`${CLOUD}/sapi/link/login?action=login`, {
    method: 'POST',
    headers: { ..._baseHeaders(shareKey), 'Content-Type': 'application/json;charset=UTF-8' },
    body: JSON.stringify({ data: { accesstoken: shareKey } }),
    timeout: TIMEOUT_MS,
  });
  if (!r.ok) throw new Error(`login HTTP ${r.status}`);
  const cookies = _parseCookies(r.headers.raw()['set-cookie']);
  const j = await r.json().catch(() => ({}));
  const d = (j && j.data) || j || {};
  const vk = d.validationkey || d.validationKey || d.validation_key
          || j.validationkey || j.validationKey;
  const jsessionid = d.jsessionid || d.JSESSIONID || j.jsessionid;
  if (!vk) throw new Error(`no validationkey in login response (${JSON.stringify(j).slice(0, 200)})`);
  const cookieHeader = cookies || (jsessionid ? `JSESSIONID=${jsessionid}` : '');
  return { vk: String(vk), cookieHeader, jsessionid: jsessionid || null };
}
async function _getMedia(shareKey, vk, cookieHeader) {
  const url = `${CLOUD}/sapi/media/video?action=get&shared=true` +
              `&key=${encodeURIComponent(shareKey)}` +
              `&validationkey=${encodeURIComponent(vk)}`;
  const headers = { ..._baseHeaders(shareKey), 'validation_key': vk };
  if (cookieHeader) headers['Cookie'] = cookieHeader;
  const r = await fetch(url, { headers, timeout: TIMEOUT_MS });
  if (!r.ok) throw new Error(`media HTTP ${r.status}`);
  const j = await r.json().catch(() => ({}));
  const data = (j && j.data) || j || {};
  let records = [];
  for (const k of ['list', 'items', 'videos', 'records', 'files', 'data']) {
    if (Array.isArray(data[k])) { records = data[k]; break; }
    if (Array.isArray(j[k]))    { records = j[k];    break; }
  }
  if (!records.length) {
    if (Array.isArray(data)) records = data;
    else if (data && (data.url || data.id)) records = [data];
  }
  return records;
}
async function _resolve(shareKey) {
  const { vk, cookieHeader, jsessionid } = await _loginShare(shareKey);
  const records = await _getMedia(shareKey, vk, cookieHeader);
  const entry = { vk, cookieHeader, jsessionid, records, ts: Date.now() };
  _cache.set(shareKey, entry);
  return entry;
}
function _pickRecord(records, fallbackName) {
  if (!records || !records.length) return null;
  if (records.length === 1) return records[0];
  if (fallbackName) {
    const target = String(fallbackName).toLowerCase();
    const exact = records.find(r =>
      String(r.name || r.filename || '').toLowerCase() === target);
    if (exact) return exact;
    const head = target.slice(0, 12);
    const partial = records.find(r =>
      String(r.name || r.filename || '').toLowerCase().includes(head));
    if (partial) return partial;
  }
  return records[0];
}
function _buildUrl(record, vk, fallbackName) {
  let base = record.url || record.downloadUrl || record.download_url;
  if (!base) return null;
  if (base.startsWith('/')) base = CLOUD + base;
  else if (!/^https?:\/\//.test(base)) base = CLOUD + '/' + base.replace(/^\/+/, '');
  const name = record.name || record.filename || fallbackName || '';
  const sep  = base.includes('?') ? '&' : '?';
  const needsVk = !/[?&]validationkey=/.test(base);
  const needsName = !/[?&]filename=/.test(base);
  let out = base;
  if (needsVk)   out += `${sep}validationkey=${encodeURIComponent(vk)}`;
  if (needsName) out += `${out.includes('?') ? '&' : '?'}filename=${encodeURIComponent(name)}`;
  return out;
}
async function getLink4ByShareUrl(shareUrl, fallbackName) {
  const shareKey = extractShareKey(shareUrl);
  if (!shareKey) return null;
  let entry = _cache.get(shareKey);
  if (!entry || Date.now() - entry.ts > TTL_MS) {
    try { entry = await _resolve(shareKey); }
    catch (e) {
      console.warn(`[link4] resolve failed for ${shareKey}: ${e.message}`);
      return null;
    }
  }
  const rec = _pickRecord(entry.records, fallbackName);
  if (!rec) return null;
  return _buildUrl(rec, entry.vk, fallbackName);
}
function clearCache(shareUrl) {
  if (!shareUrl) { _cache.clear(); return; }
  const k = extractShareKey(shareUrl);
  if (k) _cache.delete(k);
}
function cacheSize() { return _cache.size; }
module.exports = {
  getLink4ByShareUrl,
  extractShareKey,
  clearCache,
  cacheSize,
  CLOUD,
  _internals: { _loginShare, _getMedia, _resolve, _pickRecord, _buildUrl, _cache },
};