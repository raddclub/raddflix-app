import re
import time
import json
import difflib
import logging
import requests
import schema
log = logging.getLogger("enricher")
TMDB_BASE = "https://api.themoviedb.org/3"
POSTER_BASE = "https://image.tmdb.org/t/p/w500"
BACKDROP_BASE = "https://image.tmdb.org/t/p/w1280"
_last_call = 0.0
_MIN_INTERVAL = 0.27
def _rate_limit():
    global _last_call
    elapsed = time.time() - _last_call
    if elapsed < _MIN_INTERVAL:
        time.sleep(_MIN_INTERVAL - elapsed)
    _last_call = time.time()
def _get_key() -> dict:
    row = schema.get_next_api_key('tmdb')
    if not row:
        return {}
    return row
def _tmdb_get(path: str, params: dict = None) -> dict:
    tried = set()
    while True:
        key_row = schema.get_next_api_key('tmdb')
        if not key_row or key_row.get('id') in tried:
            break
        k_id = key_row['id']
        tried.add(k_id)
        api_key = key_row['api_key']
        p = dict(params or {})
        p['api_key'] = api_key
        _rate_limit()
        try:
            r = requests.get(f"{TMDB_BASE}{path}", params=p, timeout=10)
            schema.mark_key_used(k_id)
            if r.status_code == 200:
                return r.json()
            if r.status_code in (401, 403):
                schema.mark_key_dead(k_id, f"HTTP {r.status_code}")
                continue
            if r.status_code == 429:
                continue
        except Exception as e:
            log.warning("TMDB request failed: %s", e)
    return {}
def _clean_filename(filename: str):
    name = re.sub(r'\.[a-zA-Z0-9]{2,4}$', '', filename)
    name = re.sub(r'[\._\-]', ' ', name)
    patterns = [
        r'\b\d{3,4}p\b', r'\b4[kK]\b', r'\bHDR\b', r'\bWebRip\b',
        r'\bBluRay\b', r'\bx26[45]\b', r'\bh26[45]\b', r'\bAC3\b',
        r'\bDD5 1\b', r'\bDual Audio\b', r'\bESub\b', r'\bHC\b',
        r'\bYTS\b', r'\bRARBG\b', r'\b10bit\b', r'\bHEVC\b',
        r'\bNF\b', r'\bWEB-DL\b', r'\bWEBDL\b', r'\bDVDRip\b',
    ]
    for p in patterns:
        name = re.sub(p, '', name, flags=re.IGNORECASE)
    year_match = re.search(r'\b(19|20)\d{2}\b', name)
    year = year_match.group(0) if year_match else None
    if year:
        name = name.split(year)[0]
    # Strip trailing non-alphanumeric characters (like dots, parentheses)
    name = re.sub(r'[^a-zA-Z0-9]+$', '', name)
    name = re.sub(r'\s+', ' ', name).strip()
    return name, year
def _best_match(results: list, cleaned_title: str, year: str = None) -> dict:
    if not results:
        return None
    cl = cleaned_title.lower().strip()
    def score(item):
        t = (item.get('title') or item.get('name') or '').lower().strip()
        sim = difflib.SequenceMatcher(None, cl, t).ratio()
        item_year = (item.get('release_date') or item.get('first_air_date') or '')[:4]
        yb = 0.2 if year and item_year == str(year) else 0
        pop = min((item.get('popularity') or 0) / 1000, 0.05)
        return sim + yb + pop
    scored = sorted(results, key=score, reverse=True)
    best = scored[0]
    if score(best) < 0.35:
        return None
    return best
def _build_title_data(item: dict, media_type: str, credits: dict, details: dict) -> dict:
    cast = credits.get('cast', [])[:10]
    crew = credits.get('crew', [])
    directors = [c for c in crew if c.get('job') == 'Director']
    cast_names = ', '.join(c.get('name', '') for c in cast if c.get('name'))
    cast_json = json.dumps([{
        'name': c.get('name', ''), 'character': c.get('character', ''),
        'profile': (POSTER_BASE + c['profile_path']) if c.get('profile_path') else ''
    } for c in cast])
    director = directors[0].get('name', '') if directors else ''
    crew_json = json.dumps([{
        'name': c.get('name', ''), 'job': c.get('job', '')
    } for c in crew if c.get('job') in ('Director', 'Writer', 'Screenplay', 'Producer', 'Executive Producer')])
    genres = details.get('genres', [])
    genres_csv = ', '.join(g.get('name', '') for g in genres if g.get('name'))
    languages = details.get('spoken_languages', [])
    languages_csv = ', '.join(
        (l.get('english_name') or l.get('name', '')) for l in languages if l.get('name')
    )
    tmdb_id = item.get('id') or details.get('id')
    if media_type == 'movie':
        title = item.get('title') or details.get('title') or ''
        original = item.get('original_title') or details.get('original_title') or ''
        year = (item.get('release_date') or details.get('release_date') or '')[:4]
        runtime = details.get('runtime')
        status = details.get('status', '')
        tagline = details.get('tagline', '')
        content_key = f"tmdb:{tmdb_id}" if tmdb_id else ''
        imdb_id = details.get('imdb_id', '')
        if imdb_id:
            content_key = f"imdb:{imdb_id}"
        poster = (POSTER_BASE + details['poster_path']) if details.get('poster_path') else (
            (POSTER_BASE + item['poster_path']) if item.get('poster_path') else '')
        return {
            'content_key': content_key, 'tmdb_id': tmdb_id, 'imdb_id': imdb_id,
            'media_type': 'movie', 'title': title, 'original_title': original,
            'year': year, 'rating': item.get('vote_average'),
            'vote_count': item.get('vote_count', 0),
            'poster': poster,
            'overview': details.get('overview') or item.get('overview', ''),
            'genres_csv': genres_csv, 'cast_names': cast_names, 'cast_json': cast_json,
            'director': director, 'crew_json': crew_json,
            'languages_csv': languages_csv, 'runtime': runtime,
            'status': status, 'tagline': tagline,
        }
    else:
        title = item.get('name') or details.get('name') or ''
        original = item.get('original_name') or details.get('original_name') or ''
        year = (item.get('first_air_date') or details.get('first_air_date') or '')[:4]
        end_year = (details.get('last_air_date') or '')[:4]
        seasons = details.get('number_of_seasons')
        status = details.get('status', '')
        tagline = details.get('tagline', '')
        runtime_list = details.get('episode_run_time', [])
        runtime = runtime_list[0] if runtime_list else None
        content_key = f"tmdb:{tmdb_id}" if tmdb_id else ''
        poster = (POSTER_BASE + details['poster_path']) if details.get('poster_path') else (
            (POSTER_BASE + item['poster_path']) if item.get('poster_path') else '')
        return {
            'content_key': content_key, 'tmdb_id': tmdb_id, 'imdb_id': '',
            'media_type': 'series', 'title': title, 'original_title': original,
            'year': year, 'end_year': end_year,
            'rating': item.get('vote_average'), 'vote_count': item.get('vote_count', 0),
            'poster': poster,
            'overview': details.get('overview') or item.get('overview', ''),
            'genres_csv': genres_csv, 'cast_names': cast_names, 'cast_json': cast_json,
            'director': director, 'crew_json': crew_json,
            'languages_csv': languages_csv, 'runtime': runtime,
            'total_seasons': seasons, 'status': status, 'tagline': tagline,
        }
def fetch_full_metadata(query: str, year: str = None, prefer_type: str = 'auto') -> dict:
    cleaned, parsed_year = _clean_filename(query)
    if not year:
        year = parsed_year
    if not cleaned:
        return {}
    def _try_movie():
        params = {'query': cleaned, 'language': 'en-US'}
        if year:
            params['year'] = year
        data = _tmdb_get('/search/movie', params)
        results = data.get('results', [])
        best = _best_match(results, cleaned, year)
        if not best:
            if year:
                data2 = _tmdb_get('/search/movie', {'query': cleaned, 'language': 'en-US'})
                best = _best_match(data2.get('results', []), cleaned, None)
        if not best:
            return None
        mid = best['id']
        details = _tmdb_get(f'/movie/{mid}', {'language': 'en-US'}) or {}
        credits = _tmdb_get(f'/movie/{mid}/credits', {'language': 'en-US'}) or {}
        return _build_title_data(best, 'movie', credits, details)
    def _try_tv():
        params = {'query': cleaned, 'language': 'en-US'}
        if year:
            params['first_air_date_year'] = year
        data = _tmdb_get('/search/tv', params)
        results = data.get('results', [])
        best = _best_match(results, cleaned, year)
        if not best and year:
            data2 = _tmdb_get('/search/tv', {'query': cleaned, 'language': 'en-US'})
            best = _best_match(data2.get('results', []), cleaned, None)
        if not best:
            return None
        tid = best['id']
        details = _tmdb_get(f'/tv/{tid}', {'language': 'en-US'}) or {}
        credits = _tmdb_get(f'/tv/{tid}/credits', {'language': 'en-US'}) or {}
        return _build_title_data(best, 'tv', credits, details)
    if prefer_type == 'tv':
        return _try_tv() or _try_movie() or {}
    result = _try_movie()
    if result:
        return result
    return _try_tv() or {}
def fetch_tmdb_recommendations(tmdb_id: int, media_type: str = 'movie', limit: int = 5) -> list:
    mt = 'movie' if media_type == 'movie' else 'tv'
    data = _tmdb_get(f'/{mt}/{tmdb_id}/recommendations', {'language': 'en-US', 'page': 1})
    results = (data.get('results') or [])[:limit]
    out = []
    for r in results:
        title = r.get('title') or r.get('name') or ''
        year = (r.get('release_date') or r.get('first_air_date') or '')[:4]
        poster = (POSTER_BASE + r['poster_path']) if r.get('poster_path') else ''
        out.append({
            'title': title, 'year': year, 'rating': r.get('vote_average'),
            'poster': poster, 'overview': (r.get('overview') or '')[:200],
        })
    return out
def quick_check(query: str) -> dict:
    cleaned, year = _clean_filename(query)
    if not cleaned:
        return {'found': False}
    def _check_movie():
        data = _tmdb_get('/search/movie', {'query': cleaned, 'language': 'en-US'})
        best = _best_match(data.get('results', []), cleaned, year)
        if best:
            return {
                'found': True, 'media_type': 'movie',
                'title': best.get('title', ''), 'year': (best.get('release_date') or '')[:4],
                'rating': best.get('vote_average'), 'tmdb_id': best.get('id'),
                'poster': (POSTER_BASE + best['poster_path']) if best.get('poster_path') else '',
            }
        return None
    def _check_tv():
        data = _tmdb_get('/search/tv', {'query': cleaned, 'language': 'en-US'})
        best = _best_match(data.get('results', []), cleaned, year)
        if best:
            return {
                'found': True, 'media_type': 'tv',
                'title': best.get('name', ''), 'year': (best.get('first_air_date') or '')[:4],
                'rating': best.get('vote_average'), 'tmdb_id': best.get('id'),
                'poster': (POSTER_BASE + best['poster_path']) if best.get('poster_path') else '',
            }
        return None
    return _check_movie() or _check_tv() or {'found': False}