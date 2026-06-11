"""routes/delta_push.py — DISABLED.
Uploading delta.json to JazzDrive has been removed to prevent account suspension.
Catalog is now served directly from Oracle — no JazzDrive upload involved.
"""
from flask import Blueprint, jsonify
import threading

bp = Blueprint("delta_push", __name__, url_prefix="/api/catalog/delta-push")

_wake_event = threading.Event()

def delta_refresh_loop():
    """No-op stub — delta upload disabled."""
    _wake_event.wait()

@bp.route("/status")
def status():
    return jsonify({"disabled": True, "reason": "delta upload removed"})

@bp.route("/trigger", methods=["POST"])
def trigger():
    return jsonify({"disabled": True, "reason": "delta upload removed"})
