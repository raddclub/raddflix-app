"""Database Management — CRUD, raw SQL, and data grid."""
from __future__ import annotations
import json
import time
import sqlite3
import csv
import io
from flask import Blueprint, render_template, request, jsonify, Response, abort
from .. import db, auth, config

bp = Blueprint("db_mgmt", __name__)

# All tables exposed in DB Studio, grouped by category
TABLE_GROUPS = {
    "Library":       ["titles", "files", "accounts"],
    "Vault":         ["keys"],
    "Users":         ["users", "app_users", "app_refresh_tokens"],
    "Payments":      ["payment_methods", "received_sms_payments", "tid_payments"],
    "Subscriptions": ["plans", "user_subscriptions", "app_subscriptions"],
    "Analytics":     ["watch_history", "user_usage", "rate_limit_log"],
    "System":        ["settings", "scan_log", "mirror_log", "queue"],
    "App":           ["notifications", "stream_links", "recommendation_cache", "media_index"],
}

ALL_TABLES = {t for tables in TABLE_GROUPS.values() for t in tables}


def _table_exists(c: sqlite3.Connection, name: str) -> bool:
    r = c.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?", (name,)
    ).fetchone()
    return bool(r)


def _safe_row(row) -> dict:
    """Convert a sqlite3.Row or dict to JSON-serializable dict.
    Bytes (BLOB) columns are rendered as '[BINARY Nb]' so JSON doesn't crash."""
    result = {}
    d = dict(row)
    for k, v in d.items():
        if isinstance(v, bytes):
            try:
                result[k] = v.decode("utf-8")
            except UnicodeDecodeError:
                result[k] = f"[BINARY {len(v)}B]"
        else:
            result[k] = v
    return result


@bp.route("/")
@auth.login_required
def page():
    return render_template("db_mgmt.html", active="db_mgmt")


@bp.route("/api/tables")
@auth.login_required
def list_tables():
    """Return all tables grouped by category. Skip tables that don't exist yet."""
    result = {}
    with db.conn() as c:
        for group, tables in TABLE_GROUPS.items():
            existing = [t for t in tables if _table_exists(c, t)]
            if existing:
                result[group] = existing
    return jsonify({"ok": True, "groups": result})


@bp.route("/api/table/<name>")
@auth.login_required
def get_table_data(name):
    """Fetch rows from a table with pagination, search and sorting."""
    if name not in ALL_TABLES:
        abort(403)

    limit  = min(int(request.args.get("limit", 50)), 500)
    offset = int(request.args.get("offset", 0))
    q      = request.args.get("q", "").strip()
    sort   = request.args.get("sort", "id")
    order  = "DESC" if request.args.get("order", "desc").lower() == "desc" else "ASC"

    try:
        with db.conn() as c:
            if not _table_exists(c, name):
                return jsonify({"ok": False, "error": f"Table '{name}' does not exist"}), 404

            cursor  = c.execute(f"PRAGMA table_info({name})")
            columns = [{"name": r["name"], "type": r["type"], "pk": bool(r["pk"])}
                       for r in cursor.fetchall()]
            col_names = {col["name"] for col in columns}

            where, params = "", []
            if q:
                # FTS5 for titles
                if name == "titles" and _table_exists(c, "catalog_fts"):
                    try:
                        fts_rows = c.execute(
                            "SELECT rowid FROM catalog_fts WHERE catalog_fts MATCH ? LIMIT 500",
                            (f"{q}*",)
                        ).fetchall()
                        ids = ",".join(str(r[0]) for r in fts_rows) if fts_rows else "0"
                        where = f" WHERE id IN ({ids})"
                    except Exception:
                        pass

                if not where:
                    text_cols = [col["name"] for col in columns
                                 if col["type"].upper() in ("TEXT", "VARCHAR")][:10]
                    if text_cols:
                        where  = " WHERE " + " OR ".join(f"{c2} LIKE ?" for c2 in text_cols)
                        params = [f"%{q}%"] * len(text_cols)

            safe_sort = sort if sort in col_names else "id"
            total = c.execute(f"SELECT COUNT(*) FROM {name}{where}", params).fetchone()[0]
            rows  = c.execute(
                f"SELECT * FROM {name}{where} ORDER BY {safe_sort} {order} LIMIT ? OFFSET ?",
                params + [limit, offset]
            ).fetchall()

            return jsonify({
                "ok": True, "columns": columns,
                "rows": [_safe_row(r) for r in rows],
                "total": total, "limit": limit, "offset": offset,
            })
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/table/<name>/row", methods=["POST"])
@auth.login_required
def create_row(name):
    if name not in ALL_TABLES:
        abort(403)
    data = request.get_json(force=True, silent=True) or {}
    if not data:
        return jsonify({"ok": False, "error": "No data provided"}), 400
    try:
        cols = list(data.keys())
        sql  = (f"INSERT INTO {name} ({', '.join(cols)}) "
                f"VALUES ({', '.join(['?'] * len(cols))})")
        with db.conn() as c:
            cur = c.execute(sql, list(data.values()))
            return jsonify({"ok": True, "lastrowid": cur.lastrowid})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/table/<name>/row", methods=["PUT"])
@auth.login_required
def update_row(name):
    if name not in ALL_TABLES:
        abort(403)
    data    = request.get_json(force=True, silent=True) or {}
    pks     = data.get("_pks", {})
    updates = data.get("_updates", {})
    if not pks or not updates:
        return jsonify({"ok": False, "error": "Missing primary keys or updates"}), 400
    try:
        set_clause   = ", ".join(f"{k} = ?" for k in updates)
        where_clause = " AND ".join(f"{k} = ?" for k in pks)
        sql = f"UPDATE {name} SET {set_clause} WHERE {where_clause}"
        with db.conn() as c:
            c.execute(sql, list(updates.values()) + list(pks.values()))
            return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/table/<name>/row", methods=["DELETE"])
@auth.login_required
def delete_row(name):
    if name not in ALL_TABLES:
        abort(403)
    data = request.get_json(force=True, silent=True) or {}
    if not data:
        return jsonify({"ok": False, "error": "No primary keys provided"}), 400
    try:
        where_clause = " AND ".join(f"{k} = ?" for k in data)
        sql = f"DELETE FROM {name} WHERE {where_clause}"
        with db.conn() as c:
            c.execute(sql, list(data.values()))
            return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/sql", methods=["POST"])
@auth.login_required
def execute_sql():
    data = request.get_json(force=True, silent=True) or {}
    sql  = data.get("sql", "").strip()
    if not sql:
        return jsonify({"ok": False, "error": "No SQL provided"}), 400
    try:
        with db.conn() as c:
            cur = c.execute(sql)
            if cur.description:
                columns = [d[0] for d in cur.description]
                rows    = [_safe_row(dict(zip(columns, r))) for r in cur.fetchall()]
                return jsonify({"ok": True, "columns": columns, "rows": rows, "type": "select"})
            else:
                return jsonify({"ok": True, "changes": c.total_changes, "type": "exec"})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/export/<name>")
@auth.login_required
def export_table(name):
    """Export a table as CSV or JSON. Strict whitelist enforced."""
    if name not in ALL_TABLES:
        abort(403)
    fmt = request.args.get("format", "csv").lower()
    try:
        with db.conn() as c:
            if not _table_exists(c, name):
                return "Table not found", 404
            rows = c.execute(f"SELECT * FROM {name}").fetchall()
            if not rows:
                return "Table is empty", 200
            data = [_safe_row(r) for r in rows]
            if fmt == "json":
                return Response(
                    json.dumps(data, indent=2),
                    mimetype="application/json",
                    headers={"Content-Disposition": f"attachment; filename={name}.json"},
                )
            output = io.StringIO()
            writer = csv.DictWriter(output, fieldnames=data[0].keys())
            writer.writeheader()
            writer.writerows(data)
            return Response(
                output.getvalue(), mimetype="text/csv",
                headers={"Content-Disposition": f"attachment; filename={name}.csv"},
            )
    except Exception as e:
        return str(e), 500


@bp.route("/api/stats")
@auth.login_required
def db_stats():
    try:
        db_path    = config.DB_PATH
        size_bytes = db_path.stat().st_size if db_path.exists() else 0
        counts: dict = {}
        with db.conn() as c:
            tables_count = c.execute(
                "SELECT COUNT(*) FROM sqlite_master "
                "WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '%_fts%'"
            ).fetchone()[0]
            for t in ["titles", "files", "app_users", "tid_payments", "watch_history",
                      "plans", "payment_methods", "received_sms_payments"]:
                try:
                    counts[t] = c.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
                except Exception:
                    counts[t] = 0
        return jsonify({"ok": True, "size_bytes": size_bytes,
                        "tables_count": tables_count, "row_counts": counts,
                        "ts": int(time.time())})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500
