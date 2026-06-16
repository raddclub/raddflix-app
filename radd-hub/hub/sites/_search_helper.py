from __future__ import annotations
import re
_SKIP = {
    "category", "tag", "page=", "feed", "t.me", "telegram",
    "#", "?s=", "?q=", "/search", "login", "signup", "contact",
    "dmca", "privacy", "facebook", "twitter", "instagram", "youtube",
}
_STOPWORDS = {
    "the", "a", "an", "of", "and", "or", "in", "on", "at", "to",
    "for", "is", "it", "with", "from", "by", "as",
}
_WB = r"(?<![a-z0-9])"   # zero-width word-start (not preceded by alnum)
_WE = r"(?![a-z0-9])"    # zero-width word-end   (not followed  by alnum)


def _word_in(word: str, text: str) -> bool:
    """True iff `word` appears as a whole word in `text` (case-insensitive)."""
    return bool(re.search(_WB + re.escape(word.lower()) + _WE, text.lower()))


def _title_score(movie_name: str, slug: str, link_text: str = "") -> float:
    raw_words = [w.lower() for w in movie_name.split() if len(w) >= 2]
    if not raw_words:
        return 0.0
    sig_words = [
        w for w in raw_words
        if w not in _STOPWORDS and not re.fullmatch(r"(?:19|20)\d{2}", w)
    ]
    if not sig_words:
        sig_words = raw_words

    combined = slug.lower() + " " + link_text.lower()

    # Every word must match as a whole word, not a substring.
    # "stree" must NOT match inside "street", "2" must NOT match inside "2024".
    sig_matched   = [w for w in sig_words if _word_in(w, combined)]
    sig_unmatched = [w for w in sig_words if not _word_in(w, combined)]

    if not sig_matched:
        return 0.0

    # Hard requirement: the FIRST significant word (title root) must be present.
    # This prevents "Smile 2" from being a match when searching "Pushpa 2".
    if not _word_in(sig_words[0], combined):
        return 0.0

    matched_all = [w for w in raw_words if _word_in(w, combined)]
    score: float = len(matched_all) * 2 - len(sig_unmatched) * 2
    if len(sig_matched) == len(sig_words):
        score += 5
    if re.search(r"(?:19|20)\d{2}", slug.lower()):
        score += 1
    return score if score > 0 else 0.0


def find_movie_url(page, base_url: str, movie_name: str) -> str | None:
    base_url = base_url.rstrip("/")
    seen: set[str] = set()
    candidates: list[tuple[float, str]] = []
    for link in page.query_selector_all("a[href]"):
        href = (link.get_attribute("href") or "").strip()
        text = (link.inner_text() or "").strip()
        if not href:
            continue
        if any(s in href for s in _SKIP):
            continue
        if href.startswith("/"):
            href = base_url + href
        if not href.startswith("http"):
            continue
        if base_url not in href:
            continue
        if href == base_url or href == base_url + "/":
            continue
        if href in seen:
            continue
        seen.add(href)
        slug_part = href.split("?")[0].replace(base_url, "").strip("/")
        depth = slug_part.count("/")
        if depth > 3:
            continue
        score = _title_score(movie_name, slug_part, text)
        if score > 0:
            candidates.append((score, href))
    if candidates:
        candidates.sort(key=lambda x: x[0], reverse=True)
        return candidates[0][1]
    for link in page.query_selector_all("article a[href], .post a[href], .entry a[href]"):
        href = (link.get_attribute("href") or "").strip()
        if not href or any(s in href for s in _SKIP):
            continue
        if href.startswith("/"):
            href = base_url + href
        if href.startswith(base_url) and href not in seen:
            return href
    return None


def _is_valid_post(href: str, base_url: str) -> bool:
    if not href:
        return False
    if href.startswith("/"):
        href = base_url + href
    if not href.startswith("http"):
        return False
    if base_url not in href:
        return False
    return not any(s in href for s in _SKIP)
