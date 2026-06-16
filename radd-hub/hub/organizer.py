"""JazzDrive Organizer — plan, stream, and execute file clean-up operations.

Flow:
  1. plan_account()   — live crawl, returns a plan dict (synchronous)
  2. stream_plan()    — same but yields SSE events (for the auto-organizer UI)
  3. apply_operations() — execute a list of operations against JazzDrive

Folder traversal fix
--------------------
JazzDrive's `/media/folder/root?action=get` returns two tiers:
  • A "magic" folder (name="/", magic=True) that is the real storage root (id ~1719700).
    ALL content folders are children of this folder.
  • The old root-level folders (heartbeat helpers, test folders, etc.)

We now BFS both tiers to cover all content.

Video assignment fix
--------------------
`/media/video?action=get&folderId=X` always returns ALL videos, regardless of X.
The authoritative folder assignment is the `folder` field on each video item.
list_videos (scanner.py) now filters by that field.
"""
from __future__ import annotations
import logging
import os
import re
import time
from typing import Optional, Generator

from . import db
from . import jazzdrive as jd
from ._legacy import scanner as _scanner
from .media_naming import derive_media_plan, MEDIA_EXTENSIONS
# Lazy import — keeps organizer lightweight even when metadata_lookup is heavy
_metadata_lookup = None

def _get_metadata_lookup():
    global _metadata_lookup
    if _metadata_lookup is None:
        from . import metadata_lookup as _ml
        _metadata_lookup = _ml
    return _metadata_lookup

log = logging.getLogger("hub.organizer")

# Folders the organizer skips (same as scanner's SKIP_FOLDERS)
_SKIP_FOLDERS: set[str] = {
    '__pycache__', 'system', '.trash', 'thumbnails', 'heartbeat', 'logs',
    'cache', 'temp', 'tmp', 'auth', 'node_modules', '.git', '.idea',
    'radd-heartbeat', 'raddhub', 'uploads_test_archive', 'radd-test-folder',
    'radd_test_folder', 'heartbeat (1)', 'radd-heartbeat (1)',
}

# ──────────────────────────────────────────────────────────────────────────────
# Metadata enrichment helper — uses full 6-tier fallback chain
# ──────────────────────────────────────────────────────────────────────────────

def enrich_title_metadata(title: str, year: str | int | None = None,
                          media_type: str = "movie") -> dict | None:
    """Enrich a single title using the full metadata fallback chain.

    Fallback order (mirrors metadata_lookup.enrich):
      1. TMDB  2. OMDB  3. AI  4. IMDbAPI.dev  5. YouTube  6. Google KG

    Returns the enriched metadata dict, or None if all sources fail.
    Useful for callers that need fresh metadata after organising/downloading
    files without waiting for the next full scan cycle.
    """
    ml = _get_metadata_lookup()

    class _Parsed:
        pass

    p = _Parsed()
    p.title = str(title or "").strip()
    p.year  = int(year) if year and str(year).isdigit() else None
    p.media_type = media_type
    try:
        return ml.enrich(p, config={})
    except Exception as e:
        log.debug("enrich_title_metadata(%r, %r): %s", title, year, e)
        return None




# ──────────────────────────────────────────────────────────────────────────────
# Internal helpers
# ──────────────────────────────────────────────────────────────────────────────

def _should_skip_folder(name: str, extra_skip: set[str]) -> bool:
    nl = name.lower().strip()
    return nl in _SKIP_FOLDERS or nl in extra_skip


def _clean_name_for(raw_filename: str) -> str:
    try:
        plan = derive_media_plan(raw_filename)
        return plan.filename
    except Exception:
        return raw_filename


def _guess_media_type(filename: str) -> str:
    """Guess the JazzDrive media type from a filename extension.

    Used to pick the correct soft-delete endpoint:
      video   → POST /sapi/media/video?action=delete&softdelete=true
      picture → POST /sapi/media/picture?action=delete&softdelete=true
      audio   → POST /sapi/media/audio?action=delete&softdelete=true
      file    → POST /sapi/media/file?action=delete&softdelete=true  (default)
    """
    ext = (filename or "").rsplit(".", 1)[-1].lower()
    VIDEO_EXT   = {"mkv", "mp4", "avi", "mov", "wmv", "flv", "ts", "m2ts", "m4v", "webm", "rmvb"}
    PICTURE_EXT = {"jpg", "jpeg", "png", "gif", "bmp", "webp", "tiff", "svg"}
    AUDIO_EXT   = {"mp3", "wav", "ogg", "flac", "aac", "m4a", "wma"}
    if ext in VIDEO_EXT:   return "video"
    if ext in PICTURE_EXT: return "picture"
    if ext in AUDIO_EXT:   return "audio"
    return "file"


def _fmt_size(b: int) -> str:
    if b >= 1_073_741_824:
        return f"{b/1_073_741_824:.1f} GB"
    if b >= 1_048_576:
        return f"{b/1_048_576:.1f} MB"
    if b >= 1024:
        return f"{b/1024:.1f} KB"
    return f"{b} B"


def _is_media(name: str) -> bool:
    ext = os.path.splitext(name.lower())[1]
    return ext in MEDIA_EXTENSIONS


def _get_magic_root_id(account_id: int) -> Optional[int]:
    """Return the JazzDrive magic root folder ID (name='/', magic=True)."""
    try:
        data = jd.sapi_request("/media/folder/root", action="get", account_id=account_id)
        raw = (data.get("data") or {})
        folders = raw.get("folders", []) if isinstance(raw, dict) else []
        for f in folders:
            if f.get("magic") or f.get("name") == "/":
                return int(f["id"])
    except Exception:
        pass
    return None


def _build_folder_list(account_id: int, extra_skip: set[str]) -> tuple[list[dict], list[str]]:
    """BFS walk of JazzDrive; returns (all_folders, errors).

    Correctly handles both the old root-level tier AND the magic content root.
    """
    errors: list[str] = []
    queue: list[dict] = []
    pruned_ids: set[int] = set()
    visited_ids: set[int] = set()
    all_folders: list[dict] = []

    # ── Tier 1: old root-level folders ───────────────────────────────────────
    try:
        root_folders = _scanner.list_folders(None, {}, parent_id=0, account_id=account_id)
    except Exception as e:
        return [], [str(e)]

    for f in root_folders:
        if _should_skip_folder(f["name"], extra_skip):
            pruned_ids.add(f["id"])
        else:
            queue.append(f)

    # ── Tier 2: magic content root (1719700 etc.) ─────────────────────────────
    magic_root_id = _get_magic_root_id(account_id)
    if magic_root_id and magic_root_id not in {f["id"] for f in root_folders}:
        # Add a synthetic folder entry so BFS visits it
        queue.append({"id": magic_root_id, "name": "/", "parent_id": 0})

    # BFS
    while queue:
        folder = queue.pop(0)
        fid = folder["id"]
        if fid in visited_ids:
            continue
        visited_ids.add(fid)
        # Don't add the virtual "/" root itself to all_folders (no real files there
        # for most accounts), but DO expand its children.
        if folder.get("name") != "/":
            all_folders.append(folder)

        try:
            children = _scanner.list_folders(None, {}, parent_id=fid, account_id=account_id)
        except Exception:
            children = []

        for child in children:
            cid = child["id"]
            if cid in visited_ids or cid in pruned_ids:
                continue
            if _should_skip_folder(child["name"], extra_skip):
                pruned_ids.add(cid)
                continue
            queue.append(child)

    return all_folders, errors


# ──────────────────────────────────────────────────────────────────────────────
# Plan builder (synchronous)
# ──────────────────────────────────────────────────────────────────────────────

def plan_account(account_id: int, extra_skip: Optional[list] = None) -> dict:
    """Live-crawl JazzDrive and return a plan of operations."""
    skip_extra: set[str] = {s.lower().strip() for s in (extra_skip or [])}
    try:
        db_excl = db.setting("excluded_folders") or ""
        skip_extra |= {s.lower().strip() for s in db_excl.split(",") if s.strip()}
    except Exception:
        pass

    events = list(_generate_plan(account_id, skip_extra))
    ops = []
    stat: dict = {"folders_visited": 0, "files_found": 0, "error": None}
    errors = []
    for ev in events:
        if ev["type"] == "op":
            ops.append(ev["op"])
        elif ev["type"] == "stats":
            stat.update(ev)
        elif ev["type"] == "error":
            errors.append(ev.get("msg", ""))

    stat["ops"] = ops
    if errors:
        stat["error"] = "; ".join(errors)
    return stat


def _generate_plan(account_id: int, skip_extra: set[str]) -> Generator[dict, None, None]:
    """Core plan generator — yields dicts consumed by both plan_account and stream_plan.

    Folder contents are fetched in parallel (10 workers) for speed.
    Results are processed and ops are yielded in real-time as each folder completes.
    """
    from concurrent.futures import ThreadPoolExecutor, as_completed

    all_folders, folder_errors = _build_folder_list(account_id, skip_extra)
    for e in folder_errors:
        yield {"type": "error", "msg": e}

    total = len(all_folders)
    yield {"type": "stats", "folders_found": total}

    ops: list[dict] = []
    op_id = 0
    folders_visited = 0
    files_found = 0
    errors: list[str] = []

    folder_has_poster: dict[int, bool] = {}
    seen_file_ids: set[str] = set()  # deduplicate across folder calls
    dup_map: dict[str, list[dict]] = {}

    def _fetch_folder(folder: dict):
        fid   = folder["id"]
        fname = folder.get("name", "")
        try:
            items = _scanner.list_videos(None, {}, folder_id=fid, account_id=account_id)
            return fid, fname, items, None
        except Exception as exc:
            return fid, fname, [], str(exc)

    # ── Parallel fetch — 10 concurrent JazzDrive API calls ───────────────────
    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = {executor.submit(_fetch_folder, f): f for f in all_folders}

        for fut in as_completed(futures):
            fid, fname, items, err = fut.result()
            folders_visited += 1
            yield {"type": "progress", "folder": fname,
                   "visited": folders_visited, "total": total}

            if err:
                errors.append(f"folder {fname}: {err}")
                continue

            for item in items:
                raw_name  = item.get("filename") or item.get("name") or ""
                file_id   = str(item.get("remote_id") or item.get("id") or "")
                size_b    = int(item.get("size_bytes") or 0)
                is_poster = item.get("_is_poster", False)

                if not raw_name or not file_id:
                    continue
                if file_id in seen_file_ids:
                    continue
                seen_file_ids.add(file_id)

                files_found += 1
                name_lower = raw_name.lower()

                # ── Backdrop → delete ─────────────────────────────────────────
                if name_lower.startswith("backdrop"):
                    op_id += 1
                    op = {
                        "id": op_id, "type": "delete",
                        "file_id": file_id, "folder_id": str(fid), "folder_name": fname,
                        "current_name": raw_name, "new_name": None,
                        "size_str": _fmt_size(size_b), "reason": "backdrop image",
                        "auto": True,
                    }
                    ops.append(op)
                    yield {"type": "op", "op": op}
                    continue

                # ── Poster ────────────────────────────────────────────────────
                if is_poster or name_lower.startswith("poster"):
                    if folder_has_poster.get(fid):
                        op_id += 1
                        op = {
                            "id": op_id, "type": "delete",
                            "file_id": file_id, "folder_id": str(fid), "folder_name": fname,
                            "current_name": raw_name, "new_name": None,
                            "size_str": _fmt_size(size_b), "reason": "duplicate poster",
                            "auto": True,
                        }
                        ops.append(op)
                        yield {"type": "op", "op": op}
                    elif raw_name != "poster.jpg":
                        folder_has_poster[fid] = True
                        op_id += 1
                        op = {
                            "id": op_id, "type": "rename",
                            "file_id": file_id, "folder_id": str(fid), "folder_name": fname,
                            "current_name": raw_name, "new_name": "poster.jpg",
                            "size_str": _fmt_size(size_b), "reason": "standardise poster name",
                            "auto": True,
                        }
                        ops.append(op)
                        yield {"type": "op", "op": op}
                    else:
                        folder_has_poster[fid] = True
                    continue

                # ── Media file ────────────────────────────────────────────────
                if not _is_media(raw_name):
                    continue

                clean = _clean_name_for(raw_name)

                if clean != raw_name:
                    op_id += 1
                    op = {
                        "id": op_id, "type": "rename",
                        "file_id": file_id, "folder_id": str(fid), "folder_name": fname,
                        "current_name": raw_name, "new_name": clean,
                        "size_str": _fmt_size(size_b), "reason": "clean filename",
                        "auto": True,
                        "_size_bytes": size_b,
                    }
                    ops.append(op)
                    yield {"type": "op", "op": op}

                # Duplicate detection within same folder
                dup_key = f"{fid}::{clean.lower()}"
                dup_map.setdefault(dup_key, []).append({
                    "file_id": file_id, "folder_id": str(fid), "folder_name": fname,
                    "current_name": raw_name, "size_bytes": size_b,
                    "size_str": _fmt_size(size_b),
                })

    # ── Duplicate resolution ─────────────────────────────────────────────────
    for dup_key, dups in dup_map.items():
        if len(dups) < 2:
            continue
        dups.sort(key=lambda x: x["size_bytes"], reverse=True)
        for dup in dups[1:]:
            # Remove any rename op queued for this file — we're deleting it instead
            ops = [o for o in ops if not (o["file_id"] == dup["file_id"] and o["type"] == "rename")]
            op_id += 1
            op = {
                "id": op_id, "type": "delete",
                "file_id": dup["file_id"], "folder_id": dup["folder_id"],
                "folder_name": dup["folder_name"],
                "current_name": dup["current_name"], "new_name": None,
                "size_str": dup["size_str"],
                "reason": f"duplicate of {dups[0]['current_name']}",
                "auto": False,  # duplicates need manual confirmation
            }
            ops.append(op)
            yield {"type": "op", "op": op}

    yield {
        "type": "stats",
        "folders_visited": folders_visited,
        "files_found": files_found,
        "error": "; ".join(errors) if errors else None,
    }


# ──────────────────────────────────────────────────────────────────────────────
# SSE streaming plan
# ──────────────────────────────────────────────────────────────────────────────

def stream_plan(account_id: int, extra_skip: Optional[list] = None) -> Generator[str, None, None]:
    """Yield SSE-formatted strings for the live auto-organizer progress view."""
    import json
    skip_extra: set[str] = {s.lower().strip() for s in (extra_skip or [])}
    try:
        db_excl = db.setting("excluded_folders") or ""
        skip_extra |= {s.lower().strip() for s in db_excl.split(",") if s.strip()}
    except Exception:
        pass

    for ev in _generate_plan(account_id, skip_extra):
        yield f"data: {json.dumps(ev)}\n\n"

    yield "data: {\"type\": \"done\"}\n\n"


# ──────────────────────────────────────────────────────────────────────────────
# Apply operations
# ──────────────────────────────────────────────────────────────────────────────

def apply_operations(account_id: int, ops: list[dict]) -> dict:
    """Execute a list of organizer operations against JazzDrive.

    Supported op types:
      rename       — rename a file (file_id, new_name)
      delete       — move file to trash (file_id)  [alias for "trash"]
      trash        — move file to trash (file_id)
      move         — move file between folders (file_id, from_folder_id, to_folder_id)
      bulk_move    — move multiple files (file_ids[], from_folder_id, to_folder_id)
      bulk_trash   — trash multiple files (file_ids[])
      trash_folder — trash folder(s) (folder_ids[])
      rename_folder — rename a folder (folder_id, new_name, parent_id?)
      move_folder  — change folder parent (folder_id, folder_name, new_parent_id)
      restore      — restore file(s) from trash (file_ids[], media_type?)
      restore_folder — restore folder from trash (folder_id)
    """
    applied = 0
    failed  = 0
    results = []

    for op in ops:
        op_type  = op.get("type")
        op_id    = op.get("id")
        file_id  = op.get("file_id")
        r        = {}
        ok       = False

        # ── Folder-level ops (don't require file_id) ─────────────────────────
        if op_type == "trash_folder":
            raw_ids = op.get("folder_ids") or ([op["folder_id"]] if op.get("folder_id") else [])
            if not raw_ids:
                results.append({"op_id": op_id, "ok": False, "error": "missing folder_ids"})
                failed += 1
                continue
            r  = jd.trash_folder(account_id, [int(x) for x in raw_ids])
            ok = not r.get("error")
            results.append({"op_id": op_id, "ok": ok,
                             "error": str(r.get("error")) if not ok else None})
            if ok: applied += 1
            else:  failed  += 1
            continue

        if op_type == "rename_folder":
            fid = op.get("folder_id")
            new_name = (op.get("new_name") or "").strip()
            if not fid or not new_name:
                results.append({"op_id": op_id, "ok": False,
                                 "error": "rename_folder requires folder_id and new_name"})
                failed += 1
                continue
            r  = jd.rename_folder(account_id, int(fid), new_name,
                                   parent_id=op.get("parent_id"))
            ok = not r.get("error")
            results.append({"op_id": op_id, "ok": ok,
                             "error": str(r.get("error")) if not ok else None})
            if ok: applied += 1
            else:  failed  += 1
            continue

        if op_type == "move_folder":
            fid      = op.get("folder_id")
            fname    = (op.get("folder_name") or "").strip()
            new_pid  = op.get("new_parent_id")
            if not fid or not new_pid:
                results.append({"op_id": op_id, "ok": False,
                                 "error": "move_folder requires folder_id, folder_name, new_parent_id"})
                failed += 1
                continue
            r  = jd.move_folder(account_id, int(fid), fname, int(new_pid))
            ok = not r.get("error")
            results.append({"op_id": op_id, "ok": ok,
                             "error": str(r.get("error")) if not ok else None})
            if ok: applied += 1
            else:  failed  += 1
            continue

        if op_type == "restore_folder":
            fid = op.get("folder_id")
            if not fid:
                results.append({"op_id": op_id, "ok": False, "error": "missing folder_id"})
                failed += 1
                continue
            r  = jd.restore_folder(account_id, int(fid))
            ok = not r.get("error")
            results.append({"op_id": op_id, "ok": ok,
                             "error": str(r.get("error")) if not ok else None})
            if ok: applied += 1
            else:  failed  += 1
            continue

        # ── Bulk file ops (don't require single file_id) ─────────────────────
        if op_type == "bulk_trash":
            raw_ids    = op.get("file_ids") or []
            media_type = op.get("media_type") or "file"
            if not raw_ids:
                results.append({"op_id": op_id, "ok": False, "error": "missing file_ids"})
                failed += 1
                continue
            r  = jd.trash_files(account_id, [int(x) for x in raw_ids], media_type=media_type)
            ok = not r.get("error")
            results.append({"op_id": op_id, "ok": ok,
                             "error": str(r.get("error")) if not ok else None})
            if ok: applied += 1
            else:  failed  += 1
            continue

        if op_type == "bulk_move":
            raw_ids    = op.get("file_ids") or []
            from_folder = op.get("from_folder_id")
            to_folder   = op.get("to_folder_id")
            if not raw_ids or not from_folder or not to_folder:
                results.append({"op_id": op_id, "ok": False,
                                 "error": "bulk_move requires file_ids, from_folder_id, to_folder_id"})
                failed += 1
                continue
            r  = jd.move_files(account_id, [int(x) for x in raw_ids],
                                int(from_folder), int(to_folder))
            ok = not r.get("error")
            results.append({"op_id": op_id, "ok": ok,
                             "error": str(r.get("error")) if not ok else None})
            if ok: applied += 1
            else:  failed  += 1
            continue

        if op_type == "restore":
            raw_ids    = op.get("file_ids") or ([file_id] if file_id else [])
            media_type = op.get("media_type", "file")
            if not raw_ids:
                results.append({"op_id": op_id, "ok": False, "error": "missing file_ids"})
                failed += 1
                continue
            r  = jd.restore_files(account_id, [int(x) for x in raw_ids], media_type)
            ok = not r.get("error")
            results.append({"op_id": op_id, "ok": ok,
                             "error": str(r.get("error")) if not ok else None})
            if ok: applied += 1
            else:  failed  += 1
            continue

        # ── Single-file ops (require file_id) ────────────────────────────────
        if not file_id:
            results.append({"op_id": op_id, "ok": False, "error": "missing file_id"})
            failed += 1
            continue

        try:
            fid_int = int(file_id)
        except (TypeError, ValueError):
            results.append({"op_id": op_id, "ok": False,
                             "error": f"invalid file_id: {file_id}"})
            failed += 1
            continue

        if op_type == "rename":
            new_name = (op.get("new_name") or "").strip()
            if not new_name:
                results.append({"op_id": op_id, "ok": False, "error": "missing new_name"})
                failed += 1
                continue
            folder_id   = op.get("folder_id") or op.get("from_folder_id")
            media_type  = op.get("media_type") or _guess_media_type(op.get("current_name", ""))
            r  = jd.rename_video(account_id, fid_int, new_name,
                                 folder_id=int(folder_id) if folder_id else None,
                                 media_type=media_type)
            ok = not r.get("error")

        elif op_type in ("delete", "trash"):
            media_type = op.get("media_type") or _guess_media_type(op.get("current_name", ""))
            r  = jd.trash_files(account_id, [fid_int], media_type=media_type)
            ok = not r.get("error")

        elif op_type == "move":
            from_folder = op.get("from_folder_id") or op.get("folder_id")
            to_folder   = op.get("to_folder_id")
            if not from_folder or not to_folder:
                results.append({"op_id": op_id, "ok": False,
                                 "error": "move requires from_folder_id and to_folder_id"})
                failed += 1
                continue
            r  = jd.move_video(account_id, fid_int, int(from_folder), int(to_folder))
            ok = not r.get("error")

        else:
            results.append({"op_id": op_id, "ok": False,
                             "error": f"unknown op type: {op_type}"})
            failed += 1
            continue

        results.append({
            "op_id": op_id,
            "ok":    ok,
            "error": str(r.get("error")) if not ok else None,
        })
        if ok: applied += 1
        else:  failed  += 1

    return {
        "applied": applied,
        "failed":  failed,
        "total":   len(ops),
        "results": results,
    }


# ──────────────────────────────────────────────────────────────────────────────
# Auto-organize: plan + apply safe ops in one shot
# ──────────────────────────────────────────────────────────────────────────────

def auto_organize(account_id: int) -> Generator[str, None, None]:
    """Yield SSE events that plan AND apply safe ops automatically.

    Safe ops (auto=True): renames, backdrop deletes, duplicate-poster deletes.
    Unsafe ops (auto=False): duplicate media deletes — emitted but NOT applied.
    """
    import json

    skip_extra: set[str] = set()
    try:
        db_excl = db.setting("excluded_folders") or ""
        skip_extra = {s.lower().strip() for s in db_excl.split(",") if s.strip()}
    except Exception:
        pass

    safe_ops    = []
    unsafe_ops  = []
    applied     = 0
    failed      = 0

    yield f"data: {json.dumps({'type': 'phase', 'phase': 'planning'})}\n\n"

    for ev in _generate_plan(account_id, skip_extra):
        yield f"data: {json.dumps(ev)}\n\n"
        if ev["type"] == "op":
            op = ev["op"]
            if op.get("auto", True):
                safe_ops.append(op)
            else:
                unsafe_ops.append(op)

    yield f"data: {json.dumps({'type': 'phase', 'phase': 'applying', 'safe': len(safe_ops), 'unsafe': len(unsafe_ops)})}\n\n"

    # Apply safe ops one by one so we can stream progress
    for i, op in enumerate(safe_ops):
        result = apply_operations(account_id, [op])
        ok  = result["applied"] > 0
        applied += result["applied"]
        failed  += result["failed"]
        yield f"data: {json.dumps({'type': 'apply_result', 'op_id': op['id'], 'ok': ok, 'i': i+1, 'total': len(safe_ops), 'name': op['current_name'], 'op_type': op['type']})}\n\n"

    # ── Enrich any low-confidence titles that were renamed/touched ───────────────
    try:
        ml = _get_metadata_lookup()
        _enrich_count = 0
        for _t in db.list_low_confidence_titles(account_id=account_id, max_confidence=40, limit=10):
            _m = ml.enrich(_t, config={})
            if _m:
                db.update_title(_t["id"], _m)
                _enrich_count += 1
        if _enrich_count:
            _payload = {"type": "enriched", "count": _enrich_count}
            yield f"data: {json.dumps(_payload)}\n\n"
    except Exception:
        pass  # enrichment is best-effort; never block the organizer

    yield f"data: {json.dumps({'type': 'done', 'applied': applied, 'failed': failed, 'unsafe_ops': unsafe_ops})}\n\n"
