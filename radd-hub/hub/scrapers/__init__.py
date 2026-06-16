"""Movie download link scrapers for RaddHub v3.0.

Each scraper module exposes:
    search(title, year=None) -> list[dict]
    get_download_links(page_url) -> list[dict]

A dict from search() has: {title, year, url, site, quality, thumb}
A dict from get_download_links() has: {label, url, server, quality, size}
"""
from __future__ import annotations
from .multi import search_all, get_links

__all__ = ["search_all", "get_links"]
