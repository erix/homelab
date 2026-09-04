#!/usr/bin/env python3
"""Two-stage Playwright login for the k3s IBeam Client Portal Gateway.

Reads username, password, and TOTP seed from files written by the 1Password
init container. Never prints secrets, cookies, or OTP codes.
"""
from __future__ import annotations

import hmac
import hashlib
import json
import os
import ssl
import struct
import sys
import time
import urllib.request

BASE_URL = os.environ.get("IBKR_CP_URL", "https://ibeam.default.svc:5000").rstrip("/")
PRELOGIN_URL = os.environ.get(
    "IBKR_PRELOGIN_URL", "https://www.interactivebrokers.ie/sso/Login?RL=1"
)
ACCOUNT_FILE = os.environ.get("IBEAM_ACCOUNT_FILE", "/secrets/IBEAM_ACCOUNT")
PASSWORD_FILE = os.environ.get("IBEAM_PASSWORD_FILE", "/secrets/IBEAM_PASSWORD")
TOTP_FILE = os.environ.get("IBEAM_PYOTP_SECRET_FILE", "/secrets/IBEAM_PYOTP_SECRET")

CTX = ssl._create_unverified_context()


def event(name: str, **fields) -> None:
    print(json.dumps({"event": name, **fields}, sort_keys=True), flush=True)


def read_secret(path: str) -> str:
    value = open(path, encoding="utf-8").read().strip()
    if not value:
        raise RuntimeError(f"empty secret file {os.path.basename(path)}")
    return value


def totp(secret: str, interval: int = 30) -> str:
    pad = "=" * ((8 - len(secret) % 8) % 8)
    key = __import__("base64").b32decode(secret.upper() + pad)
    remaining = interval - (time.time() % interval)
    if remaining < 8:
        time.sleep(remaining + 0.5)
    counter = int(time.time() // interval)
    digest = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    code = (struct.unpack(">I", digest[offset : offset + 4])[0] & 0x7FFFFFFF) % 1_000_000
    return f"{code:06d}"


def request_json(method: str, path: str, timeout: int = 20) -> tuple[int, dict]:
    url = BASE_URL + "/v1/api" + path
    req = urllib.request.Request(url, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=CTX) as resp:
            body = resp.read().decode("utf-8", "replace")
            status = resp.status
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        status = e.code
    try:
        data = json.loads(body) if body else {}
    except json.JSONDecodeError:
        data = {}
    return status, data


def auth_status() -> dict:
    status, data = request_json("GET", "/iserver/auth/status")
    return {
        "http_status": status,
        "authenticated": bool(data.get("authenticated")),
        "connected": bool(data.get("connected")),
        "competing": bool(data.get("competing")),
    }


def fill_first(page, selectors: list[str], value: str, label: str) -> bool:
    for selector in selectors:
        loc = page.locator(selector).first
        try:
            if loc.count() and loc.is_visible(timeout=1000):
                loc.fill(value, timeout=5000)
                event("filled", field=label, selector=selector)
                return True
        except Exception:
            continue
    return False


def click_first(page, selectors: list[str], label: str) -> bool:
    for selector in selectors:
        loc = page.locator(selector).first
        try:
            if loc.count() and loc.is_visible(timeout=1000):
                loc.click(timeout=5000, no_wait_after=True)
                event("clicked", control=label, selector=selector)
                return True
        except Exception:
            continue
    return False


def submit_browser_login(page, login_url: str, username: str, password: str, totp_secret: str, stage: str) -> None:
    event("browser_login_stage_start", stage=stage, url=login_url.split("?")[0])
    try:
        page.goto(login_url, wait_until="networkidle", timeout=30000)
    except Exception:
        page.wait_for_load_state("domcontentloaded", timeout=10000)
    event("login_page_loaded", stage=stage, title=page.title()[:80])

    user_ok = fill_first(
        page,
        ['input[name="username"]', "#username", "#user_name", 'input[type="text"]', 'input[name="user_name"]'],
        username,
        "username",
    )
    pass_ok = fill_first(
        page,
        ['input[name="password"]', "#password", 'input[type="password"]'],
        password,
        "password",
    )
    if not (user_ok and pass_ok):
        raise RuntimeError(f"Could not find username/password fields during {stage} login")

    page.wait_for_timeout(1000)
    submitted = False
    try:
        submit = page.locator(
            '.xyz-button-login:visible, button[type="submit"]:visible, input[type="submit"]:visible'
        ).first
        if submit.count() and submit.is_visible(timeout=1000):
            submit.click(timeout=5000, no_wait_after=True, force=True)
            submitted = True
            event("clicked", control="submit_credentials", stage=stage)
    except Exception:
        pass
    if not submitted:
        submitted = click_first(
            page,
            [
                ".xyz-button-login:visible",
                'button[type="submit"]:visible',
                'input[type="submit"]:visible',
                'button:has-text("Log In"):visible',
                'button:has-text("Login"):visible',
            ],
            "submit_credentials",
        )
    if not submitted:
        try:
            page.locator('input[name="password"], input[type="password"]').first.press("Enter")
            submitted = True
            event("submitted", control="password_enter", stage=stage)
        except Exception:
            pass
    if not submitted:
        raise RuntimeError(f"Could not submit credentials during {stage} login")
    page.wait_for_timeout(5000)

    otp_selectors = [
        'input[name="otp"]',
        'input[name="code"]',
        "#otp",
        "#oneTimePassword",
        'input[name="challenge"]',
        'input[name*="otp" i]',
        'input[name*="code" i]',
        'input[id*="otp" i]',
        'input[id*="code" i]',
        'input[autocomplete="one-time-code"]',
        'input[inputmode="numeric"]',
    ]
    otp_needed = False
    for selector in otp_selectors:
        try:
            loc = page.locator(selector).first
            if loc.count() and loc.is_visible(timeout=1000):
                otp_needed = True
                loc.fill(totp(totp_secret), timeout=5000)
                event("filled", stage=stage, field="otp", selector=selector)
                otp_submitted = False
                try:
                    otp_submit = loc.locator("xpath=ancestor::form[1]").locator(
                        'button[type="submit"], input[type="submit"]'
                    ).first
                    if otp_submit.count():
                        otp_submit.click(timeout=5000, no_wait_after=True, force=True)
                        otp_submitted = True
                        event("clicked", stage=stage, control="submit_otp")
                except Exception:
                    pass
                if not otp_submitted:
                    loc.press("Enter")
                    event("submitted", stage=stage, control="otp_enter")
                page.wait_for_timeout(8000)
                break
        except Exception:
            continue
    event("otp_step", stage=stage, needed=otp_needed)

    for _ in range(3):
        clicked = click_first(
            page,
            [
                'button:has-text("Continue")',
                'button:has-text("I understand")',
                'button:has-text("Allow")',
                'button:has-text("Yes")',
                'input[type="submit"]',
            ],
            "post_login_prompt",
        )
        if not clicked:
            break
        page.wait_for_timeout(2000)

    for selector in (".alert-danger", '[role="alert"]', ".xyz-alert-error"):
        for alert in page.locator(selector).all():
            try:
                if not alert.is_visible():
                    continue
                text = (alert.inner_text() or "").lower()
                if any(
                    marker in text
                    for marker in (
                        "authentication failed",
                        "login failed",
                        "invalid username",
                        "invalid password",
                        "incorrect password",
                    )
                ):
                    raise RuntimeError(f"IBKR rejected the {stage} login")
            except RuntimeError:
                raise
            except Exception:
                continue
    event("browser_login_stage_submitted", stage=stage, final_url=page.url.split("?")[0])


def playwright_login(username: str, password: str, totp_secret: str) -> None:
    from playwright.sync_api import sync_playwright

    gateway_login_url = BASE_URL + "/sso/Login"
    event("browser_login_start", url=gateway_login_url)
    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=True,
            args=["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu"],
        )
        context = browser.new_context(ignore_https_errors=True)
        page = context.new_page()
        page.set_default_timeout(15000)
        try:
            submit_browser_login(page, PRELOGIN_URL, username, password, totp_secret, "public_portal")
            submit_browser_login(page, gateway_login_url, username, password, totp_secret, "gateway")
            event("browser_login_submitted", final_url=page.url.split("?")[0])
        finally:
            context.close()
            browser.close()


def main() -> int:
    try:
        status = auth_status()
        event("status", **status)
        if status["authenticated"]:
            return 0

        username = read_secret(ACCOUNT_FILE)
        password = read_secret(PASSWORD_FILE)
        totp_secret = read_secret(TOTP_FILE)
        playwright_login(username, password, totp_secret)

        http, init_data = request_json(
            "POST", "/iserver/auth/ssodh/init?publish=true&compete=true"
        )
        event(
            "init_after_login",
            http_status=http,
            authenticated=bool(init_data.get("authenticated")),
            connected=bool(init_data.get("connected")),
        )
        status = auth_status()
        event("status_after_login", **status)
        return 0 if status["authenticated"] else 2
    except Exception as e:
        event("error", message=str(e))
        return 1


if __name__ == "__main__":
    sys.exit(main())
