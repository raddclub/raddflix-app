from __future__ import annotations
import re
from dataclasses import dataclass
_LANG_TAGS = {
    "indian":     "indian",
    "hindi":      "indian",
    "bollywood":  "indian",
    "tollywood":  "indian",
    "kollywood":  "indian",
    "telugu":     "indian",
    "tamil":      "indian",
    "malayalam":  "indian",
    "kannada":    "indian",
    "punjabi":    "indian",
    "bhojpuri":   "indian",
    "marathi":    "indian",
    "south":      "indian",
    "south-indian": "indian",
    "pakistani":  "indian",
    "urdu":       "indian",
    "english":    "english",
    "hollywood":  "english",
    "western":    "english",
    "anime":      "anime",
    "japanese":   "anime",
    "manga":      "anime",
    "animated":   "animated",
    "cartoon":    "animated",
    "disney":     "animated",
    "pixar":      "animated",
    "korean":     "english",                             
    "kdrama":     "english",
    "k-drama":    "english",
}
_PUNCT_TO_SPACE = re.compile(r"[\(\)\[\]\{\}<>;,:\.&!?\"`~|\\/\*\^%$#@]+")
_DASH_NORMAL    = re.compile(r"[\u2010-\u2015\u2212]")                       
_QUOTE_NORMAL   = re.compile(r"[\u2018\u2019\u201C\u201D]")                    
_MULTI_SPACE    = re.compile(r"\s+")
_YEAR_PATTERN   = re.compile(r"\b((?:19|20)\d{2})\b")
@dataclass
class ParsedQuery:
    raw:        str                                        
    clean:      str                                                                    
    title:      str                                         
    year:       int | None                             
    lang_hint:  str | None                                                        
    lang_label: str | None
    quality_hint: str | None = None

    def to_dict(self) -> dict:
        return {
            "raw":        self.raw,
            "clean":      self.clean,
            "title":      self.title,
            "year":       self.year,
            "lang_hint":  self.lang_hint,
            "lang_label": self.lang_label,
            "quality_hint": self.quality_hint,
        }

def _normalise(s: str) -> str:
    s = _DASH_NORMAL.sub("-",  s)
    s = _QUOTE_NORMAL.sub("'", s)
    s = s.replace("\\", "")                      
    s = s.replace("/", "")
    
    # Normalize Roman numerals to digits for sequels
    lower = s.lower()
    lower = re.sub(r'\biv\b', '4', lower)
    lower = re.sub(r'\biii\b', '3', lower)
    lower = re.sub(r'\bii\b', '2', lower)
    
    # If anything changed, return the modified version
    if lower != s.lower():
        # Keep case for parts that didn't change if possible, 
        # but for simplicity returning lowercase is fine since downstream lowercases anyway.
        return lower
    return s

def parse(query: str) -> ParsedQuery:
    raw = (query or "").strip()
    if not raw:
        return ParsedQuery(raw="", clean="", title="", year=None,
                           lang_hint=None, lang_label=None)
    s = _normalise(raw)
    s_clean = _PUNCT_TO_SPACE.sub(" ", s)
    s_clean = _MULTI_SPACE.sub(" ", s_clean).strip()
    if not s_clean:
        return ParsedQuery(raw=raw, clean=raw, title=raw, year=None,
                           lang_hint=None, lang_label=None)
    tokens = s_clean.split()
    
    # ── Detect Quality ──
    quality_hint = None
    _Q_MAP = {"4k": "4k", "2160p": "4k", "1080p": "1080p", "720p": "720p", "480p": "480p", "360p": "360p"}
    new_tokens = []
    for t in tokens:
        tl = t.lower()
        if tl in _Q_MAP and not quality_hint:
            quality_hint = _Q_MAP[tl]
        else:
            new_tokens.append(t)
    tokens = new_tokens

    lang_hint  = None
    lang_label = None
    if tokens and tokens[-1].lower() in _LANG_TAGS:
        lang_label = tokens[-1]
        lang_hint  = _LANG_TAGS[tokens[-1].lower()]
        tokens.pop()
    year = None
    year_idx = -1
    for i, t in enumerate(tokens):
        if _YEAR_PATTERN.fullmatch(t):
            year = int(t)
            year_idx = i
            break
    if year_idx >= 0:
        title_tokens = tokens[:year_idx] + tokens[year_idx + 1:]
    else:
        title_tokens = list(tokens)
    
    # --- Clean Title: Remove Noise Words ---
    # We want to keep words like 'All', 'Dead' but remove 'Season', 'Series'
    final_title_tokens = []
    for t in title_tokens:
        tl = t.lower()
        if tl in ["season", "series", "s01", "s02", "s03", "s04", "s05", "s06", "s07", "s08", "s09", "s10", "show", "tv"]:
            continue
        final_title_tokens.append(t)
    
    title = _MULTI_SPACE.sub(" ", " ".join(final_title_tokens)).strip()
    if not title: # Fallback if everything was noise
        title = _MULTI_SPACE.sub(" ", " ".join(title_tokens)).strip()
        
    if year and title:
        clean = f"{title} {year}"
    else:
        clean = title or (str(year) if year else raw)
    return ParsedQuery(
        raw=raw,
        clean=clean,
        title=title or clean,
        year=year,
        lang_hint=lang_hint,
        lang_label=lang_label,
        quality_hint=quality_hint,
    )
_SLUG_GENERIC_NOISE = {
    "hindi", "english", "tamil", "telugu", "malayalam", "kannada", "punjabi",
    "marathi", "urdu", "dubbed", "dual", "audio", "multi", "org", "esubs",
    "esub", "sub", "subs", "subbed",
    "bluray", "blu", "ray", "webrip", "web", "rip", "hdrip", "hdtv", "hd",
    "cam", "dvdscr", "dvdrip", "hdcam", "hdts", "dvd", "remux", "uhd", "x264",
    "x265", "h264", "h265", "hevc", "10bit", "8bit", "aac", "ddp", "atmos",
    "amzn", "nf", "netflix", "amazon", "hotstar", "disney", "hulu", "prime",
    "season", "episode", "complete", "pack", "batch", "series", "show", "tv", 
    "s01", "s02", "s03", "s04", "s05", "s06", "s07", "s08", "s09", "s10",
    "s1", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9",
    "01", "02", "03", "04", "05", "06", "07", "08", "09", "10",
    "download", "movie", "film", "free", "online", "watch", "full",
    "1080p", "720p", "480p", "360p", "2160p", "4k", "fhd",
    "part", "vol", "volume",
    "official", "original", "remastered", "extended", "directors", "cut",
    "uncut", "uncensored", "theatrical", "edition", "version",
    "and", "the", "of", "in", "on", "with", "from", "to", "for", "or",
    "is", "it", "at", "by", "as", "be", "was", "are",
}
def _expand_hyphenated(words: list[str]) -> set[str]:
    out: set[str] = set()
    for w in words:
        wl = w.lower()
        out.add(wl)
        if "-" in wl:
            for part in wl.split("-"):
                if len(part) >= 2:
                    out.add(part)
    return out
def slug_extras(query_sig_words: list[str], slug: str) -> list[str]:
    slug_words = re.findall(r"[a-z0-9]+", slug.lower())
    qset = _expand_hyphenated(query_sig_words)
    return [
        w for w in slug_words
        if len(w) >= 3
        and w not in qset
        and w not in _SLUG_GENERIC_NOISE
        and not _YEAR_PATTERN.fullmatch(w)
    ]
def significant_words(text: str) -> list[str]:
    raw = re.findall(r"[A-Za-z0-9'\-]+", text or "")
    out = []
    for w in raw:
        wl = w.lower()
        if wl in _SLUG_GENERIC_NOISE:
            continue
        if _YEAR_PATTERN.fullmatch(wl):
            continue
            
        # KEEP digits (seasons/parts)
        if wl.isdigit():
            out.append(wl)
            continue
            
        if len(wl) >= 2:
            out.append(wl)
    return out
def levenshtein_distance(s1: str, s2: str) -> int:
    """Calculate the Levenshtein distance between two strings."""
    if len(s1) < len(s2):
        return levenshtein_distance(s2, s1)

    if len(s2) == 0:
        return len(s1)

    previous_row = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        current_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row

    return previous_row[-1]

def string_similarity(s1: str, s2: str) -> float:
    """Returns a similarity score between 0.0 and 1.0."""
    if not s1 or not s2: return 0.0
    s1, s2 = s1.lower(), s2.lower()
    
    # ── Word Order Agnostic Check ──
    # Sort words to handle swaps (e.g. "Dragon House" vs "House Dragon")
    w1 = sorted(re.findall(r"[a-z0-9]+", s1))
    w2 = sorted(re.findall(r"[a-z0-9]+", s2))
    
    s1_norm = " ".join(w1)
    s2_norm = " ".join(w2)
    
    dist = levenshtein_distance(s1_norm, s2_norm)
    max_len = max(len(s1_norm), len(s2_norm))
    if max_len == 0: return 1.0
    return 1.0 - (dist / max_len)

def slug_contains(word: str, slug: str) -> bool:
    sl = slug.lower()
    wl = word.lower()

    # 1. Direct match (with boundary check for short words)
    if len(wl) <= 2:
        # For very short words, require boundary to avoid "us" in "campus"
        pat = rf"\b{re.escape(wl)}\b"
        if re.search(pat, sl):
            return True
        # Also check with hyphens as boundaries since slugs use them
        if re.search(rf"(?:^|[-_]){re.escape(wl)}(?:[-_]|$)", sl):
            return True
    else:
        if wl in sl:
            return True

    # 2. Normalized match (remove all hyphens)
    if len(wl) > 2 and wl.replace("-", "") in sl.replace("-", ""):
        return True

    # 3. Numeric normalization (e.g., '01' matches '1')
    if wl.isdigit():
        # Exclude years from this loose numeric matching to avoid S01 matching 2024
        if len(wl) == 4 and (wl.startswith("19") or wl.startswith("20")):
            return wl in sl
            
        wl_norm = wl.lstrip("0") or "0"
        # Check against all digits in slug
        s_digits = re.findall(r"\d+", sl)
        for sd in s_digits:
            if (sd.lstrip("0") or "0") == wl_norm:
                return True

    # 4. Hyphenated word expansion
    if "-" in wl:
        parts = [p for p in wl.split("-") if len(p) >= 2]
        if parts and all(slug_contains(p, sl) for p in parts):
            return True
    return False