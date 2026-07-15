import ipaddress
import json
import os
import re
import threading
import time
from collections import defaultdict, deque
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ALLOWED_ORIGINS = {
    "https://hello-confidence.com",
    "https://www.hello-confidence.com",
}
API_TOKEN = os.environ["MAILERLITE_API_TOKEN"]
GROUP_ID = os.environ["MAILERLITE_GROUP_ID"]
EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
RATE_WINDOW_SECONDS = 600
RATE_LIMIT = 8
RATE_BUCKETS = defaultdict(deque)
RATE_LOCK = threading.Lock()


def client_ip(headers):
    value = headers.get("CF-Connecting-IP") or headers.get("X-Forwarded-For", "").split(",", 1)[0]
    try:
        return str(ipaddress.ip_address(value.strip()))
    except ValueError:
        return None


def rate_limited(ip):
    if not ip:
        return False
    now = time.monotonic()
    with RATE_LOCK:
        bucket = RATE_BUCKETS[ip]
        while bucket and now - bucket[0] > RATE_WINDOW_SECONDS:
            bucket.popleft()
        if len(bucket) >= RATE_LIMIT:
            return True
        bucket.append(now)
        return False


class Handler(BaseHTTPRequestHandler):
    server_version = "HelloConfidenceSignup/1.0"

    def log_message(self, format, *args):
        print("request", self.command, self.path, args[1] if len(args) > 1 else "", flush=True)

    def send_json(self, status, payload, origin=None):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        if origin in ALLOWED_ORIGINS:
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/healthz":
            self.send_json(200, {"ok": True})
        else:
            self.send_json(404, {"ok": False})

    def do_OPTIONS(self):
        origin = self.headers.get("Origin")
        if self.path != "/api/newsletter" or origin not in ALLOWED_ORIGINS:
            self.send_json(403, {"ok": False})
            return
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", origin)
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Max-Age", "600")
        self.send_header("Vary", "Origin")
        self.end_headers()

    def do_POST(self):
        origin = self.headers.get("Origin")
        if self.path != "/api/newsletter":
            self.send_json(404, {"ok": False}, origin)
            return
        if origin not in ALLOWED_ORIGINS:
            self.send_json(403, {"ok": False, "message": "Origin not allowed."}, origin)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0 or length > 4096:
            self.send_json(400, {"ok": False, "message": "Invalid request."}, origin)
            return
        try:
            payload = json.loads(self.rfile.read(length))
        except (json.JSONDecodeError, UnicodeDecodeError):
            self.send_json(400, {"ok": False, "message": "Invalid request."}, origin)
            return
        if payload.get("website"):
            self.send_json(202, {"ok": True}, origin)
            return
        email = str(payload.get("email", "")).strip().lower()
        source = payload.get("source")
        consent = payload.get("consent") is True
        if len(email) > 254 or not EMAIL_RE.fullmatch(email) or source not in {"footer", "guide"} or not consent:
            self.send_json(400, {"ok": False, "message": "Please provide a valid email address and consent."}, origin)
            return
        ip = client_ip(self.headers)
        if rate_limited(ip):
            self.send_json(429, {"ok": False, "message": "Please wait before trying again."}, origin)
            return
        now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
        subscriber = {
            "email": email,
            "groups": [GROUP_ID],
            "status": "active",
            "subscribed_at": now,
            "opted_in_at": now,
        }
        if ip:
            subscriber["ip_address"] = ip
            subscriber["optin_ip"] = ip
        request = Request(
            "https://connect.mailerlite.com/api/subscribers",
            data=json.dumps(subscriber).encode(),
            headers={
                "Authorization": f"Bearer {API_TOKEN}",
                "Accept": "application/json",
                "Content-Type": "application/json",
                "User-Agent": "HelloConfidenceSignup/1.0",
            },
            method="POST",
        )
        try:
            with urlopen(request, timeout=10) as response:
                if response.status not in {200, 201}:
                    raise RuntimeError("Unexpected MailerLite response")
        except HTTPError as exc:
            print("MailerLite HTTP error", exc.code, flush=True)
            self.send_json(502, {"ok": False, "message": "Signup is temporarily unavailable."}, origin)
            return
        except (URLError, TimeoutError, RuntimeError) as exc:
            print("MailerLite connection error", type(exc).__name__, flush=True)
            self.send_json(502, {"ok": False, "message": "Signup is temporarily unavailable."}, origin)
            return
        self.send_json(200, {"ok": True, "message": "You’re on the list. Welcome."}, origin)


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
