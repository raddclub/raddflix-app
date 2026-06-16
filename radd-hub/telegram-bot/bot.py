"""RaddFlix Telegram Bot — polling-based, pure requests (no external lib needed).

Commands:
  /start   — welcome + quick intro
  /help    — list all commands
  /search <query>  — search RaddFlix catalog
  /trending        — show 5 trending titles
  /movie <query>   — search movies only
  /show <query>    — search shows/series only
  /quota           — check data quota (requires phone registration)
  /status          — bot status ping

Setup (Oracle server):
  1. Add TELEGRAM_BOT_TOKEN to RaddHub admin Settings → Telegram bot (key vault)
  2. Set ENABLE_TELEGRAM_BOT=true in /etc/supervisor/conf.d/raddflix_wa_bot.conf env
  3. Restart supervisor: supervisorctl restart raddflix_wa_bot

Admin can update token from the admin panel without touching this file.
"""
from __future__ import annotations

import json
import logging
import os
import sys
import time
from pathlib import Path
from typing import Optional

import requests

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger("raddflix.telegram")

# Bot token: read from env first, then fall back to RaddHub DB via local API
BOT_TOKEN: str = os.environ.get("TELEGRAM_BOT_TOKEN", "")
ADMIN_IDS: set[int] = set()

TG_API = f"https://api.telegram.org/bot{BOT_TOKEN}"

_OFFSET = 0
_POLL_TIMEOUT = 30  # long-poll seconds


# ---------------------------------------------------------------------------
# Token bootstrap from RaddHub API
# ---------------------------------------------------------------------------

def _load_token_from_hub() -> str:
    """Fallback: read token from hub DB (plain settings table, not vault).
    Primary path: TELEGRAM_BOT_TOKEN is injected as env var by bots/telegram.py start()."""
    for db_path in [
        Path(__file__).parent.parent / "radd-hub" / "data" / "hub.db",
        Path("/home/ubuntu/radd-hub/data/hub.db"),
    ]:
        if db_path.exists():
            try:
                import sqlite3
                con = sqlite3.connect(str(db_path))
                row = con.execute(
                    "SELECT v FROM settings WHERE k='TELEGRAM_BOT_TOKEN' LIMIT 1"
                ).fetchone()
                con.close()
                if row and row[0]:
                    log.info("Loaded Telegram token from hub settings DB")
                    return row[0]
            except Exception as e:
                log.warning("Could not read hub DB: %s", e)
    return ""


# ---------------------------------------------------------------------------
# Telegram API helpers
# ---------------------------------------------------------------------------

def _tg(method: str, **kwargs) -> Optional[dict]:
    """Call Telegram Bot API. Returns result dict or None on error."""
    try:
        r = requests.post(f"{TG_API}/{method}", json=kwargs, timeout=10)
        data = r.json()
        if not data.get("ok"):
            log.warning("TG %s error: %s", method, data.get("description"))
            return None
        return data.get("result")
    except Exception as e:
        log.error("TG %s exception: %s", method, e)
        return None


def send(chat_id: int, text: str, parse_mode: str = "Markdown",
         reply_markup: dict | None = None) -> None:
    kwargs: dict = {"chat_id": chat_id, "text": text, "parse_mode": parse_mode}
    if reply_markup:
        kwargs["reply_markup"] = json.dumps(reply_markup)
    _tg("sendMessage", **kwargs)


def send_typing(chat_id: int) -> None:
    _tg("sendChatAction", chat_id=chat_id, action="typing")


# ---------------------------------------------------------------------------
# RaddHub catalog helpers
# ---------------------------------------------------------------------------

def _search_catalog(query: str, media_type: str | None = None, limit: int = 5) -> list[dict]:
    """Search local catalog via SQLite FTS (no auth needed for internal call)."""
    try:
        db_path = Path(__file__).parent.parent / "radd-hub" / "data" / "hub.db"
        if not db_path.exists():
            db_path = Path("/home/ubuntu/radd-hub/data/hub.db")
        if not db_path.exists():
            return []
        import sqlite3
        con = sqlite3.connect(str(db_path))
        con.row_factory = sqlite3.Row
        where = "is_published=1"
        params: list = []
        if media_type:
            where += " AND media_type=?"
            params.append(media_type)
        # Try FTS first
        try:
            fts_sql = (
                "SELECT t.id,t.title,t.year,t.media_type,t.rating,t.plot,t.genres "
                "FROM titles t "
                "JOIN titles_fts fts ON t.id=fts.rowid "
                f"WHERE fts.title MATCH ? AND {where} "
                "ORDER BY bm25(titles_fts) LIMIT ?"
            )
            rows = con.execute(fts_sql, [f'"{query}"'] + params + [limit]).fetchall()
        except Exception:
            rows = []
        if not rows:
            like_sql = (
                f"SELECT id,title,year,media_type,rating,plot,genres FROM titles "
                f"WHERE title LIKE ? AND {where} ORDER BY rating DESC LIMIT ?"
            )
            rows = con.execute(like_sql, [f"%{query}%"] + params + [limit]).fetchall()
        con.close()
        return [dict(r) for r in rows]
    except Exception as e:
        log.error("catalog search error: %s", e)
        return []


def _get_trending(limit: int = 5) -> list[dict]:
    """Return top-rated published titles."""
    try:
        db_path = Path(__file__).parent.parent / "radd-hub" / "data" / "hub.db"
        if not db_path.exists():
            db_path = Path("/home/ubuntu/radd-hub/data/hub.db")
        if not db_path.exists():
            return []
        import sqlite3
        con = sqlite3.connect(str(db_path))
        con.row_factory = sqlite3.Row
        rows = con.execute(
            "SELECT id,title,year,media_type,rating FROM titles "
            "WHERE is_published=1 AND rating IS NOT NULL "
            "ORDER BY rating DESC LIMIT ?", (limit,)
        ).fetchall()
        con.close()
        return [dict(r) for r in rows]
    except Exception as e:
        log.error("trending error: %s", e)
        return []


# ---------------------------------------------------------------------------
# Message formatters
# ---------------------------------------------------------------------------

MEDIA_EMOJI = {
    "movie": "🎬", "tv": "📺", "anime": "⛩️", "drama": "🎭",
}

def _fmt_title(t: dict) -> str:
    em = MEDIA_EMOJI.get(t.get("media_type", ""), "🎞️")
    rating = f"⭐ {t['rating']:.1f}" if t.get("rating") else ""
    year = f"({t['year']})" if t.get("year") else ""
    genres = ""
    try:
        g = json.loads(t.get("genres") or "[]")
        if g:
            genres = " · " + ", ".join(g[:3])
    except Exception:
        pass
    plot = (t.get("plot") or "")[:200]
    if plot and len(plot) == 200:
        plot += "…"
    lines = [f"{em} *{t['title']}* {year}  {rating}"]
    if genres:
        lines.append(genres)
    if plot:
        lines.append(f"\n_{plot}_")
    return "\n".join(lines)


WELCOME = (
    "👋 *Welcome to RaddFlix Bot!*\n\n"
    "Pakistan ka entertainment, data\\-free 🇵🇰\n\n"
    "I can help you search movies & shows from the RaddFlix library\\.\n\n"
    "*Commands:*\n"
    "/search \\<query\\> — search the catalog\n"
    "/movie \\<query\\> — search movies only\n"
    "/show \\<query\\> — search shows/series\n"
    "/trending — top rated titles\n"
    "/help — show this menu"
)

HELP_TEXT = (
    "📋 *RaddFlix Bot Commands*\n\n"
    "/search *Inception* — search any title\n"
    "/movie *Avengers* — search movies only\n"
    "/show *Breaking Bad* — search series only\n"
    "/trending — see top\\-rated titles\n"
    "/status — check if bot is running\n"
    "/help — show this menu\n\n"
    "_Watch on the RaddFlix app — zero\\-rated for Jazz SIM users\\!_"
)


# ---------------------------------------------------------------------------
# Command handlers
# ---------------------------------------------------------------------------

def handle_start(chat_id: int, _text: str) -> None:
    send(chat_id, WELCOME, parse_mode="MarkdownV2")


def handle_help(chat_id: int, _text: str) -> None:
    send(chat_id, HELP_TEXT, parse_mode="MarkdownV2")


def handle_status(chat_id: int, _text: str) -> None:
    send(chat_id, "✅ RaddFlix Bot is running\\!", parse_mode="MarkdownV2")


def handle_search(chat_id: int, text: str, media_type: str | None = None) -> None:
    query = text.strip()
    if not query:
        send(chat_id, "Please provide a search term\\.\nExample: `/search Inception`",
             parse_mode="MarkdownV2")
        return
    send_typing(chat_id)
    results = _search_catalog(query, media_type=media_type)
    if not results:
        send(chat_id,
             f"😕 No results found for *{query}*\\.\nTry a different search term\\.",
             parse_mode="MarkdownV2")
        return
    lines = [f"🔍 *Results for '{query}':*\n"]
    for i, t in enumerate(results, 1):
        lines.append(f"{i}\\. {_fmt_title(t)}")
        lines.append("")
    send(chat_id, "\n".join(lines), parse_mode="MarkdownV2")


def handle_trending(chat_id: int, _text: str) -> None:
    send_typing(chat_id)
    results = _get_trending()
    if not results:
        send(chat_id, "Could not load trending titles\\.", parse_mode="MarkdownV2")
        return
    lines = ["🔥 *Top Rated on RaddFlix:*\n"]
    for i, t in enumerate(results, 1):
        em = MEDIA_EMOJI.get(t.get("media_type", ""), "🎞️")
        rating = f"⭐ {t['rating']:.1f}" if t.get("rating") else ""
        year = f"({t['year']})" if t.get("year") else ""
        lines.append(f"{i}\\. {em} *{t['title']}* {year} {rating}")
    send(chat_id, "\n".join(lines), parse_mode="MarkdownV2")


COMMANDS: dict[str, tuple] = {
    "/start":    (handle_start,    None),
    "/help":     (handle_help,     None),
    "/status":   (handle_status,   None),
    "/search":   (handle_search,   None),
    "/movie":    (handle_search,   "movie"),
    "/movies":   (handle_search,   "movie"),
    "/show":     (handle_search,   "tv"),
    "/shows":    (handle_search,   "tv"),
    "/series":   (handle_search,   "tv"),
    "/anime":    (handle_search,   "anime"),
    "/trending": (handle_trending, None),
    "/top":      (handle_trending, None),
}


# ---------------------------------------------------------------------------
# Update dispatcher
# ---------------------------------------------------------------------------

def dispatch(update: dict) -> None:
    """Route a Telegram update to the correct handler."""
    msg = update.get("message") or update.get("edited_message")
    if not msg:
        return
    chat_id: int = msg["chat"]["id"]
    text: str = (msg.get("text") or "").strip()
    if not text.startswith("/"):
        return

    parts = text.split(maxsplit=1)
    raw_cmd = parts[0].lower().split("@")[0]  # strip @BotName suffix
    arg = parts[1] if len(parts) > 1 else ""

    entry = COMMANDS.get(raw_cmd)
    if entry:
        handler, extra_arg = entry
        if extra_arg is not None:
            handler(chat_id, arg, extra_arg)  # type: ignore[call-arg]
        else:
            handler(chat_id, arg)
    else:
        send(chat_id, "Unknown command\\. Use /help to see available commands\\.",
             parse_mode="MarkdownV2")


# ---------------------------------------------------------------------------
# Main polling loop
# ---------------------------------------------------------------------------

def main() -> None:
    global BOT_TOKEN, TG_API, _OFFSET

    # Try loading token from hub if not set in env
    if not BOT_TOKEN:
        BOT_TOKEN = _load_token_from_hub()
    if not BOT_TOKEN:
        log.error("TELEGRAM_BOT_TOKEN not set. Add it via RaddHub admin → Settings → Telegram bot.")
        sys.exit(1)

    TG_API = f"https://api.telegram.org/bot{BOT_TOKEN}"

    # Verify token
    me = _tg("getMe")
    if not me:
        log.error("Invalid bot token or Telegram unreachable.")
        sys.exit(1)
    log.info("RaddFlix Telegram Bot started: @%s (%s)", me.get("username"), me.get("first_name"))

    # Main loop
    while True:
        try:
            updates = _tg("getUpdates", offset=_OFFSET, timeout=_POLL_TIMEOUT, limit=50)
            if not updates:
                continue
            for update in updates:
                uid = update.get("update_id", 0)
                if uid >= _OFFSET:
                    _OFFSET = uid + 1
                try:
                    dispatch(update)
                except Exception as e:
                    log.error("dispatch error for update %s: %s", uid, e)
        except KeyboardInterrupt:
            log.info("Shutting down.")
            break
        except Exception as e:
            log.error("polling error: %s", e)
            time.sleep(5)


if __name__ == "__main__":
    main()
