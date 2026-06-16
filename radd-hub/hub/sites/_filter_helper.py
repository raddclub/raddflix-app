"""
Strict-first quality / language filter for site scrapers.

The new behaviour:
    1.  Build a candidate pool whose URL or anchor text *strictly*
        contains a keyword for the preferred quality.
    2.  If that pool is non-empty -> use it (and never return anything
        from a different quality).
    3.  Otherwise fall back to candidates of "nearest" quality, walking
        QUALITY_ORDER (4k > 1080p > 720p > 480p > 360p) starting from
        the preferred and trying higher first, then lower.
    4.  Within the chosen pool, links that *also* contain a different
        quality tag in their HREF are penalised, so a clean
        "movie_720p.mkv" beats an ambiguous "movie.mkv?ref=480p_pack".
"""
from __future__ import annotations
import re

QUALITY_MAP = {
    "360p":  ["360p"],
    "480p":  ["480p", "dvdscr", "cam"],
    "720p":  ["720p", r"\bhd\b", "hdtv", "hdcam"],
    "1080p": ["1080p", r"\bfhd\b", "full hd", "fullhd", r"\b1080\b"],
    "4k":    ["4k", "2160p", r"\buhd\b", "ultra hd", "4kuhd"],
}

LANG_MAP = {
    "Hindi":   ["hindi", "hin", "dual audio", "dual", "hindi dubbed"],
    "English": ["english", "eng", "original"],
    "Telugu":  ["telugu", "tel"],
    "Tamil":   ["tamil", "tam"],
    "Multi":   ["multi", "multilingual"],
}

QUALITY_ORDER = ["4k", "1080p", "720p", "480p", "360p"]
LANG_ORDER    = ["Hindi", "English", "Multi", "Telugu", "Tamil"]


# ---------------------------------------------------------------------------
# detection helpers
# ---------------------------------------------------------------------------
def detect_quality(text: str) -> str | None:
    """Return the strongest quality tag found in `text`, or None.

    Uses QUALITY_ORDER (highest -> lowest) so '4k' wins over '1080p' when
    both appear.
    """
    t = (text or "").lower()
    for q in QUALITY_ORDER:
        for kw in QUALITY_MAP[q]:
            if "\\" in kw: # regex
                if re.search(kw, t): return q
            elif kw in t:
                return q
    return None


def detect_all_qualities(text: str) -> set[str]:
    """Return a set of all quality tags found in `text`."""
    t = (text or "").lower()
    found = set()
    for q in QUALITY_ORDER:
        for kw in QUALITY_MAP[q]:
            if "\\" in kw: # regex
                if re.search(kw, t): found.add(q)
            elif kw in t:
                found.add(q)
    return found


def matches_quality(text: str, quality: str) -> bool:
    """True if `text` contains any keyword for the given preferred quality."""
    if not quality or quality not in QUALITY_MAP:
        return False
    t = (text or "").lower()
    for kw in QUALITY_MAP[quality]:
        if "\\" in kw:
            if re.search(kw, t): return True
        elif kw in t:
            return True
    return False


def fallback_order(pref: str) -> list[str]:
    """Quality fallback walk:
    User-specific priority: 720p > 480p > 360p > 1080p > 4k
    """
    # Custom priority order as requested by user
    CUSTOM_PRIORITY = ["720p", "480p", "360p", "1080p", "4k"]
    
    # If the user asked for something specific that is not 720p, 
    # we still start with their preference, but then follow the custom order.
    if pref not in CUSTOM_PRIORITY:
        return [pref] + CUSTOM_PRIORITY
    
    idx = CUSTOM_PRIORITY.index(pref)
    # Start with pref, then the rest of CUSTOM_PRIORITY in order
    return [pref] + [q for q in CUSTOM_PRIORITY if q != pref]


# ---------------------------------------------------------------------------
# scoring
# ---------------------------------------------------------------------------
def is_season_query(query: str) -> bool:
    """Return True if the query looks like a TV series / season request."""
    q = (query or "").lower()
    # Keywords
    if any(kw in q for kw in ["season", "series", "complete", "episodes", "episode", "batch", "pack"]):
        return True
    # Regex for S01, S1, Ep1, etc.
    if re.search(r'\b[se]\d+\b', q):
        return True
    return False


def score_link(context_text: str, href: str, config: dict) -> int:
    """Soft preference score (preserved for backward compat with sites)."""
    combined = ((context_text or "") + " " + (href or "")).lower()
    score    = 0
    pref_q   = config.get("quality") or config.get("preferred_quality", "720p")
    pref_l   = config.get("language") or config.get("preferred_language", "Hindi")
    is_series = config.get("content_type") == "series" or is_season_query(config.get("query", ""))

    # ── Size Limit Check (JazzDrive 2GB Limit) ───────────────────────────
    # If the context mentions a size > 1.99 GB, and it's NOT a ZIP/Archive,
    # we penalize it because it won't upload without splitting.
    is_archive = is_archive_url(href) or any(kw in combined for kw in ["zip", "pack", "batch", "complete"])
    if not is_archive and not is_series:
        # Extract GB size: e.g. "Size: 2.5 GB" or "2.5GB"
        size_match = re.search(r"(\d+(?:\.\d+)?)\s*gb", combined)
        if size_match:
            try:
                gb = float(size_match.group(1))
                if gb > 1.99:
                    score -= 300 # Massive penalty for oversized single files
            except: pass

    # ── Season/Series Priority ──────────────────────────────────────────
    if is_series:
        # Heavily prioritize explicit ZIP/Batch links for seasons
        if any(kw in combined for kw in ["batch", "zip", "pack"]):
            score += 500
        elif "complete" in combined:
            score += 200 # Moderate boost for "complete" header
            
        # Penalize individual episode links if a batch might be available
        if "/e" in combined or "episode" in combined:
            score -= 50

    # Check if the context strictly identifies a DIFFERENT quality
    all_q = detect_all_qualities(context_text or "")
    if all_q and pref_q not in all_q:
        # If context only mentions OTHER qualities, massive penalty
        score -= 150
    elif len(all_q) > 1:
        # If context mentions multiple qualities, it's ambiguous.
        # Prefer links that are CLEAN (only mention our pref).
        score -= 30

    if matches_quality(combined, pref_q):
        score += 20
    if pref_l in LANG_MAP and any(kw in combined for kw in LANG_MAP[pref_l]):
        score += 5
    
    # Hard penalty if the HREF itself advertises a different quality.
    href_q = detect_quality(href or "")
    if href_q and pref_q in QUALITY_MAP and href_q != pref_q:
        score -= 200
    return score


# ---------------------------------------------------------------------------
# strict-first selection (the actual bug fix)
# ---------------------------------------------------------------------------
def _split_pref_pool(candidates, pref_q: str, log_fn=None):
    """Split candidates into (matches_pref, others) using HREF + text."""
    pref_kws = QUALITY_MAP.get(pref_q, [])
    matched, others = [], []
    
    if log_fn:
        log_fn(f"[filter] Checking pool for {pref_q} (kws={pref_kws})")

    for entry in candidates:
        # Each entry is (score, href[, text]) -- text may be missing.
        href = entry[1] if len(entry) > 1 else ""
        text = entry[2] if len(entry) > 2 else ""
        combined = ((href or "") + " " + (text or "")).lower()
        
        # Stricter matching: must contain pref keyword AND not strictly be another quality
        has_kw = any(kw in combined for kw in pref_kws)
        href_q = detect_quality(href)
        text_q = detect_quality(text)
        all_q  = detect_all_qualities(text)
        
        is_match = False
        if has_kw:
            if href_q and href_q != pref_q:
                # Contradiction in URL
                pass
            elif all_q and pref_q not in all_q:
                # Contradiction in context (ONLY if context actually has quality tags)
                pass
            else:
                is_match = True
        elif href_q == pref_q:
            # Even if no keywords in text, if HREF itself is exactly the quality, match it.
            is_match = True

        if is_match:
            matched.append(entry)
        else:
            others.append(entry)
            
        if log_fn:
            log_fn(f"  - Link: {href[:40]}... match={is_match} has_kw={has_kw} href_q={href_q} text_q={text_q} all_q={all_q}")
            
    return matched, others


def pick_best_candidates(candidates, config: dict, max_results: int = 5, log_fn=None):
    """Return the best `max_results` candidates honouring preferred_quality.
    """
    if not candidates:
        return []

    pref_q = config.get("quality") or config.get("preferred_quality", "720p")
    chosen: list = []
    actual_q = pref_q
    
    for q in fallback_order(pref_q):
        chosen, _ = _split_pref_pool(candidates, q, log_fn=log_fn)
        if chosen:
            actual_q = q
            if q != pref_q:
                if log_fn: log_fn(f"[filter] No {pref_q} pool found. Falling back to {q}.")
                # Annotate via in-place tuple replacement so callers can log it.
                chosen = [(s, *rest, f"[fallback_quality={q}]")
                          if len(rest) >= 2 else (s, *rest)
                          for (s, *rest) in chosen]
            break

    # Final sort: keep original score order, but penalise HREFs that
    # *also* advertise a wrong quality tag.
    def _final_score(entry):
        score = entry[0]
        href  = entry[1] if len(entry) > 1 else ""
        text  = entry[2] if len(entry) > 2 else ""
        
        href_q = detect_quality(href)
        if href_q and href_q != actual_q:
            score -= 300
        elif href_q == actual_q:
            score += 50
            
        # Also check context text for conflicting quality
        all_q = detect_all_qualities(text)
        if all_q and actual_q not in all_q:
            score -= 200
        elif len(all_q) > 1:
            # Context is messy — give a small penalty
            score -= 40
            
        # If we are in 1080p or 4k tier, prioritize SMALLEST size
        if actual_q in ["1080p", "4k"]:
            combined = (href + " " + text).lower()
            # Extract size in MB for comparison
            m = re.search(r"(\d+(?:\.\d+)?)\s*(gb|mb)", combined)
            if m:
                val = float(m.group(1))
                is_gb = m.group(2) == "gb"
                size_mb = val * 1024 if is_gb else val
                # Subtract size_mb from score to prioritize smaller files
                # We use a scale that makes size a significant but not absolute factor
                # unless scores are close.
                score -= int(size_mb / 10) # 1GB = -100 points
            
        return score

    chosen.sort(key=_final_score, reverse=True)
    
    if log_fn and chosen:
        best_e = chosen[0]
        best_s = _final_score(best_e)
        best_u = best_e[1][:60]
        log_fn(f"[filter] Best candidate: score={best_s} url={best_u}... (quality={actual_q})")

    return chosen[:max_results]


def filter_links(
    candidates: list[tuple[int, str, str]],
    config: dict,
    max_results: int = 5,
) -> list[tuple[int, str, str]]:
    """Public API used by sites. Drop-in replacement for the old function."""
    rescored = []
    for entry in candidates:
        base_s = entry[0]
        href   = entry[1] if len(entry) > 1 else ""
        text   = entry[2] if len(entry) > 2 else ""
        rescored.append((base_s + score_link(text, href, config), href, text))
    return pick_best_candidates(rescored, config, max_results)


def is_archive_url(url: str) -> bool:
    url_lower = (url or "").lower().split("?")[0]
    return any(url_lower.endswith(ext) for ext in [".zip", ".rar", ".7z", ".tar.gz"])
