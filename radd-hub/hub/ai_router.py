from __future__ import annotations
import logging
from . import db

log = logging.getLogger("hub.ai_router")

# ── Only real, working plugins ────────────────────────────────────────────────
_ALL_SITES = ["VegaMovies", "KatMovieHD", "RogMovies", "SSRMovies", "RareAnimes"]

_CATEGORIES: dict[str, list[str]] = {
    "anime":   ["RareAnimes", "VegaMovies", "KatMovieHD", "SSRMovies", "RogMovies"],
    "indian":  ["RogMovies", "SSRMovies", "VegaMovies", "KatMovieHD", "RareAnimes"],
    "punjabi": ["RogMovies", "SSRMovies", "VegaMovies", "KatMovieHD", "RareAnimes"],
    "english": ["VegaMovies", "KatMovieHD", "SSRMovies", "RogMovies", "RareAnimes"],
    "both":    ["VegaMovies", "KatMovieHD", "RogMovies", "SSRMovies", "RareAnimes"],
}

_ANIME_KEYWORDS = {
    "one piece", "naruto", "boruto", "demon slayer", "jujutsu", "attack on titan",
    "dragon ball", "bleach", "hunter x hunter", "my hero academia", "fairy tail",
    "fullmetal", "sword art online", "tokyo ghoul", "death note", "chainsaw man",
    "oshi no ko", "vinland saga", "anime", "hentai", "ova", "isekai",
}
_PUNJABI_KEYWORDS = {"ardaas", "jatt", "singh", "punjabi", "oye lucky", "shadaa"}
_INDIAN_KEYWORDS = {
    "hindi", "bolly", "south indian", "desi", "pathaan", "salaar", "mirzapur",
    "shah rukh", "srk", "aamir khan", "hrithik", "akshay kumar", "rohit shetty",
    "karan johar", "baazigar", "dilwale", "stree", "vikram", "bahubali",
    "tollywood", "kollywood", "malayalam", "kannada", "telugu", "tamil",
    "brahmastra", "jawan", "dunki", "animal", "fighter", "pushpa",
}


def classify_movie(title: str) -> str:
    t = title.lower()
    if any(kw in t for kw in _ANIME_KEYWORDS):
        return "anime"
    if any(kw in t for kw in _PUNJABI_KEYWORDS):
        return "punjabi"
    if any(kw in t for kw in _INDIAN_KEYWORDS):
        return "indian"
    return "both"


def get_prioritised_sites(title: str) -> list[str]:
    """Return all real plugin names, best-match first for this title."""
    cat = classify_movie(title)
    log.info("[AI Router] '%s' -> category=%s", title, cat)
    priority = _CATEGORIES.get(cat, _CATEGORIES["both"])
    # Deduplicate while preserving order, include every real site
    seen: set[str] = set()
    result: list[str] = []
    for s in priority:
        if s not in seen and s in _ALL_SITES:
            seen.add(s)
            result.append(s)
    for s in _ALL_SITES:
        if s not in seen:
            result.append(s)
    return result


def get_all_sites() -> list[str]:
    """Return every real plugin name."""
    return list(_ALL_SITES)
