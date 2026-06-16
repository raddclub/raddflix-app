"""JazzDrive account scanner (replaces v2 dbgen scanner wiring).

Reuses v2.0's tested ``_legacy.scanner.scan_account`` for the JazzDrive
crawl + TMDB enrichment, but writes results into the unified v3 database
and immediately mirrors every new file to GitHub + Google Sheets.
"""
from __future__ import annotations
import threading
import time
import logging
import base64
import json
from typing import Callable, Optional
from . import db, mirror, keys
from . import _legacy  # ensure sys.path
from ._legacy import scanner as _scanner
from ._legacy import schema as _legacy_schema

log = logging.getLogger("hub.scanner")

# Android OAuth2 credentials — mirrors jazzdrive.py constants
# Decrypted from APK (AES-128-CBC, classes2.dex C4622a / classes3.dex C6516a)
ANDROID_CLIENT_ID     = "fnbroot"
ANDROID_CLIENT_SECRET = "f&rW23"


# --------------------------------------------------------------------------- #
# Account ↔ legacy DB sync                                                    #
# --------------------------------------------------------------------------- #

def _ensure_legacy_account(account_id: int) -> int:
    """Mirror our v3 account row into the legacy dbgen schema so its
    scanner can read tokens via its own get_account()."""
    acct = db.get_account(account_id)
    if not acct:
        raise RuntimeError(f"account {account_id} not found")
    _legacy_schema.ensure_setup()
    # label must be unique in the legacy schema — fall back to msisdn so
    # two accounts with blank labels never collide on INSERT.
    legacy_id = _legacy_schema.upsert_account({
        "msisdn": acct["msisdn"],
        "label":  acct.get("label") or acct["msisdn"],
        "notes":  acct.get("notes") or "",
    })
    if acct.get("validation_key") and acct.get("jsessionid"):
        _legacy_schema.update_account_session(
            legacy_id,
            acct.get("jsessionid"),
            acct.get("validation_key"),
            acct.get("node") or ""
        )
    return legacy_id


# --------------------------------------------------------------------------- #
# OTP flow                                                                    #
# --------------------------------------------------------------------------- #

_otp_sessions: dict[int, dict] = {}
_otp_lock = threading.Lock()


def send_otp(account_id: int) -> dict:
    acct = db.get_account(account_id)
    if not acct or not acct.get("msisdn"):
        return {"ok": False, "error": "no msisdn on account"}
    msisdn = acct["msisdn"]

    from .jazzdrive import resolve_proxies, is_proxy_bypass, require_wg0
    require_wg0()  # Hard-fail if wg0 down — never leak JD call via Oracle raw IP
    from . import proxy_pool as _pp

    # Build proxy chain — bypass check first.
    _chain: list = []
    _seen: set = set()
    if is_proxy_bypass():
        _chain = [None]  # direct via wg0 — wg0 exit IP is not banned by JazzDrive
    else:
        _primary = resolve_proxies()
        if _primary:
            _chain.append(_primary)
            _seen.add(_primary.get("_url", ""))
        try:
            for _p in _pp.pool.get_proxy_chain(n=8):
                _p_url = _p.get("_url", "")
                if _p_url and _p_url not in _seen:
                    _seen.add(_p_url)
                    _chain.append(_p)
        except Exception:
            pass
        if not _chain:
            log.warning("send_otp: proxy chain empty — direct connection will likely fail (MED-1011)")
            _chain = [None]

    _last_err: Exception = Exception("No proxies available")
    result = None
    for proxies in _chain:
        try:
            # Always use Android OAuth2 flow — gives months-long refresh_token sessions
            result = _scanner.jazzdrive_login(msisdn, use_android=True, proxies=proxies)
            break  # success
        except Exception as _so_e:
            _last_err = _so_e
            _err_s = str(_so_e).lower()
            _is_conn = any(x in _err_s for x in ('connection', 'timeout', 'refused', 'reset', 'socks', 'proxy', 'max retries', 'newconnection'))
            if _is_conn and proxies:
                _fail_url = proxies.get("_url") or ""
                try:
                    if _fail_url:
                        _pp.pool.mark_fail(_fail_url)
                        log.warning("send_otp: proxy %s failed (%s), trying next", _fail_url, str(_so_e)[:80])
                except Exception:
                    pass
                continue
            break  # non-connection error — don't retry with different proxy

    if result is None:
        log.error("send_otp: all proxies exhausted: %s", _last_err)
        return {"ok": False, "error": str(_last_err)}

    with _otp_lock:
        _otp_sessions[account_id] = {
            "verify_url":  result.get("verify_url"),
            "session":     result.get("session"),
            "msisdn":      msisdn,
            "use_android": True,
            "ts":          time.time(),
        }
    db.append_scan_log(account_id, "otp", "OTP sent (Android OAuth2 flow)")
    return {"ok": True, "verify_url": result.get("verify_url")}


def resend_otp(account_id: int) -> dict:
    """Trigger a resend of the OTP for a specific account."""
    with _otp_lock:
        sess = _otp_sessions.get(account_id)
    if not sess:
        return {"ok": False, "error": "no pending OTP for account"}

    from .jazzdrive import resolve_proxies, is_proxy_bypass, require_wg0
    require_wg0()  # Hard-fail if wg0 down — never leak JD call via Oracle raw IP
    from . import proxy_pool as _pp

    # Build proxy chain — bypass check first.
    _chain: list = []
    _seen: set = set()
    if is_proxy_bypass():
        _chain = [None]  # direct via wg0 — wg0 exit IP is not banned by JazzDrive
    else:
        _primary = resolve_proxies()
        if _primary:
            _chain.append(_primary)
            _seen.add(_primary.get("_url", ""))
        try:
            for _p in _pp.pool.get_proxy_chain(n=8):
                _p_url = _p.get("_url", "")
                if _p_url and _p_url not in _seen:
                    _seen.add(_p_url)
                    _chain.append(_p)
        except Exception:
            pass
        if not _chain:
            _chain = [None]

    import requests as _req
    session = sess["session"]
    verify_url = sess["verify_url"]

    _last_err: Exception = Exception("No proxies available")
    for proxies in _chain:
        try:
            if proxies:
                session.proxies = proxies
            r = session.post(
                verify_url,
                data={"resendpin": ""},
                headers={
                    "Content-Type": "application/x-www-form-urlencoded",
                    "Referer": verify_url,
                },
                timeout=(5, 30),
                proxies=proxies,
            )
            log.info("OTP resend triggered for acct %s (status=%d)", account_id, r.status_code)
            db.append_scan_log(account_id, "otp", "OTP resend requested")
            return {"ok": True, "message": "OTP resend request sent."}
        except Exception as _rr_e:
            _last_err = _rr_e
            _err_s = str(_rr_e).lower()
            _is_conn = any(x in _err_s for x in ('connection', 'timeout', 'refused', 'reset', 'socks', 'proxy', 'max retries', 'newconnection'))
            if _is_conn and proxies:
                _fail_url = proxies.get("_url") or ""
                try:
                    if _fail_url:
                        _pp.pool.mark_fail(_fail_url)
                        log.warning("resend_otp: proxy %s failed (%s), trying next", _fail_url, str(_rr_e)[:80])
                except Exception:
                    pass
                continue
            break  # non-connection error — don't retry

    log.error("resend_otp: all proxies exhausted: %s", _last_err)
    return {"ok": False, "error": str(_last_err)}


def verify_otp(account_id: int, otp: str) -> dict:
    with _otp_lock:
        sess = _otp_sessions.get(account_id)
    if not sess:
        return {"ok": False, "error": "no pending OTP for account"}
    if time.time() - sess["ts"] > 600:
        return {"ok": False, "error": "OTP session expired, request again"}

    from .jazzdrive import resolve_proxies, is_proxy_bypass, require_wg0
    require_wg0()  # Hard-fail if wg0 down — never leak JD call via Oracle raw IP
    from . import proxy_pool as _pp

    # ── Build proxy chain — bypass check first ───────────────────────────────
    _chain: list = []
    _seen: set = set()
    if is_proxy_bypass():
        _chain = [None]  # direct via wg0 — wg0 exit IP is not banned by JazzDrive
    else:
        _primary = resolve_proxies(purpose='otp')
        if _primary:
            _chain.append(_primary)
            _seen.add(_primary.get("_url", ""))
        try:
            for _p in _pp.pool.get_proxy_chain(n=8):
                _p_url = _p.get("_url", "")
                if _p_url and _p_url not in _seen:
                    _seen.add(_p_url)
                    _chain.append(_p)
        except Exception:
            pass
        if not _chain:
            log.warning("verify_otp: proxy chain empty — direct connection will likely fail (MED-1011)")
            _chain = [None]

    # ── PRE-SAPI: capture VK via keytype=otp BEFORE OTP is consumed by verify.php ──
    # verify.php (Step 3 of jazzdrive_verify_otp) consumes the OTP for OAuth2.
    # SAPI keytype=otp is an INDEPENDENT Jazz endpoint — the same OTP works on both.
    # By calling mobile_direct_verify_otp() HERE (before verify.php POST), we get VK
    # while the OTP is still fresh. The captured VK is injected after OAuth2 completes.
    # Works from any IP with the correct Android headers (User-Agent: omh android client).
    # Direct connection (None proxy) is tried last and will also succeed with the correct UA.
    _pre_vk  = ""
    _pre_jid = ""
    _sapi_pre_chain: list = []
    _sapi_pre_seen: set = set()
    try:
        from . import proxy_pool as _pp_pre
        _best_pre = _pp_pre.pool.get_best()
        if _best_pre:
            _sapi_pre_chain.append(_best_pre)
            _sapi_pre_seen.add(_best_pre.get("_url", ""))
        for _sp_pre in _pp_pre.pool.get_proxy_chain(n=3):
            _su_pre = _sp_pre.get("_url", "")
            if _su_pre and _su_pre not in _sapi_pre_seen:
                _sapi_pre_seen.add(_su_pre)
                _sapi_pre_chain.append(_sp_pre)
    except Exception:
        pass
    _sapi_pre_chain.append(None)  # direct via wg0 as last resort

    log.info("verify_otp: PRE-SAPI keytype=otp for account %s (proxies=%d)",
             account_id, len(_sapi_pre_chain))
    for _sp_pre in _sapi_pre_chain:
        try:
            _pre_tok = _scanner.mobile_direct_verify_otp(
                sess.get("msisdn", ""), otp, proxies=_sp_pre,
            )
            _pre_vk  = _pre_tok.get("validation_key") or _pre_tok.get("validationkey") or ""
            _pre_jid = _pre_tok.get("jsessionid") or ""
            if _pre_vk:
                _pre_proxy_label = (_sp_pre or {}).get("_url", "direct")[:50] if _sp_pre else "direct"
                log.info(
                    "verify_otp: PRE-SAPI VK captured BEFORE token.php "
                    "(proxy=%s vk_len=%d jid=%s)",
                    _pre_proxy_label, len(_pre_vk), bool(_pre_jid),
                )
                break
            log.debug("verify_otp: PRE-SAPI 200 but no VK (proxy=%s)",
                      (_sp_pre or {}).get("_url", "direct")[:40] if _sp_pre else "direct")
        except Exception as _pse:
            _pse_str = str(_pse)[:80]
            _pse_proxy = (_sp_pre or {}).get("_url", "direct")[:40] if _sp_pre else "direct"
            _is_conn_pse = any(x in _pse_str.lower() for x in (
                "connection", "timeout", "refused", "reset", "socks", "proxy", "retries"))
            if _is_conn_pse and _sp_pre:
                _fail_url_pse = (_sp_pre or {}).get("_url", "")
                if _fail_url_pse:
                    try:
                        _pp_pre.pool.mark_fail(_fail_url_pse)
                    except Exception:
                        pass
            log.debug("verify_otp: PRE-SAPI attempt failed (proxy=%s): %s", _pse_proxy, _pse_str)

    if _pre_vk:
        log.info("verify_otp: PRE-SAPI succeeded — VK will be merged after OAuth2 token exchange")
    else:
        log.info("verify_otp: PRE-SAPI gave no VK — proceeding with OAuth2 only")

    # ── Android OAuth2 code exchange ──────────────────────────────────────────
    # jazzdrive_verify_otp always uses client_id=fnbroot (Android credentials).
    # The server returns a refresh_token valid for ~90 days; future re-logins
    # exchange it via POST /oauth2/refresh_token.php — no OTP needed.
    # Try each proxy in the chain — mark_fail on connection errors, keep going.
    tokens = None
    _last_std_err: Exception = Exception("standard flow not attempted")
    _last_mobile_err: Exception = Exception("mobile direct not attempted")

    for _vproxy in _chain:
        try:
            tokens = _scanner.jazzdrive_verify_otp(
                sess["session"], sess["verify_url"], otp,
                msisdn=sess.get("msisdn", ""),
                proxies=_vproxy,
            )
            log.info("verify_otp: standard flow succeeded (proxy=%s)",
                     (_vproxy or {}).get("_url", "direct")[:60] if _vproxy else "direct")
            break
        except Exception as _ve:
            _last_std_err = _ve
            _err_s = str(_ve).lower()
            _is_conn = any(x in _err_s for x in (
                'connection', 'timeout', 'refused', 'reset', 'aborted',
                'remote', 'socks', 'proxy', 'max retries', 'newconnection'))
            _fail_url = (_vproxy or {}).get("_url", "")
            if _is_conn and _fail_url:
                try:
                    _pp.pool.mark_fail(_fail_url)
                    log.warning("verify_otp: proxy %s failed (%s), trying next",
                                _fail_url[:60], str(_ve)[:80])
                except Exception:
                    pass
                continue
            log.debug("verify_otp: standard flow non-conn error (proxy=%s): %s",
                      _fail_url[:40] if _fail_url else "direct", _ve)
            break

    if tokens is None:
        log.warning("verify_otp: all standard flows failed (%s). Trying mobile direct fallback...",
                    _last_std_err)
        for _vproxy in _chain[:3]:
            try:
                tokens = _scanner.mobile_direct_verify_otp(
                    sess.get("msisdn", ""),
                    otp,
                    proxies=_vproxy,
                )
                log.info("verify_otp: mobile direct fallback SUCCEEDED (proxy=%s)",
                         (_vproxy or {}).get("_url", "direct")[:60] if _vproxy else "direct")
                break
            except Exception as _me:
                _last_mobile_err = _me
                _err_s = str(_me).lower()
                _fail_url = (_vproxy or {}).get("_url", "")
                if any(x in _err_s for x in ('connection', 'timeout', 'refused', 'reset', 'aborted')) and _fail_url:
                    try:
                        _pp.pool.mark_fail(_fail_url)
                    except Exception:
                        pass
                log.debug("verify_otp: mobile direct failed (proxy=%s): %s",
                          _fail_url[:40] if _fail_url else "direct", _me)
                continue

    if tokens is None:
        log.error("verify_otp: all flows failed for %s: std=%s mobile=%s",
                  account_id, _last_std_err, _last_mobile_err)
        return {"ok": False, "error": f"Verification failed. Primary error: {_last_std_err}. Fallback error: {_last_mobile_err}"}

    # ── Handle partial result (SAPI keytype=accesstoken did not return VK) ────
    # jazzdrive_verify_otp returns _sapi_blocked=True when the SAPI silent-login
    # (keytype=accesstoken) step did not return a validationkey.
    # The OTP was accepted and we have a valid refresh_token + raw_accesstoken,
    # but the SAPI step did not produce a JSESSIONID/validationkey.
    # Save the tokens so keepalive can attempt refresh, and tell the UI to prompt
    # the user to paste cookies from their local browser session.
    if tokens.get("_sapi_blocked"):
        rt  = tokens.get("refresh_token") or ""
        rat = tokens.get("raw_accesstoken") or ""
        jid_partial = tokens.get("jsessionid") or ""  # FIX-JD-LOGIN-1: now populated
        node_partial = tokens.get("node") or ""
        log.info(
            "verify_otp: SAPI keytype=accesstoken did not return VK for account %s — saving partial tokens "
            "vk=False jid=%s rt=%s rat=%s",
            account_id, bool(jid_partial), bool(rt), bool(rat),
        )
        # FIX-JD-LOGIN-2: Persist partial tokens including JSESSIONID (fixed by FIX-1).
        # Then immediately try android_refresh_session which uses the OAuth2 refresh
        # path to get VK. Note: both platform=web and platform=Android keytype=accesstoken
        # are blocked from Oracle IP — only works from Jazz SIM network.
        _exp = int(time.time() + (86400 * 30 if rt else 3300))
        db.update_account_session(
            account_id,
            validation_key="",
            jsessionid=jid_partial,
            node=node_partial,
            expires_at=_exp,
            refresh_token=rt,
        )
        if rat:
            try:
                with db.conn() as _c:
                    _c.execute(
                        "UPDATE accounts SET raw_accesstoken=? WHERE id=?",
                        (rat, account_id)
                    )
            except Exception as _dbe:
                log.debug("verify_otp: raw_accesstoken DB write (partial): %s", _dbe)

        # Try android_refresh_session to get VK via OAuth2 refresh path.
        # This is the same path used by keepalive. NOTE: keytype=accesstoken is
        # blocked from Oracle IP — if this returns a VK it came via wg0 Jazz SIM route.
        _refresh_vk = ""
        try:
            from . import jazzdrive as _jd_mod
            log.info("verify_otp: SAPI step failed — trying android_refresh_session "
                     "for account %s to obtain VK via OAuth2 refresh path", account_id)
            _ar = _jd_mod.android_refresh_session(rt, account_id=account_id)
            if _ar.get("ok"):
                _refresh_vk = _ar.get("validation_key") or _ar.get("vk") or ""
                log.info("verify_otp: android_refresh_session OK — vk=%s jid=%s",
                         bool(_refresh_vk), bool(_ar.get("jsessionid")))
            else:
                log.info("verify_otp: android_refresh_session returned not-ok: %s",
                         _ar.get("error", "?")[:100])
        except Exception as _ar_e:
            log.warning("verify_otp: android_refresh_session attempt failed: %s", _ar_e)

        db.append_scan_log(
            account_id, "otp",
            f"OTP accepted (jid={'yes' if jid_partial else 'no'} rt={'yes' if rt else 'no'} "
            f"vk_via_refresh={'yes' if _refresh_vk else 'no'}). "
            + ("Session fully activated via OAuth2 refresh." if _refresh_vk
               else "VK missing — SAPI calls will fail until cookies are pasted.")
        )
        with _otp_lock:
            _otp_sessions.pop(account_id, None)

        if _refresh_vk:
            log.info("verify_otp: android_refresh gave VK for account %s", account_id)
            return {"ok": True, "account_id": account_id}

        # android_refresh failed — try mobile_direct_verify_otp (keytype=otp) via wg0.
        # NOTE: mobile_direct_verify_otp now uses the correct Android UA (omh android client).
        # The SAPI endpoint responds from any IP with the correct headers.
        # The real path is the activation link the user opens on their Jazz phone.
        _md3_msisdn = sess.get("msisdn", "")
        log.info("verify_otp: trying mobile_direct_verify_otp "
                 "(keytype=otp, direct via wg0) for account %s", account_id)
        try:
            _md3_tokens = _scanner.mobile_direct_verify_otp(
                _md3_msisdn, otp, proxies=None,
            )
            _md3_vk  = _md3_tokens.get("validation_key") or _md3_tokens.get("validationkey") or ""
            _md3_jid = _md3_tokens.get("jsessionid") or ""
            if _md3_vk:
                log.info("verify_otp: mobile_direct gave VK — fully activated!")
                db.update_account_session(
                    account_id,
                    validation_key=_md3_vk,
                    jsessionid=_md3_jid or jid_partial,
                    node=node_partial,
                    expires_at=_exp,
                    refresh_token=rt,
                )
                return {"ok": True, "account_id": account_id}
            log.warning("verify_otp: mobile_direct 200 but no VK")
        except Exception as _md3_e:
            log.warning("verify_otp: mobile_direct failed: %s",
                        str(_md3_e)[:100])

        msisdn_hint = sess.get("msisdn", "")
        return {
            "ok": False,
            "needs_paste_cookies": True,
            "msisdn": msisdn_hint,
            "account_id": account_id,
            "error": (
                "OTP accepted — JazzDrive confirmed your login and JSESSIONID was saved. "
                "However, the validation_key could not be obtained from this server IP. "
                "Open the activation link on your Jazz phone and paste the session JSON below."
            ),
        }

    vk  = tokens.get("validation_key") or tokens.get("validationkey") or ""
    jid = tokens.get("jsessionid") or ""
    rt  = tokens.get("refresh_token") or tokens.get("refreshtoken") or ""

    # ── Inject PRE-SAPI VK if OAuth2 flow didn't provide one ─────────────────
    # _pre_vk was captured BEFORE verify.php consumed the OTP, so it is always
    # fresh regardless of whether keytype=accesstoken SAPI step succeeded.
    if _pre_vk and not vk:
        log.info(
            "verify_otp: injecting PRE-SAPI VK into tokens (vk_len=%d jid=%s)",
            len(_pre_vk), bool(_pre_jid),
        )
        vk = _pre_vk
        tokens["validation_key"] = vk
        if _pre_jid and not jid:
            jid = _pre_jid
            tokens["jsessionid"] = jid
    elif _pre_vk and vk:
        log.info("verify_otp: PRE-SAPI VK available but OAuth2 already provided VK — using OAuth2 one")

    log.info("verify_otp: Android OAuth2 succeeded for account %s "
             "(has_vk=%s has_rt=%s pre_vk_used=%s)", account_id, bool(vk), bool(rt), bool(_pre_vk and not tokens.get("_sapi_blocked")))

    # ── If OAuth2 gave no VK, try mobile_direct_verify_otp with the same OTP ──
    # mobile_direct_verify_otp hits /sapi/login/oauth?keytype=otp directly.
    # keytype=otp works from any IP with the correct Android headers (User-Agent: omh android client).
    # FIX-OTP-UA-GATE confirmed this works from Oracle directly (commit c8490d9).
    # The same SMS OTP works for BOTH verify.php (OAuth2) AND keytype=otp (SAPI)
    # simultaneously — they are independent Jazz endpoints.
    if not vk:
        _md_msisdn = sess.get("msisdn", "")
        log.info("verify_otp: OAuth2 gave no VK — trying mobile_direct_verify_otp "
                 "(keytype=otp, direct via wg0) for account %s", account_id)
        try:
            _md_tokens = _scanner.mobile_direct_verify_otp(
                _md_msisdn, otp, proxies=None,
            )
            _md_vk  = _md_tokens.get("validation_key") or _md_tokens.get("validationkey") or ""
            _md_jid = _md_tokens.get("jsessionid") or ""
            _md_rt  = _md_tokens.get("refresh_token") or _md_tokens.get("refreshtoken") or ""
            if _md_vk:
                log.info("verify_otp: mobile_direct gave VK (len=%d) — merging. jid=%s rt=%s",
                         len(_md_vk), bool(_md_jid), bool(_md_rt))
                vk = _md_vk
                tokens["validation_key"] = vk
                if _md_jid:
                    jid = _md_jid
                    tokens["jsessionid"] = jid
                if _md_rt and not rt:
                    rt = _md_rt
            else:
                log.warning("verify_otp: mobile_direct 200 but no VK")
        except Exception as _md_e:
            log.warning("verify_otp: mobile_direct failed: %s",
                        str(_md_e)[:100])
        if not vk:
            log.warning("verify_otp: mobile_direct also gave no VK — account %s "
                        "has JSESSIONID=%s but NO VK. SAPI calls will fail.",
                        account_id, bool(jid))

    # ── Extract raw_accesstoken ────────────────────────────────────────────────
    # jazzdrive_verify_otp returns it directly as 'raw_accesstoken' (40-char hex).
    # Fall back to decoding 'access_token' if the field is base64-JSON or raw hex.
    import re as _re
    raw_at = tokens.get("raw_accesstoken") or ""
    if not raw_at:
        at_field = tokens.get("access_token") or ""
        if at_field:
            if _re.match(r'^[0-9a-f]{40}$', at_field, _re.IGNORECASE):
                # Raw 40-char hex — use directly
                raw_at = at_field
            else:
                # Base64-JSON: {"data":{"accesstoken":"...","refreshtoken":"..."}}
                try:
                    _padding = "=" * ((4 - len(at_field) % 4) % 4)
                    at_data = json.loads(
                        base64.b64decode(at_field + _padding).decode()
                    ).get("data", {})
                    raw_at = at_data.get("accesstoken", "")
                    if not rt:
                        rt = at_data.get("refreshtoken", "")
                except Exception as _dec_err:
                    log.debug("verify_otp: could not decode access_token b64: %s", _dec_err)

    log.info("verify_otp: tokens — vk=%s jid=%s raw_at=%s rt=%s",
             bool(vk), bool(jid), bool(raw_at), bool(rt))

    # Session lifetime: with a real OAuth2 refresh_token we can renew silently for
    # months — set a 30-day window so keepalive doesn't trigger false-expired warnings.
    expires_at = int(time.time() + (86400 * 30 if rt else 3300))

    db.update_account_session(
        account_id,
        validation_key=vk,
        jsessionid=jid,
        node=tokens.get("node", ""),
        expires_at=expires_at,
        refresh_token=rt,
    )
    if raw_at:
        try:
            with db.conn() as _c:
                _c.execute(
                    "UPDATE accounts SET raw_accesstoken=? WHERE id=?",
                    (raw_at, account_id)
                )
        except Exception as _dbe:
            log.debug("verify_otp: raw_accesstoken DB write: %s", _dbe)

    # ── Sync tokens to jazzdrive session file so refresh_session can use them ──
    try:
        import json as _json, pickle as _pickle, base64 as _b64
        from . import config as _cfg
        sess_file = _cfg.DATA_DIR / "jazzdrive_session.json"
        acct = db.get_account(account_id)
        msisdn = (acct or {}).get("msisdn") or sess["msisdn"]
        cookies_b64 = ""
        try:
            cookies_b64 = _b64.b64encode(_pickle.dumps(sess["session"].cookies)).decode()
        except Exception:
            pass
        sess_file.parent.mkdir(parents=True, exist_ok=True)
        sess_file.write_text(_json.dumps({
            "validationkey":   vk,
            "jsessionid":      jid,
            "refresh_token":   rt,
            "raw_accesstoken": raw_at,
            "msisdn":          msisdn,
            "created_at":      time.time(),
            "expires_at":      float(expires_at),
            "cookies":         cookies_b64,
        }, indent=2))
        log.info("verify_otp: jazzdrive session file updated for %s", msisdn)
    except Exception as _sf_err:
        log.warning("verify_otp: could not update session file: %s", _sf_err)

    db.append_scan_log(
        account_id, "otp",
        f"OTP verified via Android OAuth2 (has_refresh_token={bool(rt)}, has_raw_at={bool(raw_at)}), session stored"
    )
    with _otp_lock:
        _otp_sessions.pop(account_id, None)

    # ── Reset keepalive status immediately ────────────────────────────────────
    # After a successful OTP login the in-memory keepalive _STATUS dict still
    # holds the old consecutive_failures count and last_error string from before
    # the login. That stale state makes the UI show "Offline / Re-login required"
    # even though fresh tokens are now in the DB. Trigger an immediate background
    # heartbeat so the probe resets consecutive_failures=0 and last_error=None.
    try:
        from . import keepalive as _ka
        _ka.trigger_heartbeat(account_id)
        log.info("verify_otp: keepalive heartbeat triggered for account %s", account_id)
    except Exception as _kae:
        log.debug("verify_otp: could not trigger keepalive heartbeat: %s", _kae)

    return {"ok": True}


# --------------------------------------------------------------------------- #
# Scan + mirror                                                               #
# --------------------------------------------------------------------------- #

_active_scans: dict[int, dict] = {}
_scan_lock = threading.Lock()


def scan_progress(account_id: int) -> dict:
    with _scan_lock:
        return dict(_active_scans.get(account_id, {"running": False}))


def start_scan(account_id: int) -> dict:
    """Kick off a scan in a background thread."""
    acct = db.get_account(account_id)
    if not acct:
        return {"ok": False, "error": "Account not found."}
    # Accept raw_accesstoken (Android OAuth2 path) OR traditional validation_key+jsessionid
    has_session = (
        acct.get("raw_accesstoken")
        or acct.get("refresh_token")
        or (acct.get("validation_key") and acct.get("jsessionid"))
    )
    if not has_session:
        return {"ok": False, "error": "Not logged in (no session). Send/verify OTP first."}

    legacy_id = _ensure_legacy_account(account_id)

    # ── Sync TMDB + OMDB keys to legacy schema so enricher can use them ───────
    # BUG-APIKEY-SYNC: previously only TMDB was synced; OMDB keys were never
    # available inside _scanner.enrich_and_save(), killing the OMDB fallback.
    try:
        from . import keys as _keys
        tmdb_keys = _keys.get_all_active_values("tmdb")
        for k in tmdb_keys:
            _legacy_schema.add_api_key("tmdb", k)
        omdb_keys_for_legacy = _keys.get_all_active_values("omdb")
        for k in omdb_keys_for_legacy:
            _legacy_schema.add_api_key("omdb", k)
    except Exception as e:
        log.warning("failed to sync api keys to legacy: %s", e)

    with _scan_lock:
        active = _active_scans.get(account_id, {})
        if active.get("running") and not active.get("finished_at"):
            return {"ok": False, "error": "scan already running"}
        _active_scans[account_id] = {
            "running": True,
            "paused": False,
            "stop_requested": False,
            "started_at": int(time.time()),
            "events": [],
            "files_seen": 0,
            "files_mirrored": 0
        }

    t = threading.Thread(target=_scan_worker, args=(account_id, legacy_id), daemon=True)
    t.start()
    return {"ok": True}


def pause_scan(account_id: int) -> dict:
    with _scan_lock:
        if account_id in _active_scans:
            _active_scans[account_id]["paused"] = True
            db.append_scan_log(account_id, "info", "Scan paused by user")
            return {"ok": True}
    return {"ok": False, "error": "No active scan for this account"}


def resume_scan(account_id: int) -> dict:
    with _scan_lock:
        if account_id in _active_scans:
            _active_scans[account_id]["paused"] = False
            db.append_scan_log(account_id, "info", "Scan resumed by user")
            return {"ok": True}
    return {"ok": False, "error": "No active scan for this account"}


def stop_scan(account_id: int) -> dict:
    with _scan_lock:
        if account_id in _active_scans:
            _active_scans[account_id]["stop_requested"] = True
            db.append_scan_log(account_id, "info", "Stop requested by user...")
            return {"ok": True}
    return {"ok": False, "error": "No active scan for this account"}


def _assign_poster_share_urls(account_id: int, folder_poster_map: dict) -> None:
    """
    After a scan, set poster_share_url on any title whose JazzDrive folder
    contained a poster image (detected during scan_folder).

    folder_poster_map: {folder_id_str → {'filename': 'poster_N.jpg', 'share_url': '<folder share url>'}}

    We store the FOLDER share URL as poster_share_url.  The library route
    (/api/poster/<id>) calls jazzdrive.generate_direct_link with
    target_filename='poster.jpg', which resolves the file inside the shared
    folder.  Going forward assets.py uploads posters as 'poster.jpg' so this
    always works.  Existing files with legacy names (poster_1.jpg etc.) will
    continue to serve the TMDB fallback until the JD Organizer renames them.
    """
    if not folder_poster_map:
        return
    assigned = 0
    for folder_id_str, poster_info in folder_poster_map.items():
        share_url = poster_info.get('share_url', '')
        if not share_url:
            continue
        try:
            with db.conn() as c:
                row = c.execute(
                    "SELECT DISTINCT title_id FROM files "
                    "WHERE account_id=? AND remote_folder_id=? AND title_id IS NOT NULL LIMIT 1",
                    (account_id, folder_id_str)
                ).fetchone()
                if not row:
                    continue
                title_id = row['title_id']
                existing = c.execute(
                    "SELECT poster_share_url FROM titles WHERE id=?", (title_id,)
                ).fetchone()
                if existing and not existing['poster_share_url']:
                    c.execute(
                        "UPDATE titles SET poster_share_url=? WHERE id=?",
                        (share_url, title_id)
                    )
                    assigned += 1
        except Exception as e:
            log.debug("poster assignment failed for folder %s: %s", folder_id_str, e)
    if assigned:
        log.info("poster_share_url assigned to %d title(s) from scan", assigned)


def _auto_publish_titled_files(account_id: int) -> int:
    """Publish every title that has at least one file with a share_url.

    Called at end of scan (and on user-stop) so titles whose video file
    is on JazzDrive become visible in the Flutter app automatically.
    Publishes any title with is_published != 1 (catches NULL and 0).
    Scopes to all accounts — a title shared across accounts is published
    as soon as any account's scan finds a share_url for it.
    """
    try:
        now = int(time.time())
        with db.conn() as c:
            result = c.execute(
                "UPDATE titles SET is_published=1, updated_at=?"
                " WHERE id IN ("
                "     SELECT DISTINCT title_id FROM files"
                "     WHERE title_id IS NOT NULL"
                "       AND share_url IS NOT NULL AND share_url != '')"
                " AND (is_published IS NULL OR is_published != 1)",
                (now,)
            )
            n = result.rowcount
        if n:
            log.info(
                "auto-publish: %d title(s) published after scan for account %s",
                n, account_id
            )
        return n
    except Exception as e:
        log.warning("auto-publish failed for account %s: %s", account_id, e)
        return 0


def _scan_worker(account_id: int, legacy_id: int) -> None:
    state = _active_scans[account_id]

    def cb(evt_or_type, msg: str | None = None) -> None:
        """
        Adapter for legacy scanner callbacks.

        v3 prefers dict events: {"type": "...", "message": "..."}.
        v2 legacy emits (event, msg). Support both.
        """
        # ── Control check ──────────────────────────────────────────────────
        while state.get("paused"):
            time.sleep(1.0)
        if state.get("stop_requested"):
            raise InterruptedError("Scan stopped by user")

        if isinstance(evt_or_type, dict):
            evt = evt_or_type
        else:
            evt = {"type": str(evt_or_type), "message": msg or ""}
            
        # store small ring of events
        state.setdefault("events", []).append(evt)
        if len(state["events"]) > 200:
            state["events"] = state["events"][-200:]
            
        etype = evt.get("type", "info")
        emsg = str(evt.get("message") or etype or "")
        db.append_scan_log(account_id, etype, emsg)
        
        # ---- INCREMENTAL IMPORT ----
        # If we just finished a TMDB lookup (tmdb_ok or tmdb_miss), 
        # it means a folder's files were just written to the legacy DB.
        # Import them to v3 immediately so progress is visible/saved.
        if etype in ("tmdb_ok", "tmdb_miss", "enrich", "mirror"):
            try:
                _import_legacy_into_v3_for_account(legacy_id, account_id)
            except Exception as _ie:
                log.debug("incremental import failed: %s", _ie)

    try:
        # ── AUTO REFRESH SESSION ─────────────────────────────────────────────
        # If we have raw_accesstoken / refresh_token but no vk+jid,
        # silently grab a fresh JSESSIONID before starting the scan.
        acct_now = db.get_account(account_id)
        if acct_now and not (acct_now.get("validation_key") and acct_now.get("jsessionid")):
            if acct_now.get("raw_accesstoken") or acct_now.get("refresh_token"):
                db.append_scan_log(account_id, "info", "No active session found — auto-refreshing using stored token…")
                from .jazzdrive import refresh_session as _jd_refresh
                _refresh_result = _jd_refresh(account_id=account_id)
                if _refresh_result.get("ok"):
                    db.append_scan_log(account_id, "info", "✅ Session refreshed automatically — starting scan")
                    # Re-sync the refreshed tokens into the legacy schema
                    _ensure_legacy_account(account_id)
                else:
                    err = _refresh_result.get("error", "unknown error")
                    db.append_scan_log(account_id, "error",
                        f"❌ Session refresh failed: {err}. "
                        "Please paste validation_key + JSESSIONID from browser DevTools in the scan page.")
                    with _scan_lock:
                        state["running"] = False
                        state["finished_at"] = int(time.time())
                    return

        # ---- PRE-SCAN CLEANUP: Clear legacy files for this account to avoid ghost data ----
        try:
            with _legacy_schema._lock, _legacy_schema._get_conn() as c:
                c.execute("DELETE FROM files WHERE account_id=?", (legacy_id,))
                log.info("Cleared legacy files for account %s before scan", legacy_id)
        except Exception as _ce:
            log.debug("pre-scan cleanup error: %s", _ce)

        # ── Load user-defined excluded folders from DB setting ───────────────
        import json as _json
        try:
            _excl_raw = db.setting("scan_excluded_folders") or "[]"
            _user_excl = [x.strip() for x in _json.loads(_excl_raw) if x.strip()]
        except Exception:
            _user_excl = []
        if _user_excl:
            db.append_scan_log(account_id, "info",
                f"Excluded folders: {', '.join(_user_excl)}")

        files = _scanner.scan_account(legacy_id, progress_cb=cb, extra_skip_folders=_user_excl)
        payload = (files or {}).get("files") if isinstance(files, dict) else None
        files_list = payload if payload is not None else (files or [])
        # folder_poster_map: {folder_id_str → {'filename': ..., 'share_url': ...}}
        _folder_poster_map = (files or {}).get("folder_poster_map", {}) if isinstance(files, dict) else {}

        # ---- FILTER: Remove non-media files (noise reduction) ----
        # Uses the single source-of-truth extension sets from media_naming.
        # Keeps only true media files (video/audio/subtitle).
        # Also drops junk personal prefixes (VID-/WA-/PXL-).
        from .media_naming import MEDIA_EXTENSIONS, NON_MEDIA_EXTENSIONS, ALWAYS_SKIP_EXTENSIONS
        import os as _os

        def _is_noise(f):
            name     = (f.get("filename") or "")
            name_up  = name.upper()
            # 1. Personal WhatsApp / camera files
            if name_up.startswith("VID-") or name_up.startswith("WA-") or name_up.startswith("PXL-"):
                return True
            # 2. Extension must be a known media extension
            ext = _os.path.splitext(name)[1].lower()
            if not ext:
                return False  # no extension → let through (scanner may classify it)
            if ext in NON_MEDIA_EXTENSIONS:
                return True   # definitely not media
            if ext in ALWAYS_SKIP_EXTENSIONS:
                return True   # temp/incomplete file
            # 3. If extension is known but NOT in MEDIA_EXTENSIONS, skip it
            # (e.g. .zip .pdf .txt .jpg etc.)
            if ext not in MEDIA_EXTENSIONS:
                return True
            return False

        filtered_files = [f for f in files_list if not _is_noise(f)]
        noise_count = len(files_list) - len(filtered_files)
        if noise_count:
            cb({"type": "info", "message": f"Filtered {noise_count} non-media files (.zip/.txt/.pdf/WA-/etc.)"})
        
        cb({"type": "info", "message": f"scan complete, {len(filtered_files)} files"})

        # ---- SKIP-ALREADY-CLEAN: Load previously enriched files ----
        # Files already in the DB with confidence ≥ 60, poster, title, year, and
        # plot are skipped from TMDB/OMDB enrichment — they're already good.
        # We still import their file records (to catch new share URLs etc.)
        # but save all the enrichment API calls.
        clean_remote_ids, clean_filenames = _get_clean_file_set(account_id)
        if clean_remote_ids or clean_filenames:
            cb({"type": "info",
                "message": f"skip-clean check: {len(clean_remote_ids)} already-enriched files in DB"})

        needs_enrich = []
        already_clean = []
        for f in filtered_files:
            rid = str(f.get("remote_id") or f.get("id") or "")
            fname = (f.get("filename") or "").lower()
            if (rid and rid in clean_remote_ids) or (fname and fname in clean_filenames):
                already_clean.append(f)
            else:
                needs_enrich.append(f)

        skipped_count = len(already_clean)
        if skipped_count:
            cb({"type": "info",
                "message": f"Skipped {skipped_count} already-clean files — no re-enrichment needed"})

        # Enrich only the new/dirty files
        titles_done = _scanner.enrich_and_save(needs_enrich, legacy_id, progress_cb=cb) if needs_enrich else 0
        if needs_enrich:
            cb({"type": "info", "message": f"enriched {titles_done} new titles"})
        state["files_seen"] = len(filtered_files)
        state["files_skipped_clean"] = skipped_count

        # ---- pull latest legacy data into v3 schema, then mirror -----
        _import_legacy_into_v3_for_account(legacy_id, account_id)

        # ---- assign poster_share_url to titles from scan-discovered poster files ----
        if _folder_poster_map:
            _assign_poster_share_urls(account_id, _folder_poster_map)

        mirrored = _mirror_unsynced_for_account(account_id)
        state["files_mirrored"] = mirrored
        cb({"type": "mirror", "message": f"pushed {mirrored} files to GitHub + Sheets"})

        # ---- enrich low-confidence titles with TMDB/OMDB metadata -----
        try:
            enriched = _enrich_low_confidence_titles(account_id, progress_cb=cb)
            if enriched:
                cb({"type": "enrich", "message": f"metadata enriched {enriched} titles"})
        except Exception as _ee:
            log.debug("post-scan enrichment error: %s", _ee)

        # -- auto-publish titles that now have a linked file with share_url --
        try:
            _pub = _auto_publish_titled_files(account_id)
            if _pub:
                cb({"type": "publish",
                    "message": "auto-published " + str(_pub) + " title(s)"})
        except Exception as _ape:
            log.debug("auto-publish step error: %s", _ape)

        db.touch_account_scan(account_id)
    except InterruptedError as ie:
        log.info("Scan for account %s interrupted: %s", account_id, ie)
        # Final attempt to import any remaining enriched data before stopping
        try:
            saved = _import_legacy_into_v3_for_account(legacy_id, account_id)
            _auto_publish_titled_files(account_id)
            cb({"type": "info", "message": f"Scan stopped by user. {saved} files were saved to database."})
        except Exception:
            cb({"type": "info", "message": "Scan stopped. Data saved up to last folder."})
    except Exception as e:
        log.exception("scan failed")
        cb({"type": "error", "message": str(e)})
    finally:
        state["running"] = False
        state["paused"] = False
        state["stop_requested"] = False
        state["finished_at"] = int(time.time())


def _import_legacy_into_v3_for_account(legacy_id: int, v3_account_id: int) -> int:
    """Copy newly-scanned titles+files from legacy schema into v3 db."""
    n = 0
    title_map: dict[int, int] = {}
    # Stash TMDB-enriched title+year per legacy title_id so we can build clean
    # filenames without re-parsing from the dirty JazzDrive filename.
    legacy_title_meta: dict[int, dict] = {}

    # Get the account's MSISDN so we can stamp titles with account_number
    acct = db.get_account(v3_account_id)
    account_number = (acct or {}).get("msisdn") or ""

    try:
        with _legacy_schema._lock, _legacy_schema._get_conn() as c:
            for r in c.execute("SELECT * FROM titles"):
                t = dict(r)
                meta = {
                    "content_key":   t.get("content_key"),
                    "tmdb_id":       t.get("tmdb_id"),
                    "media_type":    t.get("media_type"),
                    "title":         t.get("title"),
                    "original_title":t.get("original_title"),
                    "year":          t.get("year"),
                    "rating":        t.get("rating"),
                    "vote_count":    t.get("vote_count") or 0,
                    "poster":        t.get("poster"),
                    "overview":      t.get("overview"),
                    "plot":          t.get("overview"),   # mirror into new field
                    "genres_csv":    t.get("genres_csv"),
                    "cast_names":    t.get("cast_names"),
                    "cast_json":     t.get("cast_json"),
                    "director":      t.get("director"),
                    "crew_json":     t.get("crew_json"),
                    "languages_csv": t.get("languages_csv"),
                    "runtime":       t.get("runtime"),
                    "account_number":account_number,
                    "industry":      t.get("industry"),
                }
                
                # Auto-tag industry, regenerate slug/confidence, fill missing
                # metadata (plot/poster/genres) using vault keys.
                # BUG-IMPORT-KEYS: previously called with no keys so TMDB/OMDB
                # were always skipped; every import relied on free fallbacks only.
                from .metadata import enrich_title
                from . import keys as _import_keys
                _t_key = _import_keys.get_active_value("tmdb") or None
                _o_key = _import_keys.get_active_value("omdb") or None
                meta = enrich_title(meta, tmdb_key=_t_key, omdb_key=_o_key)
                
                try:
                    new_id = db.upsert_title(meta)
                except Exception as _ue:
                    # UNIQUE slug conflict (duplicate legacy title) — look up
                    # the already-inserted row by slug so we can still link files.
                    _slug = meta.get("slug") or ""
                    if _slug and "UNIQUE" in str(_ue):
                        try:
                            _row = db._conn().execute(
                                "SELECT id FROM titles WHERE slug=?", (_slug,)
                            ).fetchone()
                            new_id = _row["id"] if _row else None
                        except Exception:
                            new_id = None
                    else:
                        log.debug("upsert_title failed for %r: %s", meta.get("title"), _ue)
                        new_id = None
                if new_id:
                    title_map[t["id"]] = new_id
                    legacy_title_meta[t["id"]] = {
                        "title": t.get("title") or "",
                        "year":  str(t.get("year") or "").strip(),
                    }

            # Import files, tracking folder share info per title
            title_folder_share: dict[int, str] = {}   # title_id → share_url

            for r in c.execute("SELECT * FROM files WHERE account_id=?", (legacy_id,)):
                f = dict(r)
                v3_title_id = title_map.get(f.get("title_id"))
                share_key   = f.get("share_key") or ""
                share_url   = f.get("share_url") or ""
                if not share_url and share_key:
                    share_url = f"https://cloud.jazzdrive.com.pk/f/{share_key}"

                # ── Clean filename via derive_media_plan ──────────────────────
                # Raw JD filenames are dirty (e.g. "Dune.Part.Two.2024.720p…mkv").
                # Apply media_naming so the DB always stores clean, organised names
                # regardless of how messy the original JazzDrive folder structure is.
                # This also handles: episodes in wrong folders, files in root,
                # seasons missing their folder — the clean name is derived from the
                # filename itself, not from where the file actually sits on JazzDrive.
                raw_filename  = f.get("filename") or ""
                jd_folder_path = f.get("folder_path") or ""
                clean_filename = raw_filename
                clean_folder   = jd_folder_path
                file_kind      = f.get("media_kind")
                file_season    = f.get("season")
                file_episode   = f.get("episode")
                try:
                    from .media_naming import derive_media_plan as _derive
                    if raw_filename:
                        _plan = _derive(raw_filename)
                        clean_filename = _plan.filename
                        clean_folder   = _plan.folder_str or jd_folder_path
                        if _plan.kind and _plan.kind != "file":
                            file_kind = _plan.kind
                        if _plan.season is not None:
                            file_season = _plan.season
                        if _plan.episode is not None:
                            file_episode = _plan.episode
                except Exception as _pe:
                    log.debug("derive_media_plan failed for %r: %s", raw_filename, _pe)

                # ── TMDB title override ───────────────────────────────────────
                # The raw JD filename title (e.g. "Vncenz0") is unreliable.
                # We already have the TMDB-enriched title in legacy_title_meta.
                # Build a synthetic clean filename from that title + the S/E
                # numbers already detected above, then run it through
                # derive_media_plan() to get a properly sanitized result.
                # This ensures files.filename stores "Vincenzo S01E02.mkv",
                # not "Vncenz0 S01E02.mkv" — making Passes 1-3 reliable even
                # when remote_id is 0 (e.g. very old scan rows).
                _tmdb_meta = legacy_title_meta.get(f.get("title_id"))
                if _tmdb_meta and _tmdb_meta.get("title") and raw_filename:
                    try:
                        import os as _os
                        from .media_naming import derive_media_plan as _derive
                        _ext = _os.path.splitext(raw_filename)[1]
                        _tt  = _tmdb_meta["title"]
                        _yr  = _tmdb_meta.get("year") or ""
                        if file_season is not None and file_episode is not None:
                            _synth = f"{_tt}.S{file_season:02d}E{file_episode:02d}{_ext}"
                        elif _yr:
                            _synth = f"{_tt}.{_yr}{_ext}"
                        else:
                            _synth = f"{_tt}{_ext}"
                        _plan2 = _derive(_synth)
                        clean_filename = _plan2.filename
                        if _plan2.folder_str:
                            clean_folder = _plan2.folder_str
                    except Exception as _te:
                        log.debug("TMDB filename override failed for %r: %s",
                                  raw_filename, _te)

                fid = db.upsert_file({
                    "fingerprint":     "scan:" + (f.get("fingerprint") or str(f.get("id"))),
                    "title_id":        v3_title_id,
                    "source":          "scan",
                    "account_id":      v3_account_id,
                    "filename":        clean_filename,
                    "media_kind":      file_kind,
                    "season":          file_season,
                    "episode":         file_episode,
                    "size_bytes":      f.get("size_bytes") or 0,
                    "quality":         f.get("quality"),
                    "remote_id":       f.get("remote_id"),
                    "remote_folder_id":f.get("remote_folder_id"),
                    "folder_path":     clean_folder,
                    "share_url":       share_url,
                    "share_key":       share_key,
                    "share_link_id":   f.get("share_link_id"),
                    "share_folder_id": f.get("share_folder_id"),
                    "download_url":    f.get("download_url"),
                    "scanned_at":      int(time.time()),
                })
                if fid:
                    n += 1
                    # Collect best folder share URL per title
                    if v3_title_id and share_url and v3_title_id not in title_folder_share:
                        title_folder_share[v3_title_id] = share_url

            # Back-fill folder_share_url on titles that now have a share link
            for tid, fsu in title_folder_share.items():
                try:
                    db.update_title(tid, {"folder_share_url": fsu})
                except Exception as _e:
                    log.debug("folder_share_url backfill for title %s: %s", tid, _e)

        # ── Post-import deduplication ─────────────────────────────────────────
        # Handles four real-world scenarios observed on JazzDrive:
        #
        # 1. Same episode uploaded twice with different filenames (clean + dirty)
        #    e.g. "All Of Us Are Dead S01E02.mkv" AND
        #         "All.Of.Us.Are.Dead.S01E02.720p.10Bit.Hindi.mkv" — same episode.
        #
        # 2. Loose root files duplicating a folder's episodes
        #    e.g. "All Of Us Are Dead S01E08.mkv" at root AND in the season folder.
        #
        # 3. Two encodes of the same movie
        #    e.g. Interstellar x264 1.8GB AND x265 HEVC 1.5GB — same title.
        #
        # 4. Same file copied with different names at different folder depths.
        #
        # Rule: keep the file with the LARGEST size_bytes (best quality proxy).
        # For episodes: deduplicate on (account_id, title_id, season, episode).
        # For movies:   deduplicate on (account_id, title_id) where no season/ep.
        dedup_removed = 0
        try:
            with db.conn() as _dc:
                # TV episode duplicates
                tv_dups = _dc.execute("""
                    SELECT title_id, season, episode, COUNT(*) AS cnt
                    FROM files
                    WHERE account_id=? AND season IS NOT NULL AND episode IS NOT NULL
                      AND title_id IS NOT NULL
                    GROUP BY title_id, season, episode
                    HAVING cnt > 1
                """, (v3_account_id,)).fetchall()
                for row in tv_dups:
                    keep = _dc.execute("""
                        SELECT id FROM files
                        WHERE account_id=? AND title_id=? AND season=? AND episode=?
                        ORDER BY size_bytes DESC LIMIT 1
                    """, (v3_account_id, row["title_id"], row["season"], row["episode"])).fetchone()
                    if keep:
                        gone = _dc.execute("""
                            DELETE FROM files
                            WHERE account_id=? AND title_id=? AND season=? AND episode=?
                              AND id != ?
                        """, (v3_account_id, row["title_id"], row["season"], row["episode"],
                              keep["id"])).rowcount
                        dedup_removed += gone

                # Movie duplicates (same title, no season/episode)
                movie_dups = _dc.execute("""
                    SELECT title_id, COUNT(*) AS cnt
                    FROM files
                    WHERE account_id=? AND (season IS NULL OR season = '')
                      AND (episode IS NULL OR episode = '')
                      AND title_id IS NOT NULL
                    GROUP BY title_id
                    HAVING cnt > 1
                """, (v3_account_id,)).fetchall()
                for row in movie_dups:
                    keep = _dc.execute("""
                        SELECT id FROM files
                        WHERE account_id=? AND title_id=?
                          AND (season IS NULL OR season = '')
                          AND (episode IS NULL OR episode = '')
                        ORDER BY size_bytes DESC LIMIT 1
                    """, (v3_account_id, row["title_id"])).fetchone()
                    if keep:
                        gone = _dc.execute("""
                            DELETE FROM files
                            WHERE account_id=? AND title_id=?
                              AND (season IS NULL OR season = '')
                              AND (episode IS NULL OR episode = '')
                              AND id != ?
                        """, (v3_account_id, row["title_id"], keep["id"])).rowcount
                        dedup_removed += gone

            if dedup_removed:
                log.info("dedup: removed %d duplicate file(s) for account %s",
                         dedup_removed, v3_account_id)
                n -= dedup_removed
        except Exception as _de:
            log.debug("dedup step failed: %s", _de)

    except Exception as e:
        log.warning("legacy → v3 import failed: %s", e)
    return n


def _enrich_low_confidence_titles(account_id: int, progress_cb=None) -> int:
    """Run TMDB/OMDB enrichment on titles that have confidence < 30 in parallel."""
    from concurrent.futures import ThreadPoolExecutor
    from .metadata import enrich_title as _enrich

    tmdb_keys = keys.get_all_active_values("tmdb")
    omdb_keys = keys.get_all_active_values("omdb")
    
    if not tmdb_keys and not omdb_keys:
        if progress_cb:
            progress_cb({"type": "warn", "message": "No API keys configured — skipping parallel enrichment"})
        return 0

    # Find titles linked to this account's files with confidence < 60.
    # BUG-THRESHOLD: was < 30, but title+year+media_type = 30 pts already, so
    # titles from legacy scanner that are missing plot/poster/genres (confidence
    # 30-59) were silently skipped. Threshold raised to 60 so they get filled in.
    with db.conn() as c:
        rows = c.execute(
            "SELECT DISTINCT t.id, t.title, t.year, t.media_type, t.confidence "
            "FROM titles t JOIN files f ON t.id=f.title_id "
            "WHERE f.account_id=? AND (t.confidence IS NULL OR t.confidence < 60) "
            "AND t.title IS NOT NULL AND t.title != '' "
            "LIMIT 200",
            (account_id,)
        ).fetchall()

    if not rows:
        return 0

    titles = [dict(r) for r in rows]
    total = len(titles)
    
    # Use as many threads as we have keys (min 2, max 10)
    num_threads = min(max(len(tmdb_keys), len(omdb_keys), 2), 10)
    
    # BUG-ROTATION: updated_count was 0 inside every worker closure (captured
    # by reference but never updated before workers read it), so all threads
    # always used tmdb_keys[0] — no rotation. Fixed: pass (idx, title_meta)
    # tuples so each worker derives its key slot from the task index.
    def worker(idx_and_meta):
        idx, title_meta = idx_and_meta
        t_key = tmdb_keys[idx % len(tmdb_keys)] if tmdb_keys else None
        o_key = omdb_keys[idx % len(omdb_keys)] if omdb_keys else None

        if progress_cb:
            progress_cb({"type": "enrich", "message": f"Parallel Enriching: {title_meta['title']}"})

        try:
            from . import assets
            enriched = _enrich(title_meta, tmdb_key=t_key, omdb_key=o_key)
            new_title_id = db.upsert_title(enriched)
            if new_title_id:
                if enriched.get("poster"):
                    assets.process_title_poster(new_title_id, enriched["poster"], account_id)
            return True
        except Exception as e:
            log.debug("parallel enrich failed for %s: %s", title_meta.get("title"), e)
            return False

    with ThreadPoolExecutor(max_workers=num_threads) as executor:
        results = list(executor.map(worker, enumerate(titles)))
        updated_count = sum(1 for r in results if r)

    if progress_cb and updated_count:
        progress_cb({"type": "enrich", "message": f"Successfully enriched {updated_count}/{total} titles in parallel"})
    
    return updated_count


def _get_clean_file_set(account_id: int) -> tuple[set, set]:
    """Return two sets for skip-already-clean optimisation.

    Returns:
        (clean_remote_ids, clean_filenames)

    A file is considered "already clean" when ALL of these hold:
      • Exists in the DB linked to this account
      • Its title has confidence ≥ 60
      • Its title has a poster URL  (TMDB or JazzDrive-hosted)
      • Its title has both title and year populated
      • Its title has a plot/overview (means metadata is real, not stub)

    During a re-scan the scanner can skip TMDB enrichment for these files —
    they are imported as-is with their existing DB data, saving significant time.
    """
    clean_remote_ids: set[str] = set()
    clean_filenames:  set[str] = set()
    try:
        with db.conn() as c:
            rows = c.execute(
                """SELECT f.remote_id, f.filename,
                          t.confidence, t.poster, t.title, t.year, t.plot
                   FROM files f
                   LEFT JOIN titles t ON t.id = f.title_id
                   WHERE f.account_id = ?
                     AND f.remote_id IS NOT NULL""",
                (account_id,)
            ).fetchall()
        for r in rows:
            if (
                (r["confidence"] or 0) >= 60
                and (r["poster"] or "")
                and (r["title"] or "")
                and (r["year"] or "")
                and (r["plot"] or "")
            ):
                if r["remote_id"]:
                    clean_remote_ids.add(str(r["remote_id"]))
                if r["filename"]:
                    clean_filenames.add(r["filename"].lower())
    except Exception as e:
        log.debug("_get_clean_file_set: %s", e)
    return clean_remote_ids, clean_filenames


def _mirror_unsynced_for_account(account_id: int) -> int:
    """Push every file for this account that isn't mirrored yet."""
    with db.conn() as c:
        rows = c.execute(
            "SELECT id FROM files WHERE account_id=? AND "
            "(github_status IS NULL OR github_status='failed' OR "
            " gsheets_status IS NULL OR gsheets_status='failed')",
            (account_id,)
        ).fetchall()
    n = 0
    for r in rows:
        try:
            mirror.push_file(r["id"])
            n += 1
        except Exception as e:
            log.warning("mirror file %s: %s", r["id"], e)
    return n