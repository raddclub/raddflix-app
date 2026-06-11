import os
from flask import Blueprint, render_template, redirect, url_for
from .. import db, auth

bp = Blueprint("home", __name__)


def _get_access_url() -> str:
    """Return the best public URL for this environment."""
    for key in ("REPLIT_DEV_DOMAIN", "REPLIT_DOMAINS"):
        val = os.environ.get(key, "").split(",")[0].strip()
        if val:
            return f"https://{val}"
    try:
        from .. import tunnel as _tunnel
        tunnel_url = _tunnel.get_url()
        if tunnel_url:
            return tunnel_url
    except Exception:
        pass
    return ""


@bp.route("/")
def home():
    if not auth.is_logged_in():
        return redirect(url_for("auth.login"))
    return render_template(
        "home.html",
        stats=db.count_library(),
        accounts=db.list_accounts(),
        recent_files=db.list_files(limit=20),
        access_url=_get_access_url(),
        csrf_token=auth.get_csrf_token(),
    )
