from __future__ import annotations
import logging
import urllib.parse
from typing import Optional
log = logging.getLogger("radd_flix.share")
CLOUD_BASE       = "https://cloud.jazzdrive.com.pk"
PUBLIC_URL_TMPL  = CLOUD_BASE + "/f/{share_key}"
EP_SAVE_FOLDER   = "/sapi/link/folder?action=save"
EP_LIST_LINKS    = "/sapi/link?action=get"
EP_DELETE_LINK   = "/sapi/link?action=delete"
def _vk(tokens: dict) -> str:
    return tokens.get("validation_key") or tokens.get("validationkey") or ""
def _jsid(tokens: dict) -> str:
    return tokens.get("jsessionid") or tokens.get("session") or ""
def _auth_qs(tokens: dict) -> str:
    vk = _vk(tokens)
    return f"validationkey={urllib.parse.quote(vk, safe='')}" if vk else ""
def _auth_headers(tokens: dict) -> dict:
    from .. import jazzdrive
    return jazzdrive._auth_headers(tokens)
def _build_url(path: str, tokens: dict) -> str:
    sep = "&" if "?" in path else "?"
    return f"{CLOUD_BASE}{path}{sep}{_auth_qs(tokens)}"
def _public_url(share_key: str) -> str:
    return PUBLIC_URL_TMPL.format(share_key=share_key)
def _normalize_link_record(raw: dict) -> dict:
    if not isinstance(raw, dict):
        return {}
    d = raw.get("data") if isinstance(raw.get("data"), dict) else raw
    share_key       = d.get("shareKey") or d.get("sharedKey") or ""
    url             = d.get("url") or ""
    
    if not share_key and url:
        if '/share/f/' in url:
            share_key = url.split('/share/f/')[1].split('?')[0]
        elif '/f/' in url:
            share_key = url.split('/f/')[1].split('?')[0]

    shared_label_id = d.get("sharedLabelId") or d.get("labelid") or d.get("labelId") or ""
    validation_key  = d.get("validationKey") or ""
    link_id         = str(d.get("id") or d.get("linkId") or d.get("link_id") or "")
    folder_id       = d.get("folderid") or d.get("folderId") or d.get("folder_id") or 0
    
    if not url and share_key:
        url = _public_url(share_key)
        
    return {
        "link_id":         link_id,
        "folder_id":       int(folder_id) if str(folder_id).isdigit() else folder_id,
        "share_key":       share_key,
        "share_url":       url,
        "shared_label_id": str(shared_label_id),
        "validation_key":  str(validation_key),
        "expiration_date": d.get("expirationDate"),
        "password":        bool(d.get("password")),
        "raw":             d,
    }
def create_folder_share_link(
    session,
    tokens: dict,
    folder_id: int,
    *,
    expiration_date: Optional[str] = None,
    password: Optional[str] = None,
    timeout: int = 30,
) -> dict:
    url = _build_url(EP_SAVE_FOLDER, tokens)
    # Use both folderid and folderId for broad compatibility
    body: dict = {"data": {"folderid": int(folder_id), "folderId": int(folder_id)}}
    if expiration_date:
        body["data"]["expirationDate"] = expiration_date
    if password:
        body["data"]["password"] = password
    log.info("share: creating folder link folder_id=%s", folder_id)
    r = session.post(url, json=body,
                     headers={**_auth_headers(tokens),
                              "Content-Type": "application/json;charset=UTF-8"},
                     timeout=timeout)
    r.raise_for_status()
    data = r.json() if r.content else {}
    rec  = _normalize_link_record(data)
    if not rec.get("share_key") and not rec.get("share_url"):
        log.warning("share: response missing shareKey and url: %r", data)
    elif not rec.get("share_key") and rec.get("share_url"):
        log.info("share: link ready (url only) folder_id=%s url=%s", folder_id, rec["share_url"])
    else:
        log.info("share: link ready folder_id=%s url=%s", folder_id, rec["share_url"])
    return rec
def list_share_links(
    session,
    tokens: dict,
    folder_id: Optional[int] = None,
    timeout: int = 30,
) -> list:
    url  = _build_url(EP_LIST_LINKS, tokens)
    body = {"data": {}}
    if folder_id is not None:
        body["data"]["folderid"] = int(folder_id)
        body["data"]["folderId"] = int(folder_id)
    r = session.post(url, json=body,
                     headers={**_auth_headers(tokens),
                              "Content-Type": "application/json;charset=UTF-8"},
                     timeout=timeout)
    if r.status_code == 405:                                         
        r = session.get(url, headers=_auth_headers(tokens), timeout=timeout)
    r.raise_for_status()
    data = r.json() if r.content else {}
    items = []
    if isinstance(data, dict):
        for key in ("data", "links", "items", "folders", "result"):
            v = data.get(key)
            if isinstance(v, list):
                items = v
                break
            if isinstance(v, dict):
                for sub in ("links", "items", "folders"):
                    if isinstance(v.get(sub), list):
                        items = v[sub]
                        break
                if items:
                    break
    elif isinstance(data, list):
        items = data
    out = [_normalize_link_record(it) for it in items if isinstance(it, dict)]
    if folder_id is not None:
        out = [r for r in out if int(r.get("folder_id") or 0) == int(folder_id)]
    return out
def delete_share_link(
    session,
    tokens: dict,
    link_id: str,
    timeout: int = 30,
) -> bool:
    url  = _build_url(EP_DELETE_LINK, tokens)
    body = {"data": {"id": str(link_id)}}
    r = session.post(url, json=body,
                     headers={**_auth_headers(tokens),
                              "Content-Type": "application/json;charset=UTF-8"},
                     timeout=timeout)
    r.raise_for_status()
    return True
def get_or_create_folder_share(
    session,
    tokens: dict,
    folder_id: int,
    **create_kwargs,
) -> dict:
    try:
        existing = list_share_links(session, tokens, folder_id=folder_id)
        if existing:
            log.info("share: reusing existing link folder_id=%s url=%s",
                     folder_id, existing[0].get("share_url"))
            return existing[0]
    except Exception as e:                                             
        log.debug("share: list failed (will create new): %s", e)
    return create_folder_share_link(session, tokens, folder_id, **create_kwargs)