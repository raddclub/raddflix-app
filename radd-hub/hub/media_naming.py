from __future__ import annotations
import logging
import re
from dataclasses import dataclass
from pathlib import PurePosixPath
from typing import Callable, Optional
log = logging.getLogger("radd_flix.naming")

# ── Single source of truth: file types that belong in the media library ──────
# Both the scanner and the uploader import this set so they always agree.

MEDIA_EXTENSIONS: frozenset[str] = frozenset({
    # Video
    ".mp4", ".mkv", ".avi", ".mov", ".m4v", ".webm", ".wmv", ".flv",
    ".ts",  ".m2ts", ".mpg", ".mpeg", ".3gp", ".3g2", ".vob", ".ogv",
    ".rmvb", ".rm", ".divx", ".xvid", ".f4v", ".hevc", ".mts",
    # Audio (standalone media)
    ".mp3", ".aac", ".flac", ".m4a", ".ogg", ".opus", ".wav",
    # Subtitle / companion
    ".srt", ".ass", ".ssa", ".vtt", ".sub", ".idx",
})

# These are NEVER uploaded/indexed — temp/incomplete download files
ALWAYS_SKIP_EXTENSIONS: frozenset[str] = frozenset({
    ".tmp", ".part", ".crdownload", ".download", ".!ut", ".aria2",
})

# These are non-media documents/archives — excluded from scan & upload
NON_MEDIA_EXTENSIONS: frozenset[str] = frozenset({
    ".zip", ".rar", ".7z", ".tar", ".gz", ".bz2", ".xz",
    ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx",
    ".txt", ".csv", ".json", ".xml", ".html", ".htm", ".md",
    ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp", ".tiff", ".svg",
    ".exe", ".apk", ".ipa", ".dmg", ".iso",
    ".py",  ".js",  ".sh",  ".bat", ".ps1",
})
_RE_SXXEXX     = re.compile(r"[._\s-]?[Ss](\d{1,2})[._\s-]?[Ee](\d{1,3})")
_RE_NXM        = re.compile(r"\b(\d{1,2})x(\d{1,3})\b")
_RE_EPISODE    = re.compile(r"\b[Ee]pisode[._\s-]?(\d{1,3})\b")
_RE_SEASON_DIR = re.compile(r"\b[Ss]eason[._\s-]?(\d{1,2})\b")
_JUNK_TOKENS = {
    "1080p", "720p", "2160p", "4k", "uhd", "hdr", "hdr10", "dv", "dolby",
    "bluray", "brrip", "bdrip", "webrip", "web-dl", "webdl", "dvdrip",
    "hdtv", "x264", "x265", "h264", "h265", "hevc", "10bit", "8bit",
    "aac", "ac3", "dts", "ddp5", "dd5", "atmos", "truehd", "5", "1",
    "remux", "imax", "extended", "directors", "director", "cut",
    "proper", "repack", "internal", "limited", "rarbg", "yify", "yts",
    "ettv", "eztv", "hindi", "english", "dual", "audio", "esubs",
}
_RE_YEAR     = re.compile(r"(?:^|[^\d])((?:19|20)\d{2})(?:[^\d]|$)")
_RE_NONALNUM = re.compile(r"[^A-Za-z0-9]+")
@dataclass
class MediaPlan:
    kind: str                                          
    folder_path: list                                                     
    filename: str                                                
    title: str = ""                                      
    year: Optional[str] = None
    season: Optional[int] = None
    episode: Optional[int] = None
    tmdb: Optional[dict] = None
    @property
    def folder_str(self) -> str:
        return str(PurePosixPath(*self.folder_path)) if self.folder_path else ""
    @property
    def remote_full_path(self) -> str:
        return f"{self.folder_str}/{self.filename}" if self.folder_str else self.filename
def derive_media_plan(
    filename: str,
    *,
    tmdb_lookup: Optional[Callable[[str, Optional[str]], Optional[dict]]] = None,
) -> MediaPlan:
    name = _strip_ext(filename)
    season, episode = _detect_season_episode(name)
    is_tv = season is not None and episode is not None
    if is_tv:
        return _plan_tv(filename, name, season, episode, tmdb_lookup)
    return _plan_movie_or_file(filename, name, tmdb_lookup)
def _strip_ext(filename: str) -> str:
    return PurePosixPath(filename).stem
def _detect_season_episode(stem: str):
    m = _RE_SXXEXX.search(stem)
    if m:
        return int(m.group(1)), int(m.group(2))
    m = _RE_NXM.search(stem)
    if m:
        return int(m.group(1)), int(m.group(2))
    m = _RE_EPISODE.search(stem)
    if m:
        season = 1
        m2 = _RE_SEASON_DIR.search(stem)
        if m2:
            season = int(m2.group(1))
        return season, int(m.group(1))
    return None, None
def _extract_year(text: str):
    m = _RE_YEAR.search(text)
    return m.group(1) if m else None
def _clean_tokens(text: str) -> list:
    raw = _RE_NONALNUM.sub(" ", text).split()
    out = []
    for w in raw:
        lw = w.lower()
        if lw in _JUNK_TOKENS:
            break                                                                      
        if lw.isdigit() and len(lw) == 4 and 1900 <= int(lw) <= 2099:
            break                                                     
        out.append(w)
    return out
def _title_case(words: list) -> str:
    return " ".join(w[:1].upper() + w[1:].lower() if w.isalpha() else w for w in words).strip()
_RESERVED_WIN_NAMES = {
    "CON", "PRN", "AUX", "NUL",
    *(f"COM{i}" for i in range(1, 10)),
    *(f"LPT{i}" for i in range(1, 10)),
}


def _sanitize_folder(name: str) -> str:
    """Sanitize a path segment so it can never traverse the filesystem
    or break Windows / POSIX rules.

    Hardening rules (S3 - audit):
      * Strip every path separator (`/`, `\\`) and reserved chars (`:*?"<>|`)
      * Strip control bytes (`\\x00-\\x1f`)
      * Reject `.` / `..` literals (path traversal)
      * Reject leading dot or trailing dot/space
      * Truncate to 200 chars (safe NTFS / ext4 limit)
      * Substitute reserved Windows device names (CON, PRN ...)
    """
    if not name:
        return "Untitled"
    # 1. drop control bytes + separators + windows-reserved chars
    cleaned = re.sub(r'[\x00-\x1f\x7f\\/:*?"<>|]+', " ", name)
    # 2. collapse whitespace
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    # 3. strip leading/trailing dots and spaces (Windows refuses them)
    cleaned = cleaned.strip(". ")
    # 4. forbid traversal literals
    if cleaned in {"", ".", ".."}:
        return "Untitled"
    # 5. windows reserved device names
    stem = cleaned.split(".")[0].upper()
    if stem in _RESERVED_WIN_NAMES:
        cleaned = f"_{cleaned}"
    # 6. length cap
    if len(cleaned) > 200:
        cleaned = cleaned[:200].rstrip(". ")
    return cleaned or "Untitled"


def safe_join_segments(*parts: str) -> str:
    """Sanitize each segment then join with `/`. Useful when you accept
    user-supplied folder names from an upload form."""
    safe = [_sanitize_folder(p) for p in parts if p]
    return "/".join(safe)
_RE_PART = re.compile(r"[._\s-]?[Pp]art[._\s-]?(\d{1,2})")

def _plan_movie_or_file(filename: str, stem: str, tmdb_lookup) -> MediaPlan:
    # Detect Part numbering
    part_match = _RE_PART.search(stem)
    part_num = int(part_match.group(1)) if part_match else None
    
    # Clean the name for year/title extraction
    clean_stem = _RE_PART.sub("", stem) if part_num else stem
    
    year   = _extract_year(clean_stem)
    words  = _clean_tokens(clean_stem)
    title  = _title_case(words) if words else clean_stem
    tmdb = None
    if tmdb_lookup and title:
        try:
            tmdb = tmdb_lookup(title, year)
        except Exception as e:
            log.debug("tmdb lookup failed for %r: %s", title, e)
            tmdb = None
    if tmdb and tmdb.get("title"):
        title = tmdb["title"]
        year  = str(tmdb.get("year") or year or "").strip() or None
        kind  = "movie" if (tmdb.get("media_type") or "movie") != "tv" else "tv"
    else:
        kind  = "movie" if year else "file"
    
    # User Request: movie-name (movie-year) or movie-name part X (movie-year)
    label = title
    if part_num:
        label = f"{title} Part {part_num}"
    
    folder = f"{label} ({year})" if year else label
    folder = _sanitize_folder(folder)
    
    # Clean filename: "Title (Year).ext"
    ext = PurePosixPath(filename).suffix
    clean_filename = f"{folder}{ext}"
    
    return MediaPlan(
        kind=kind,
        folder_path=[folder],
        filename=clean_filename,
        title=title,
        year=year,
        tmdb=tmdb,
    )

def _plan_tv(filename: str, stem: str, season: int, episode: int, tmdb_lookup) -> MediaPlan:
    # Use the first occurrence of Season/Episode markers to cut the show title
    candidates = [m for m in (
        _RE_SXXEXX.search(stem),
        _RE_NXM.search(stem),
        _RE_EPISODE.search(stem),
        _RE_SEASON_DIR.search(stem),
    ) if m]
    
    # Also look for Year as a secondary cut point
    year_match = _RE_YEAR.search(stem)
    
    cut_pos = len(stem)
    if candidates:
        cut_pos = min(m.start() for m in candidates)
    if year_match and year_match.start() < cut_pos:
        cut_pos = year_match.start()
        
    show_raw = stem[:cut_pos].strip(" ._-")
    words    = _clean_tokens(show_raw)
    show     = _title_case(words) if words else show_raw or "Unknown Show"
    
    year: Optional[str] = year_match.group(1) if year_match else None
    tmdb = None
    if tmdb_lookup and show:
        try:
            tmdb = tmdb_lookup(show, year)
        except Exception as e:
            log.debug("tmdb (tv) lookup failed for %r: %s", show, e)
    
    if tmdb and tmdb.get("title"):
        show = tmdb["title"]
        year = str(tmdb.get("year") or year or "").strip() or None
    
    # Build episode filename: "Show Name S01E01.ext"
    ext       = PurePosixPath(filename).suffix
    ep_stem   = f"{show} S{season:02d}E{episode:02d}"
    ep_filename = _sanitize_folder(ep_stem) + ext
    
    # TV season folders: "Show Season N (Year)" when year is known, else "Show Season N".
    folder_label = f"{show} Season {season}"
    if year:
        folder_label = f"{show} Season {season} ({year})"
    
    return MediaPlan(
        kind="tv",
        folder_path=[_sanitize_folder(folder_label)],
        filename=ep_filename,
        title=show,
        year=year,
        season=season,
        episode=episode,
        tmdb=tmdb,
    )
if __name__ == "__main__":
    samples = [
        "salaar.2023.1080p.WEB-DL.x265.mkv",
        "Salaar-2023.mkv",
        "Loki.S01E01.1080p.mkv",
        "Loki.1x02.Glorious.Purpose.mkv",
        "Breaking.Bad.Season.5.Episode.14.mkv",
        "random_video.mp4",
        "Inception (2010) 4K.mkv",
    ]
    for s in samples:
        p = derive_media_plan(s)
        print(f"{s:55s} → kind={p.kind:5s} folder={p.folder_str!r:40s} file={p.filename}")