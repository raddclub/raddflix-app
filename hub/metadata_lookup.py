from __future__ import annotations
import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
import threading
_BASE = Path(__file__).parent
_CACHE_PATH = _BASE / ".metadata_cache.json"
_CACHE_TTL  = 30 * 24 * 3600           
_cache_lock = threading.Lock()
_LANG_TO_CATEGORY = {
    "hi": "indian", "te": "indian", "ta": "indian", "ml": "indian",
    "kn": "indian", "pa": "indian", "bn": "indian", "mr": "indian",
    "gu": "indian", "ur": "indian", "or": "indian",
    "en": "english", "es": "english", "fr": "english", "de": "english",
    "it": "english", "pt": "english", "ru": "english", "tr": "english",
    "nl": "english", "sv": "english", "no": "english", "da": "english",
    "ko": "english", "zh": "english", "th": "english",
    "ja": "anime",
}
def _coerce_list(v) -> list[str]:
    if not v:
        return []
    if isinstance(v, str):
        return [v.strip()] if v.strip() else []
    if isinstance(v, list):
        return [str(x).strip() for x in v if str(x).strip()]
    return []
from . import db, keys
import urllib.request as _urlreq


def _tmdb_keys(config: dict) -> list[str]:
    # In v3, we primarily use the vault
    k_list = keys.get_all_active_values("tmdb")
    if k_list:
        return k_list
    
    # Fallback to env for legacy support
    keys_env: list[str] = []
    for envname in ("TMDB_API_KEY", "TMDB_API_KEY_1", "TMDB_API_KEY_2",
                    "TMDB_API_KEY_3", "TMDB_API_KEYS"):
        raw = os.environ.get(envname, "")
        keys_env += [k.strip() for k in raw.split(",") if k.strip()]
    return list(dict.fromkeys(keys_env))


def _omdb_keys(config: dict) -> list[str]:
    k_list = keys.get_all_active_values("omdb")
    if k_list:
        return k_list

    keys_env: list[str] = []
    for envname in ("OMDB_API_KEY", "OMDB_API_KEYS", "IMDB_API_KEY"):
        raw = os.environ.get(envname, "")
        keys_env += [k.strip() for k in raw.split(",") if k.strip()]
    return list(dict.fromkeys(keys_env))


# ---------------------------------------------------------------------------
# AI metadata fallback — Groq → Gemini → OpenAI → OpenRouter
# Used for Pakistani / Indian / Hindi / South / Punjabi / Chinese content
# that is absent from TMDB and OMDB.
# ---------------------------------------------------------------------------

_AI_PROMPT_TMPL = """You are a film and TV metadata expert with deep knowledge of Pakistani, Indian, Hindi, South Indian, Punjabi, Urdu, and Chinese cinema.

Find metadata for: "{title}"{year_hint}

Return ONLY valid compact JSON (no markdown, no explanation) with these fields:
{{
  "found": true,
  "title": "canonical English title",
  "original_title": "title in original language script",
  "year": 2024,
  "media_type": "movie",
  "plot": "2-3 sentence synopsis in English",
  "genres": ["Action", "Drama"],
  "cast": ["Actor One", "Actor Two", "Actor Three"],
  "director": "Director Name",
  "country": "PK",
  "language": "Urdu",
  "rating": 7.2
}}

Rules:
- country: ISO 3166-1 alpha-2 code (PK, IN, CN, US …)
- media_type: "movie" or "tv"
- If you genuinely don't know this title, return {{"found": false}}
- Prefer accuracy over guessing
"""


def _call_groq(key: str, prompt: str) -> str | None:
    try:
        req = _urlreq.Request(
            "https://api.groq.com/openai/v1/chat/completions",
            data=json.dumps({
                "model": "llama3-8b-8192",
                "messages": [{"role": "user", "content": prompt}],
                "temperature": 0,
                "max_tokens": 512,
            }).encode(),
            headers={
                "Authorization": f"Bearer {key}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with _urlreq.urlopen(req, timeout=15) as resp:
            d = json.loads(resp.read())
            return d["choices"][0]["message"]["content"].strip()
    except Exception:
        return None


def _call_gemini(key: str, prompt: str) -> str | None:
    try:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={key}"
        req = _urlreq.Request(
            url,
            data=json.dumps({"contents": [{"parts": [{"text": prompt}]}]}).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with _urlreq.urlopen(req, timeout=20) as resp:
            d = json.loads(resp.read())
            return d["candidates"][0]["content"]["parts"][0]["text"].strip()
    except Exception:
        return None


def _call_openai_compat(key: str, base_url: str, model: str, prompt: str) -> str | None:
    try:
        req = _urlreq.Request(
            f"{base_url}/chat/completions",
            data=json.dumps({
                "model": model,
                "messages": [{"role": "user", "content": prompt}],
                "temperature": 0,
                "max_tokens": 512,
            }).encode(),
            headers={
                "Authorization": f"Bearer {key}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with _urlreq.urlopen(req, timeout=20) as resp:
            d = json.loads(resp.read())
            return d["choices"][0]["message"]["content"].strip()
    except Exception:
        return None


def _parse_ai_response(raw: str, title: str, year: int | None) -> dict | None:
    """Extract JSON from AI response and validate it."""
    if not raw:
        return None
    # Strip markdown fences if present
    raw = re.sub(r"```(?:json)?", "", raw).strip().strip("`")
    try:
        data = json.loads(raw)
    except Exception:
        # Try to extract first {...} block
        m = re.search(r"\{.*\}", raw, re.DOTALL)
        if not m:
            return None
        try:
            data = json.loads(m.group())
        except Exception:
            return None

    if not data.get("found", True):
        return None
    if not data.get("title"):
        return None

    lang_str = (data.get("language") or "").lower()
    lang_map = {
        "urdu": "ur", "hindi": "hi", "punjabi": "pa",
        "telugu": "te", "tamil": "ta", "malayalam": "ml",
        "kannada": "kn", "bengali": "bn", "marathi": "mr",
        "chinese": "zh", "mandarin": "zh", "korean": "ko",
        "japanese": "ja", "english": "en",
    }
    iso = lang_map.get(lang_str, "")

    return {
        "source":         "ai",
        "title":          data.get("title") or title,
        "original_title": data.get("original_title") or data.get("title") or title,
        "year":           int(data["year"]) if str(data.get("year", "")).isdigit() else year,
        "original_lang":  iso,
        "lang_hint":      _LANG_TO_CATEGORY.get(iso),
        "imdb_id":        None,
        "tmdb_id":        None,
        "media_type":     data.get("media_type", "movie"),
        "release_date":   str(data.get("year", "")) + "-01-01" if data.get("year") else "",
        "overview":       data.get("plot") or "",
        "genres_csv":     ", ".join(data.get("genres") or []),
        "cast_names":     ", ".join(data.get("cast") or []),
        "director":       data.get("director") or "",
        "country":        (data.get("country") or "")[:2].upper(),
        "language":       data.get("language") or "",
        "rating":         float(data["rating"]) if data.get("rating") else None,
        "alt_titles":     [],
    }


def _ai_search(title: str, year: int | None, config: dict) -> dict | None:
    """Try every configured AI provider in order; return first successful hit."""
    year_hint = f" ({year})" if year else ""
    prompt = _AI_PROMPT_TMPL.format(title=title, year_hint=year_hint)

    # Groq (fast, free)
    for k in keys.get_all_active_values("groq"):
        raw = _call_groq(k, prompt)
        meta = _parse_ai_response(raw, title, year)
        if meta:
            return meta

    # Gemini (Google, free tier)
    for k in keys.get_all_active_values("gemini"):
        raw = _call_gemini(k, prompt)
        meta = _parse_ai_response(raw, title, year)
        if meta:
            return meta

    # OpenAI
    for k in keys.get_all_active_values("openai"):
        raw = _call_openai_compat(k, "https://api.openai.com/v1", "gpt-4o-mini", prompt)
        meta = _parse_ai_response(raw, title, year)
        if meta:
            return meta

    # OpenRouter (free models)
    for k in keys.get_all_active_values("openrouter"):
        raw = _call_openai_compat(k, "https://openrouter.ai/api/v1",
                                  "meta-llama/llama-3.1-8b-instruct:free", prompt)
        meta = _parse_ai_response(raw, title, year)
        if meta:
            return meta

    return None


# ---------------------------------------------------------------------------
# IMDbAPI.dev Fallback — free IMDB data, no key required
# ---------------------------------------------------------------------------

def _imdbapi_search(title: str, year: int | None, media_type: str = "movie") -> dict | None:
    """Search IMDbAPI.dev — free, no API key needed.
    Excellent for Pakistani/Punjabi/South-Asian content absent from TMDB+OMDB.
    Returns same field structure as _tmdb_search / _omdb_search.

    API: api.imdbapi.dev  (v2.7+)
    Search endpoint: GET /search/titles?query=...&limit=5
    """
    if not title:
        return None
    try:
        _BASE = "https://api.imdbapi.dev"
        params = urllib.parse.urlencode({"query": title, "limit": "5"})
        url = f"{_BASE}/search/titles?{params}"
        data = _http_get_json(url, timeout=12)
        # Response shape: {"titles": [...]}
        items = []
        if isinstance(data, dict):
            items = data.get("titles") or data.get("results") or []
        elif isinstance(data, list):
            items = data
        if not items:
            return None

        # Pick best match — prefer matching year and/or media type
        is_tv  = media_type in ("tv", "drama", "anime", "series", "show")
        year_s = str(year) if year else ""
        best   = None
        for item in items:
            itype = (item.get("type") or "").lower()
            iyear = str(item.get("startYear") or "")
            if media_type == "movie" and "series" in itype:
                continue
            if is_tv and itype == "movie":
                continue
            if year_s and iyear == year_s:
                best = item
                break
        if best is None:
            best = items[0]

        itype  = (best.get("type") or "").lower()
        img    = best.get("primaryImage") or {}
        poster = img.get("url") if isinstance(img, dict) else ""
        poster = poster or ""

        # Genres — list of strings in v2 API
        genres_raw = best.get("genres") or []
        genres_csv = ", ".join(
            (g.get("text") if isinstance(g, dict) else str(g))
            for g in genres_raw if g
        )

        # Rating — {"aggregateRating": 8.4, "voteCount": ...}
        rat_obj = best.get("rating") or {}
        rating  = float(rat_obj["aggregateRating"]) if isinstance(rat_obj, dict) and rat_obj.get("aggregateRating") else None

        yr_raw = best.get("startYear")
        yr_int = int(yr_raw) if str(yr_raw or "").isdigit() else year

        return {
            "source":         "imdbapi",
            "title":          best.get("primaryTitle") or best.get("title") or title,
            "original_title": best.get("originalTitle") or best.get("primaryTitle") or title,
            "year":           yr_int,
            "original_lang":  "",
            "lang_hint":      None,
            "imdb_id":        best.get("id") or "",
            "tmdb_id":        None,
            "media_type":     "tv" if "series" in itype else "movie",
            "release_date":   f"{yr_int or ''}-01-01",
            "overview":       best.get("plot") or best.get("description") or "",
            "genres_csv":     genres_csv,
            "cast_names":     "",
            "director":       "",
            "rating":         rating,
            "poster":         poster,
            "alt_titles":     [],
        }
    except Exception:
        pass
    return None


# ---------------------------------------------------------------------------
# YouTube Fallback — trailer thumbnail as last-resort poster
# ---------------------------------------------------------------------------

def _youtube_search(title: str, year: int | None) -> dict | None:
    """Search YouTube for a trailer poster.
    Tries YouTube Data API v3 (vault provider 'youtube') first, then
    falls back to HTML scraping — works with no key at all.
    """
    if not title:
        return None
    query = f"{title} {year or ''} official trailer".strip()

    for yt_key in keys.get_all_active_values("youtube"):
        try:
            q    = urllib.parse.quote_plus(query)
            url  = (f"https://www.googleapis.com/youtube/v3/search"
                    f"?key={yt_key}&q={q}&part=snippet&type=video&maxResults=1")
            data = _http_get_json(url, timeout=10)
            if not data:
                continue
            items = data.get("items") or []
            if not items:
                continue
            vid_id  = items[0]["id"]["videoId"]
            snippet = items[0].get("snippet") or {}
            thumbs  = snippet.get("thumbnails") or {}
            poster  = (thumbs.get("maxres") or thumbs.get("high") or
                       thumbs.get("medium") or {}).get("url", "")
            if not poster:
                poster = f"https://img.youtube.com/vi/{vid_id}/hqdefault.jpg"
            return {
                "source":      "youtube_api",
                "poster":      poster,
                "trailer_url": f"https://www.youtube.com/watch?v={vid_id}",
                "alt_titles":  [],
            }
        except Exception:
            pass

    # HTML scrape fallback — no key needed
    try:
        q   = urllib.parse.quote_plus(query)
        req = urllib.request.Request(
            f"https://www.youtube.com/results?search_query={q}",
            headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"},
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            html = resp.read().decode("utf-8", errors="replace")
        ids = re.findall(r'"videoId":"([A-Za-z0-9_-]{11})"', html)
        if ids:
            vid_id = ids[0]
            return {
                "source":      "youtube_scrape",
                "poster":      f"https://img.youtube.com/vi/{vid_id}/hqdefault.jpg",
                "trailer_url": f"https://www.youtube.com/watch?v={vid_id}",
                "alt_titles":  [],
            }
    except Exception:
        pass
    return None


# ---------------------------------------------------------------------------
# Google Knowledge Graph Fallback
# ---------------------------------------------------------------------------

def _google_search(title: str, year: int | None) -> dict | None:
    """Search Google Knowledge Graph API.
    Uses vault provider 'google' (Google API key with Knowledge Graph enabled).
    No-op if no Google key is configured.
    """
    if not title:
        return None
    for g_key in keys.get_all_active_values("google"):
        try:
            q   = urllib.parse.quote_plus(f"{title} {year or ''}".strip())
            url = (f"https://kgsearch.googleapis.com/v1/entities:search"
                   f"?query={q}&key={g_key}&limit=3"
                   f"&types=Movie&types=TVSeries&types=TVEpisode")
            data = _http_get_json(url, timeout=10)
            if not data:
                continue
            items = data.get("itemListElement") or []
            if not items:
                continue
            result   = items[0].get("result") or {}
            name     = result.get("name") or title
            desc     = result.get("description") or ""
            detailed = result.get("detailedDescription") or {}
            overview = detailed.get("articleBody") or desc
            img      = result.get("image") or {}
            poster   = img.get("contentUrl") or img.get("url") or ""
            types    = result.get("@type") or []
            if isinstance(types, str):
                types = [types]
            mt = "tv" if any("TV" in t or "Series" in t for t in types) else "movie"
            return {
                "source":         "google_kg",
                "title":          name,
                "original_title": name,
                "year":           year,
                "original_lang":  "",
                "lang_hint":      None,
                "imdb_id":        None,
                "tmdb_id":        None,
                "media_type":     mt,
                "release_date":   "",
                "overview":       overview,
                "poster":         poster,
                "alt_titles":     [],
            }
        except Exception:
            pass
    return None

def _load_cache() -> dict:
    with _cache_lock:
        if not _CACHE_PATH.exists():
            return {}
        try:
            return json.loads(_CACHE_PATH.read_text())
        except Exception:
            return {}
def _save_cache(cache: dict) -> None:
    with _cache_lock:
        try:
            _CACHE_PATH.write_text(json.dumps(cache, ensure_ascii=False, indent=1))
        except Exception:
            pass
def _cache_key(title: str, year: int | None) -> str:
    return f"{(title or '').strip().lower()}|{year or ''}"
class _AuthError(Exception):
    """Raised when an API key is rejected (HTTP 401/403)."""

def _http_get_json(url: str, timeout: float = 8.0) -> dict | None:
    try:
        req = urllib.request.Request(url, headers={
            "User-Agent": "Radd-Hub/4.0",
            "Accept":     "application/json",
        })
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8", errors="replace"))
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            raise _AuthError(f"HTTP {e.code} — API key rejected")
        return None
    except Exception:
        return None
def _tmdb_search(title: str, year: int | None, key: str) -> dict | None:
    """Multi-strategy TMDB search.

    Strategy order:
      1. Movie search with year  (English)
      2. Movie search without year  (English) — catches year-off mismatches
      3. TV search with year  (English)
      4. TV search without year  (English)
      5. Movie search in Hindi language  — catches Bollywood/Lollywood titles
      6. TV search in Hindi language
    """
    q = urllib.parse.quote_plus(title or "")
    yp    = f"&year={year}" if year else ""
    yp_tv = f"&first_air_date_year={year}" if year else ""

    # Strategy 1+2: Movie (with year, then without)
    for extra in ([yp, ""] if year else [""]):
        data = _http_get_json(
            f"https://api.themoviedb.org/3/search/movie?api_key={key}&query={q}{extra}"
        )
        if data and data.get("results"):
            hit = _tmdb_pick(data["results"], title, year, "movie", key)
            if hit:
                return hit

    # Strategy 3+4: TV (with year, then without)
    for extra in ([yp_tv, ""] if year else [""]):
        data = _http_get_json(
            f"https://api.themoviedb.org/3/search/tv?api_key={key}&query={q}{extra}"
        )
        if data and data.get("results"):
            hit = _tmdb_pick(data["results"], title, year, "tv", key)
            if hit:
                return hit

    # Strategy 5+6: Hindi language search (covers Bollywood, Lollywood, South dubs)
    for kind, ep in [("movie", yp), ("tv", yp_tv)]:
        data = _http_get_json(
            f"https://api.themoviedb.org/3/search/{kind}?api_key={key}"
            f"&query={q}&language=hi-IN{ep}"
        )
        if data and data.get("results"):
            hit = _tmdb_pick(data["results"], title, year, kind, key)
            if hit:
                return hit

    return None
# _AuthError is re-raised by _http_get_json and propagates through _tmdb_search
# so that enrich() can catch it, mark the key invalid, and skip to the next one.
def _tmdb_pick(results: list, want_title: str, want_year: int | None,
               kind: str, key: str) -> dict | None:
    if not results:
        return None
    wt = (want_title or "").lower().strip()
    def score(r: dict) -> float:
        s = 0.0
        date = r.get("release_date") or r.get("first_air_date") or ""
        if want_year and date.startswith(str(want_year)):
            s += 100
        if r.get("title", "").lower() == wt or r.get("name", "").lower() == wt:
            s += 50
        if r.get("original_title", "").lower() == wt or r.get("original_name", "").lower() == wt:
            s += 30
        s += min(float(r.get("popularity", 0) or 0), 100) * 0.1
        return s
    best = max(results, key=score)
    title = best.get("title") or best.get("name") or want_title
    orig  = best.get("original_title") or best.get("original_name") or title
    date  = best.get("release_date") or best.get("first_air_date") or ""
    year  = int(date[:4]) if date[:4].isdigit() else want_year
    lang  = (best.get("original_language") or "").lower()
    out = {
        "source":         "tmdb",
        "title":          title,
        "original_title": orig,
        "year":           year,
        "original_lang":  lang,
        "lang_hint":      _LANG_TO_CATEGORY.get(lang),
        "imdb_id":        None,
        "tmdb_id":        best.get("id"),
        "media_type":     kind,
        "release_date":   date,
        "overview":       best.get("overview") or "",
        "alt_titles":     [],
    }
    if kind == "movie":
        ext = _http_get_json(
            f"https://api.themoviedb.org/3/movie/{best['id']}/external_ids?api_key={key}"
        )
    else:
        ext = _http_get_json(
            f"https://api.themoviedb.org/3/tv/{best['id']}/external_ids?api_key={key}"
        )
    if ext and ext.get("imdb_id"):
        out["imdb_id"] = ext["imdb_id"]
    if kind == "movie":
        alt = _http_get_json(
            f"https://api.themoviedb.org/3/movie/{best['id']}/alternative_titles?api_key={key}"
        )
        titles_field = (alt or {}).get("titles") or []
    else:
        alt = _http_get_json(
            f"https://api.themoviedb.org/3/tv/{best['id']}/alternative_titles?api_key={key}"
        )
        titles_field = (alt or {}).get("results") or []
    out["alt_titles"] = [
        t.get("title") for t in titles_field if t.get("title")
    ]
    return out
def _omdb_search(title: str, year: int | None, key: str) -> dict | None:
    q = urllib.parse.quote_plus(title or "")
    yp = f"&y={year}" if year else ""
    data = _http_get_json(
        f"https://www.omdbapi.com/?apikey={key}&t={q}{yp}&type=movie"
    )
    if not data or data.get("Response") != "True":
        data = _http_get_json(
            f"https://www.omdbapi.com/?apikey={key}&t={q}{yp}"
        )
    if not data or data.get("Response") != "True":
        return None
    lang_str = (data.get("Language") or "").split(",")[0].strip().lower()
    lang_map = {
        "english": "en", "hindi": "hi", "telugu": "te", "tamil": "ta",
        "malayalam": "ml", "kannada": "kn", "punjabi": "pa", "japanese": "ja",
        "korean": "ko", "spanish": "es", "french": "fr",
    }
    iso = lang_map.get(lang_str, "")
    yr = data.get("Year") or ""
    yrm = re.search(r"(?:19|20)\d{2}", yr)
    return {
        "source":         "omdb",
        "title":          data.get("Title") or title,
        "original_title": data.get("Title") or title,
        "year":           int(yrm.group()) if yrm else year,
        "original_lang":  iso,
        "lang_hint":      _LANG_TO_CATEGORY.get(iso),
        "imdb_id":        data.get("imdbID"),
        "tmdb_id":        None,
        "media_type":     ("tv" if data.get("Type") == "series" else "movie"),
        "release_date":   data.get("Released") or "",
        "overview":       data.get("Plot") or "",
        "alt_titles":     [],
    }
def enrich(parsed, config: dict, log_fn=None) -> dict | None:
    title = getattr(parsed, "title", None) or (parsed.get("title") if isinstance(parsed, dict) else None)
    year  = getattr(parsed, "year",  None) or (parsed.get("year")  if isinstance(parsed, dict) else None)
    if not title:
        return None
    def say(msg):
        if log_fn:
            log_fn(f"[Metadata] {msg}")
    cache = _load_cache()
    ck = _cache_key(title, year)
    hit = cache.get(ck)
    if hit and (time.time() - hit.get("_ts", 0)) < _CACHE_TTL:
        meta = {k: v for k, v in hit.items() if not k.startswith("_")}
        if meta:
            say(f"cache hit ({meta.get('source')}) → {meta.get('title')} ({meta.get('year')}) [{meta.get('original_lang')}]")
            return meta
    # 1. IMDbAPI.dev — PRIMARY: free, no key, full IMDb catalogue
    #    Best first choice: covers Bollywood, Lollywood, South Asian, anime, Hollywood
    #    No API key needed, fast, and finds Pakistani/Indian content TMDB often misses
    try:
        _mt = getattr(parsed, "media_type", None) if not isinstance(parsed, dict) else parsed.get("media_type")
        meta = _imdbapi_search(title, year, _mt or "movie")
        if meta:
            meta["_ts"] = int(time.time())
            cache[ck] = meta
            _save_cache(cache)
            say(f"IMDb → {meta['title']} ({meta.get('year')}) id={meta.get('imdb_id')!r}")
            return {k: v for k, v in meta.items() if not k.startswith("_")}
    except Exception as e:
        say(f"IMDbAPI error: {e}")

    # 2. OMDB — IMDb-backed supplement (requires omdb vault key)
    for key in _omdb_keys(config):
        try:
            meta = _omdb_search(title, year, key)
            if meta:
                meta["_ts"] = int(time.time())
                cache[ck] = meta
                _save_cache(cache)
                say(f"OMDB → {meta['title']} ({meta['year']}) [{meta['original_lang']}] → {meta['lang_hint']}")
                return {k: v for k, v in meta.items() if not k.startswith("_")}
        except _AuthError as e:
            say(f"OMDB key rejected ({e}) — marking invalid, trying next key")
            keys.mark_invalid("omdb", key)
            continue
        except Exception as e:
            say(f"OMDB error: {e}")
            continue

    # 3. TMDB — best poster quality, good for Hollywood/Bollywood (requires tmdb vault key)
    for key in _tmdb_keys(config):
        try:
            meta = _tmdb_search(title, year, key)
            if meta:
                meta["_ts"] = int(time.time())
                cache[ck] = meta
                _save_cache(cache)
                say(f"TMDB → {meta['title']} ({meta['year']}) [{meta['original_lang']}] → {meta['lang_hint']}")
                return {k: v for k, v in meta.items() if not k.startswith("_")}
        except _AuthError as e:
            say(f"TMDB key rejected ({e}) — marking invalid, trying next key")
            keys.mark_invalid("tmdb", key)
            continue
        except Exception as e:
            say(f"TMDB error: {e}")
            continue

    # 4. AI fallback — Groq → Gemini → OpenAI → OpenRouter
    #    Best for Pakistani/Indian/South/Punjabi/Chinese content absent from IMDb/OMDB/TMDB
    say("IMDb + OMDB + TMDB all failed — trying AI fallback (Groq/Gemini/OpenAI/OpenRouter) …")
    try:
        meta = _ai_search(title, year, config)
        if meta:
            meta["_ts"] = int(time.time())
            cache[ck] = meta
            _save_cache(cache)
            say(f"AI({meta.get('source','ai')}) → {meta['title']} ({meta.get('year')}) "
                f"[{meta.get('original_lang')}] lang={meta.get('language')} "
                f"country={meta.get('country')}")
            return {k: v for k, v in meta.items() if not k.startswith("_")}
        else:
            say("AI fallback returned no result for this title")
    except Exception as e:
        say(f"AI fallback error: {e}")

    # 5. YouTube — trailer thumbnail as poster (no plot/cast metadata)
    try:
        meta = _youtube_search(title, year)
        if meta:
            meta["_ts"] = int(time.time())
            cache[ck] = meta
            _save_cache(cache)
            say(f"YouTube ({meta.get('source','yt')}) -> poster+trailer for {title!r}")
            return {k: v for k, v in meta.items() if not k.startswith("_")}
    except Exception as e:
        say(f"YouTube fallback error: {e}")

    # 6. Google Knowledge Graph — name/description/poster (requires 'google' vault key)
    try:
        meta = _google_search(title, year)
        if meta:
            meta["_ts"] = int(time.time())
            cache[ck] = meta
            _save_cache(cache)
            say(f"Google KG -> {meta.get('title')!r} ({meta.get('year')})")
            return {k: v for k, v in meta.items() if not k.startswith("_")}
    except Exception as e:
        say(f"Google KG error: {e}")

    say("no provider returned metadata (continuing without enrichment)")
    return None
def has_any_key(config: dict) -> bool:
    """Return True if any enrichment source is available.
    Vault providers: tmdb, omdb, groq, gemini, openai, openrouter, youtube, google.
    IMDbAPI.dev and YouTube HTML scrape always work (no key needed).
    """
    ai_providers = ("groq", "gemini", "openai", "openrouter")
    has_ai = any(keys.get_all_active_values(p) for p in ai_providers)
    return bool(_tmdb_keys(config) or _omdb_keys(config) or has_ai or True)