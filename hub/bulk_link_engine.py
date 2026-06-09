"""bulk_link_engine.py — DISABLED.
Server-side stream link pre-generation removed.
Stream links are now generated exclusively on the Flutter client side.
"""
import threading

def loop(stop_event: threading.Event) -> None:
    """No-op stub — bulk link engine disabled."""
    stop_event.wait()
