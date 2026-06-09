"""keepalive.py — DISABLED.
Heartbeat uploads to JazzDrive have been removed to prevent account suspension.
Oracle no longer writes any files to JazzDrive.
"""
import threading

def loop(stop_event: threading.Event, interval_min: int = 15) -> None:
    """No-op stub — keepalive disabled."""
    stop_event.wait()

def get_status() -> dict:
    return {"disabled": True, "reason": "keepalive removed to prevent JazzDrive account suspension"}

def trigger_heartbeat(account_id: int) -> None:
    pass
