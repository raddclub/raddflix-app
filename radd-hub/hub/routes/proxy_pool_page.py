"""Dedicated SAPI Proxy Pool admin page — /proxy-pool/"""
from flask import Blueprint, render_template
from .. import auth as _auth

bp = Blueprint("proxy_pool_page", __name__)


@bp.route("/")
@_auth.login_required
def proxy_pool_index():
    return render_template("proxy_pool_page.html", active="proxy_pool")
