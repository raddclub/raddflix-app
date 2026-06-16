"""Vendored modules from v2.0 - kept byte-for-byte to preserve all logic.

A sys.path entry is injected so the internal cross-imports inside these
files (e.g. ``import schema``, ``import enricher``) resolve to siblings
in this very folder rather than escaping into the wider project.
"""
import os, sys
_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
