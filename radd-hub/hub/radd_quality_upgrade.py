"""Quality auto-upgrade scanner (F13).

For every entry the user has subscribed to (table `quality_upgrade_subscriptions`)
this scanner re-runs the scraper looking for a higher quality than what's on disk.

v3.0 improvement over the stub: _notify now inserts a real queue job AND writes
a bot_status_index notification (the same mechanism v2.0 used) so WhatsApp/Telegram
bots actually alert users about the available upgrade.
"""
from __future__ import annotations
import time
import uuid
import logging
from . import db

log = logging.getLogger("hub.quality")

QUALITY_RANK = {"360p": 0, "480p": 1, "720p": 2, "1080p": 3, "1440p": 4, "2160p": 5}


def _detect_q(text: str) -> str | None:
    t = (text or "").lower()
    for q in ("2160p", "1440p", "1080p", "720p", "480p", "360p"):
        if q in t:
            return q
    if "4k" in t or "uhd" in t:
        return "2160p"
    if "fhd" in t:
        return "1080p"
    if " hd" in t or "hd " in t:
        return "720p"
    return None


def list_subscriptions() -> list[dict]:
    with db.conn() as c:
        return [dict(r) for r in c.execute(
            "SELECT user_jid, fingerprint, current_q, target_q, notified_at "
            "FROM quality_upgrade_subscriptions"
        ).fetchall()]


def subscribe(user_jid: str, fingerprint: str, current_q: str, target_q: str) -> bool:
    with db.conn() as c:
        c.execute(
            "INSERT OR REPLACE INTO quality_upgrade_subscriptions "
            "(user_jid, fingerprint, current_q, target_q) VALUES (?,?,?,?)",
            (user_jid, fingerprint, current_q, target_q),
        )
    return True


def unsubscribe(user_jid: str, fingerprint: str) -> bool:
    with db.conn() as c:
        c.execute(
            "DELETE FROM quality_upgrade_subscriptions WHERE user_jid=? AND fingerprint=?",
            (user_jid, fingerprint),
        )
    return True


def _notify(user_jid: str, fingerprint: str, found_q: str, link: str) -> None:
    """Notify the user that a higher quality is available.

    1. Update the subscription's notified_at timestamp.
    2. Enqueue a quality upgrade download job in the download queue.
    3. Upsert a bot_status_index row so WhatsApp/Telegram bots alert the user.
       Uses the v3 schema defined in db.py DDL (fingerprint PK, not an id PK).
    """
    now = int(time.time())

    # 1. Update subscription timestamp
    with db.conn() as c:
        c.execute(
            "UPDATE quality_upgrade_subscriptions SET notified_at=? "
            "WHERE user_jid=? AND fingerprint=?",
            (now, user_jid, fingerprint),
        )

    # 2. Enqueue a download job for the upgraded quality
    if link:
        try:
            with db.conn() as c:
                row = c.execute(
                    "SELECT filename, "
                    "(SELECT title FROM titles WHERE id=files.title_id) AS title "
                    "FROM files WHERE fingerprint=?",
                    (fingerprint,),
                ).fetchone()
            movie_label = (row["title"] or row["filename"] or fingerprint) if row else fingerprint
            job_id = uuid.uuid4().hex[:10]
            with db.conn() as c:
                c.execute(
                    "INSERT INTO queue "
                    "(job_id,movie,site,status,message,url,created_at,updated_at) "
                    "VALUES(?,?,?,?,?,?,?,?)",
                    (job_id, f"[UPGRADE {found_q}] {movie_label}", "auto",
                     "queued", f"Quality upgrade to {found_q}", link, now, now),
                )
            log.info("Quality upgrade job %s queued for %s (%s)", job_id, fingerprint, found_q)
        except Exception as e:
            log.warning("Failed to enqueue quality upgrade job: %s", e)

    # 3. Upsert bot_status_index (v3 schema: fingerprint PK, user_jid, title, state, detail)
    if user_jid:
        try:
            with db.conn() as c:
                row = c.execute(
                    "SELECT (SELECT title FROM titles WHERE id=files.title_id) AS title "
                    "FROM files WHERE fingerprint=? LIMIT 1",
                    (fingerprint,),
                ).fetchone()
            movie_title = (row["title"] if row else None) or fingerprint
            notify_fp = f"upgrade:{fingerprint}:{now}"
            with db.conn() as c:
                c.execute(
                    "INSERT OR REPLACE INTO bot_status_index "
                    "(fingerprint,user_jid,title,state,progress_pct,detail,updated_at,created_at) "
                    "VALUES(?,?,?,?,?,?,?,?)",
                    (
                        notify_fp, user_jid, movie_title,
                        "quality_upgrade", 100.0,
                        f"{found_q} upgrade available: {link[:200] if link else ''}",
                        now, now,
                    ),
                )
            log.info("Bot notification queued for %s: %s upgrade", user_jid, found_q)
        except Exception as e:
            log.warning("Failed to write bot_status_index notification: %s", e)

    log.info("Quality upgrade available for %s → %s [user=%s]", fingerprint, found_q, user_jid)


def scan_once(scraper_cb=None) -> dict:
    """Run one pass over all subscriptions.

    scraper_cb(fingerprint, target_q) → (found_q, link) or (None, None)
    """
    checked  = 0
    notified = 0
    errors   = 0
    subs = list_subscriptions()

    for sub in subs:
        checked += 1
        target = (sub.get("target_q") or "").lower()
        cur    = (sub.get("current_q") or "").lower()

        if not target:
            continue

        # Avoid spamming the same user more than once every 24 h
        last_notified = sub.get("notified_at") or 0
        if last_notified and (time.time() - last_notified) < 86400:
            continue

        if scraper_cb is None:
            # No scraper available — skip silently
            continue

        try:
            found_q, link = scraper_cb(sub["fingerprint"], target)
            if not found_q:
                continue
            if QUALITY_RANK.get(found_q, -1) > QUALITY_RANK.get(cur, -1):
                _notify(sub["user_jid"], sub["fingerprint"], found_q, link or "")
                notified += 1
        except Exception as e:
            log.warning("upgrade check failed for %s: %s", sub.get("fingerprint"), e)
            errors += 1
            continue

    return {
        "checked":  checked,
        "notified": notified,
        "errors":   errors,
        "ts":       int(time.time()),
    }
