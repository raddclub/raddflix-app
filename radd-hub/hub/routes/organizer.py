"""JazzDrive Organizer — blueprint."""
from flask import Blueprint, render_template, request, jsonify, Response, stream_with_context
from .. import db, auth, jazzdrive as jd
from .. import organizer as org_mod
from .._legacy import scanner as _scanner

bp = Blueprint("organizer", __name__)


@bp.route("/")
@auth.login_required
def page():
    accounts = db.list_accounts(role="scan")
    return render_template("organizer.html", accounts=accounts)


@bp.route("/api/plan/<int:aid>", methods=["POST"])
@auth.login_required
def plan(aid):
    data = request.get_json(force=True, silent=True) or {}
    extra_skip = data.get("extra_skip") or []
    result = org_mod.plan_account(aid, extra_skip=extra_skip)
    return jsonify(result)


@bp.route("/api/stream/<int:aid>")
@auth.login_required
def stream_plan(aid):
    """SSE endpoint — streams plan events as they're discovered."""
    return Response(
        stream_with_context(org_mod.stream_plan(aid)),
        mimetype="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@bp.route("/api/auto/<int:aid>")
@auth.login_required
def auto_organize(aid):
    """SSE endpoint — plans AND applies safe ops automatically."""
    return Response(
        stream_with_context(org_mod.auto_organize(aid)),
        mimetype="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@bp.route("/api/apply/<int:aid>", methods=["POST"])
@auth.login_required
def apply_ops(aid):
    data = request.get_json(force=True, silent=True) or {}
    ops  = data.get("ops") or []
    if not ops:
        return jsonify({"error": "no ops provided"}), 400
    result = org_mod.apply_operations(aid, ops)
    return jsonify(result)


# ── Folder listing ────────────────────────────────────────────────────────────

@bp.route("/api/folders/<int:aid>")
@auth.login_required
def list_folders(aid):
    parent_id = int(request.args.get("parent_id", 0))
    try:
        folders = _scanner.list_folders(None, {}, parent_id=parent_id, account_id=aid)
        result  = [{"id": f["id"], "name": f["name"]} for f in folders
                   if f.get("name", "").lower() not in org_mod._SKIP_FOLDERS]
        return jsonify({"folders": result})
    except Exception as e:
        return jsonify({"error": str(e), "folders": []}), 500


# ── Folder CRUD ───────────────────────────────────────────────────────────────

@bp.route("/api/folders/create/<int:aid>", methods=["POST"])
@auth.login_required
def folders_create(aid):
    """Create a new folder on JazzDrive.

    Body: {"name": "My Folder", "parent_id": 1719700}
    """
    data      = request.get_json(force=True, silent=True) or {}
    name      = (data.get("name") or "").strip()
    parent_id = data.get("parent_id") or 1719700  # magic root default
    if not name:
        return jsonify({"error": "name is required"}), 400
    r = jd.create_folder(aid, name, int(parent_id))
    if r.get("error"):
        return jsonify({"ok": False, "error": r["error"]}), 500
    folder = (r.get("data") or {}).get("folder") or {}
    return jsonify({"ok": True, "folder_id": folder.get("id"), "name": folder.get("name")})


@bp.route("/api/folders/rename/<int:aid>", methods=["POST"])
@auth.login_required
def folders_rename(aid):
    """Rename a folder on JazzDrive.

    Body: {"folder_id": 12345, "new_name": "New Name", "parent_id": 1719700}
    """
    data      = request.get_json(force=True, silent=True) or {}
    folder_id = data.get("folder_id")
    new_name  = (data.get("new_name") or "").strip()
    parent_id = data.get("parent_id")
    if not folder_id or not new_name:
        return jsonify({"error": "folder_id and new_name are required"}), 400
    r = jd.rename_folder(aid, int(folder_id), new_name, parent_id=parent_id)
    if r.get("error"):
        return jsonify({"ok": False, "error": r["error"]}), 500
    return jsonify({"ok": True})


@bp.route("/api/folders/move/<int:aid>", methods=["POST"])
@auth.login_required
def folders_move(aid):
    """Move a folder to a different parent on JazzDrive.

    Body: {"folder_id": 12345, "folder_name": "Name", "new_parent_id": 99999}
    """
    data          = request.get_json(force=True, silent=True) or {}
    folder_id     = data.get("folder_id")
    folder_name   = (data.get("folder_name") or "").strip()
    new_parent_id = data.get("new_parent_id")
    if not folder_id or not new_parent_id:
        return jsonify({"error": "folder_id and new_parent_id are required"}), 400
    r = jd.move_folder(aid, int(folder_id), folder_name, int(new_parent_id))
    if r.get("error"):
        return jsonify({"ok": False, "error": r["error"]}), 500
    return jsonify({"ok": True})


@bp.route("/api/folders/trash/<int:aid>", methods=["POST"])
@auth.login_required
def folders_trash(aid):
    """Move one or more folders to the JazzDrive trash.

    Body: {"folder_ids": [12345, 67890]}  OR  {"folder_id": 12345}
    """
    data       = request.get_json(force=True, silent=True) or {}
    folder_ids = data.get("folder_ids") or ([data["folder_id"]] if data.get("folder_id") else [])
    if not folder_ids:
        return jsonify({"error": "folder_ids is required"}), 400
    r = jd.trash_folder(aid, [int(x) for x in folder_ids])
    if r.get("error"):
        return jsonify({"ok": False, "error": r["error"]}), 500
    return jsonify({"ok": True, "trashed": len(folder_ids)})


@bp.route("/api/folders/restore/<int:aid>", methods=["POST"])
@auth.login_required
def folders_restore(aid):
    """Restore a folder from the JazzDrive trash.

    Body: {"folder_id": 12345}
    """
    data      = request.get_json(force=True, silent=True) or {}
    folder_id = data.get("folder_id")
    if not folder_id:
        return jsonify({"error": "folder_id is required"}), 400
    r = jd.restore_folder(aid, int(folder_id))
    if r.get("error"):
        return jsonify({"ok": False, "error": r["error"]}), 500
    return jsonify({"ok": True})


@bp.route("/api/folders/delete/<int:aid>", methods=["POST"])
@auth.login_required
def folders_delete_permanent(aid):
    """Permanently delete folders from JazzDrive (IRREVERSIBLE).

    Body: {"folder_ids": [12345]}
    """
    data       = request.get_json(force=True, silent=True) or {}
    folder_ids = data.get("folder_ids") or ([data["folder_id"]] if data.get("folder_id") else [])
    if not folder_ids:
        return jsonify({"error": "folder_ids is required"}), 400
    r = jd.delete_folder_permanent(aid, [int(x) for x in folder_ids])
    if r.get("error"):
        return jsonify({"ok": False, "error": r["error"]}), 500
    return jsonify({"ok": True, "deleted": len(folder_ids)})


# ── File operations ───────────────────────────────────────────────────────────

@bp.route("/api/files/trash/<int:aid>", methods=["POST"])
@auth.login_required
def files_trash(aid):
    """Move one or more files to the JazzDrive trash (soft delete).

    Body: {"file_ids": [242352111], "media_type": "video"}
          OR {"file_id": 242352111, "media_type": "file"}
    media_type: "file" (default), "video", "picture", "audio"

    Trashed files appear in GET /organizer/api/file-trash/<aid>, NOT in
    the folder-trash endpoint (/organizer/api/trash/<aid>).
    """
    data       = request.get_json(force=True, silent=True) or {}
    file_ids   = data.get("file_ids") or ([data["file_id"]] if data.get("file_id") else [])
    media_type = (data.get("media_type") or "").strip() or None
    if not file_ids:
        return jsonify({"error": "file_ids is required"}), 400
    if media_type is None:
        from ..organizer import _guess_media_type
        media_type = _guess_media_type("")  # defaults to "file"
    r = jd.trash_files(aid, [int(x) for x in file_ids], media_type=media_type)
    if r.get("error"):
        return jsonify({"ok": False, "error": r["error"]}), 500
    return jsonify({"ok": True, "trashed": len(file_ids), "media_type": media_type})


@bp.route("/api/files/restore/<int:aid>", methods=["POST"])
@auth.login_required
def files_restore(aid):
    """Restore one or more files from the JazzDrive trash.

    Body: {"file_ids": [242352111], "media_type": "video"}
    media_type: "video" (default), "file", "picture", "audio"
    """
    data       = request.get_json(force=True, silent=True) or {}
    file_ids   = data.get("file_ids") or ([data["file_id"]] if data.get("file_id") else [])
    media_type = data.get("media_type", "video")
    if not file_ids:
        return jsonify({"error": "file_ids is required"}), 400
    r = jd.restore_files(aid, [int(x) for x in file_ids], media_type)
    if r.get("error"):
        return jsonify({"ok": False, "error": r["error"]}), 500
    return jsonify({"ok": True, "restored": len(file_ids)})


@bp.route("/api/files/move/<int:aid>", methods=["POST"])
@auth.login_required
def files_move(aid):
    """Move one or more files between JazzDrive folders.

    Body: {"file_ids": [242352111], "from_folder_id": 111, "to_folder_id": 222}
    Single file also accepted as {"file_id": 242352111, ...}
    """
    data          = request.get_json(force=True, silent=True) or {}
    file_ids      = data.get("file_ids") or ([data["file_id"]] if data.get("file_id") else [])
    from_folder   = data.get("from_folder_id")
    to_folder     = data.get("to_folder_id")
    if not file_ids or not from_folder or not to_folder:
        return jsonify({"error": "file_ids, from_folder_id, and to_folder_id are required"}), 400
    r = jd.move_files(aid, [int(x) for x in file_ids], int(from_folder), int(to_folder))
    if r.get("error"):
        return jsonify({"ok": False, "error": r["error"]}), 500
    return jsonify({"ok": True, "moved": len(file_ids)})


@bp.route("/api/files/rename/<int:aid>", methods=["POST"])
@auth.login_required
def files_rename(aid):
    """Rename a single video file on JazzDrive.

    Body: {"file_id": 242352111, "new_name": "Movie (2024).mkv"}
    """
    data       = request.get_json(force=True, silent=True) or {}
    file_id    = data.get("file_id")
    new_name   = (data.get("new_name") or "").strip()
    folder_id  = data.get("folder_id")
    media_type = data.get("media_type", "video")
    if not file_id or not new_name:
        return jsonify({"error": "file_id and new_name are required"}), 400
    r = jd.rename_video(aid, int(file_id), new_name,
                        folder_id=int(folder_id) if folder_id else None,
                        media_type=media_type)
    if r.get("error"):
        return jsonify({"ok": False, "error": r["error"]}), 500
    return jsonify({"ok": True})


# ── Trash management ──────────────────────────────────────────────────────────

@bp.route("/api/trash/<int:aid>", methods=["GET"])
@auth.login_required
def trash_get(aid):
    """Fetch folder-trash contents (trashed folders only).

    NOTE: Trashed media FILES are in GET /organizer/api/file-trash/<aid>.
    This endpoint only returns folder-level trash entries.
    Query params: ?max_items=200
    """
    max_items = int(request.args.get("max_items", 200))
    r = jd.get_trash(aid, max_items=max_items)
    if r.get("error"):
        return jsonify({"ok": False, "error": r["error"]}), 500
    entries = (r.get("data") or {}).get("entries") or []
    files   = [e for e in entries if e.get("type") == "media"]
    folders = [e for e in entries if e.get("type") == "folder"]
    return jsonify({
        "ok":      True,
        "total":   len(entries),
        "files":   files,
        "folders": [{"id": f.get("id"), "name": f.get("name"),
                     "date": f.get("date")} for f in folders],
    })


@bp.route("/api/file-trash/<int:aid>", methods=["GET"])
@auth.login_required
def file_trash_get(aid):
    """Fetch trashed media files (videos, files, pictures, audio).

    Despite the underlying endpoint being /sapi/media/video/trash, it returns
    ALL trashed media types — the name is a JazzDrive API misnomer.

    Files trashed via POST /organizer/api/files/trash appear here (not in
    GET /organizer/api/trash which only shows folder trash).

    Query params: ?max_items=200
    Response: {"ok": true, "total": N, "files": [...]}
    """
    max_items = int(request.args.get("max_items", 200))
    r = jd.get_file_trash(aid, max_items=max_items)
    if r.get("error"):
        return jsonify({"ok": False, "error": r["error"]}), 500
    media = (r.get("data") or {}).get("media") or []
    return jsonify({
        "ok":    True,
        "total": len(media),
        "files": [{"id": m.get("id"), "mediatype": m.get("mediatype"),
                   "date": m.get("date"), "userid": m.get("userid")} for m in media],
    })


@bp.route("/api/trash/empty/<int:aid>", methods=["POST"])
@auth.login_required
def trash_empty(aid):
    """Permanently delete ALL items in the JazzDrive trash. IRREVERSIBLE.

    Body: {"confirm": true}  (confirmation required)
    """
    data = request.get_json(force=True, silent=True) or {}
    if not data.get("confirm"):
        return jsonify({"error": "Pass {\"confirm\": true} to empty trash"}), 400
    r = jd.empty_trash(aid)
    if r.get("error"):
        return jsonify({"ok": False, "error": r["error"]}), 500
    return jsonify({"ok": True})
