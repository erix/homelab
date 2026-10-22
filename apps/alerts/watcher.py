"""Email when an opted-in CronJob fails or stops succeeding, or a health URL
stops answering 200. One email when a problem appears, one when it clears.

A CronJob opts in with the annotation `alerts.erix-homelab.site/max-age`
(for example `26h`): the time allowed since its last successful run.
Open problems are kept in the ConfigMap `alerts-state`, so a problem is
reported once, not on every run."""

from __future__ import annotations

import json
import os
import smtplib
import ssl
import urllib.error
import urllib.request
from datetime import UTC, datetime, timedelta
from email.message import EmailMessage
from email.utils import formatdate, make_msgid

ANNOTATION = "alerts.erix-homelab.site/max-age"
STATE = "alerts-state"
API = "https://kubernetes.default.svc"
ACCOUNT = "/var/run/secrets/kubernetes.io/serviceaccount"
LOG_LINES = 15


def parse_age(value: str) -> timedelta:
    units = {"m": "minutes", "h": "hours", "d": "days"}
    return timedelta(**{units[value[-1]]: float(value[:-1])})


def parse_time(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def failed(job: dict) -> bool:
    return any(c["type"] == "Failed" and c["status"] == "True" for c in job.get("status", {}).get("conditions") or [])


def cronjob_problems(cronjobs: list[dict], jobs: list[dict], now: datetime, logs=lambda job: "") -> dict[str, str]:
    latest: dict[tuple[str, str], dict] = {}
    for job in jobs:
        for owner in job["metadata"].get("ownerReferences") or []:
            if owner["kind"] == "CronJob":
                key = (job["metadata"]["namespace"], owner["name"])
                if key not in latest or job["metadata"]["creationTimestamp"] > latest[key]["metadata"]["creationTimestamp"]:
                    latest[key] = job
    problems = {}
    for cj in cronjobs:
        meta = cj["metadata"]
        max_age = (meta.get("annotations") or {}).get(ANNOTATION)
        if not max_age or cj["spec"].get("suspend"):
            continue
        ns, name = meta["namespace"], meta["name"]
        key = f"cronjob {ns}/{name}"
        job = latest.get((ns, name))
        if job is not None and failed(job):
            reason = next(c for c in job["status"]["conditions"] if c["type"] == "Failed")
            message = f"last run {job['metadata']['name']} failed: {reason.get('reason')} {reason.get('message', '')}".strip()
            tail = logs(job)
            problems[key] = message + (f"\n\nLast log lines:\n{tail}" if tail else "")
            continue
        last = cj.get("status", {}).get("lastSuccessfulTime")
        since = parse_time(last or meta["creationTimestamp"])
        if now - since > parse_age(max_age):
            problems[key] = f"no successful run since {last or 'it was created'} (allowed: {max_age})"
    return problems


def url_problems(urls: dict[str, str], fetch) -> dict[str, str]:
    problems = {}
    for name, url in urls.items():
        status, body = fetch(url)
        if status != 200:
            try:
                details = "\n".join(json.loads(body)["problems"])
            except (ValueError, KeyError, TypeError):
                details = body[:500]
            problems[f"health {name}"] = f"{url} answered {status}\n{details}".strip()
    return problems


def changes(previous: dict[str, dict], current: dict[str, str], now: datetime):
    opened = {k: v for k, v in current.items() if k not in previous}
    resolved = {k: v for k, v in previous.items() if k not in current}
    state = {k: previous.get(k, {"since": now.isoformat(timespec="seconds")}) | {"message": v} for k, v in current.items()}
    return opened, resolved, state


def compose(opened: dict[str, str], resolved: dict[str, dict], still_open: int) -> EmailMessage:
    parts = []
    if opened:
        parts.append(f"{len(opened)} new problem(s)")
    if resolved:
        parts.append(f"{len(resolved)} resolved")
    msg = EmailMessage()
    msg["Subject"] = f"[homelab] {', '.join(parts)}"
    # Neither smtplib nor mail-relay adds these for mail from pods, and Gmail
    # may drop or spam-file a message without them.
    msg["Date"] = formatdate(usegmt=True)
    msg["Message-ID"] = make_msgid(domain="erix-homelab.site")
    body = []
    for key, message in opened.items():
        body.append(f"PROBLEM  {key}\n{message}\n")
    for key, entry in resolved.items():
        body.append(f"RESOLVED {key} (open since {entry['since']})\n")
    body.append(f"Problems still open: {still_open}.")
    msg.set_content("\n".join(body))
    return msg


class Kube:
    def __init__(self):
        self.token = open(f"{ACCOUNT}/token").read()
        self.ctx = ssl.create_default_context(cafile=f"{ACCOUNT}/ca.crt")

    def call(self, method: str, path: str, body: dict | None = None, raw: bool = False):
        request = urllib.request.Request(
            API + path,
            method=method,
            data=json.dumps(body).encode() if body is not None else None,
            headers={"Authorization": f"Bearer {self.token}", "Content-Type": "application/json"},
        )
        with urllib.request.urlopen(request, context=self.ctx, timeout=30) as response:
            data = response.read().decode()
        return data if raw else json.loads(data)

    def logs(self, job: dict) -> str:
        ns, name = job["metadata"]["namespace"], job["metadata"]["name"]
        try:
            pods = self.call("GET", f"/api/v1/namespaces/{ns}/pods?labelSelector=job-name%3D{name}")["items"]
            if not pods:
                return ""
            pod = max(pods, key=lambda p: p["metadata"]["creationTimestamp"])["metadata"]["name"]
            return self.call("GET", f"/api/v1/namespaces/{ns}/pods/{pod}/log?tailLines={LOG_LINES}", raw=True).strip()
        except urllib.error.HTTPError:
            return ""


def fetch(url: str) -> tuple[int, str]:
    try:
        with urllib.request.urlopen(url, timeout=20) as response:
            return response.status, response.read().decode()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode(errors="replace")
    except OSError as exc:
        return 0, f"unreachable: {exc}"


def main() -> None:
    now = datetime.now(UTC)
    kube = Kube()
    ns = open(f"{ACCOUNT}/namespace").read().strip()
    current = cronjob_problems(
        kube.call("GET", "/apis/batch/v1/cronjobs")["items"],
        kube.call("GET", "/apis/batch/v1/jobs")["items"],
        now,
        kube.logs,
    ) | url_problems(json.loads(os.environ.get("HEALTH_URLS", "{}")), fetch)

    try:
        stored = kube.call("GET", f"/api/v1/namespaces/{ns}/configmaps/{STATE}")
        previous = json.loads(stored["data"]["open"])
    except urllib.error.HTTPError as exc:
        if exc.code != 404:
            raise
        stored, previous = None, {}

    opened, resolved, state = changes(previous, current, now)
    print(f"open: {sorted(current)}; new: {sorted(opened)}; resolved: {sorted(resolved)}")
    if opened or resolved:
        msg = compose(opened, resolved, len(current))
        msg["From"], msg["To"] = os.environ["ALERT_FROM"], os.environ["ALERT_TO"]
        with smtplib.SMTP(os.environ["SMTP_HOST"], int(os.environ.get("SMTP_PORT", "25")), timeout=30) as smtp:
            smtp.send_message(msg)
        print(f"sent: {msg['Subject']}")

    # Saved only after the email went out, so a failed send is retried next run.
    configmap = {"apiVersion": "v1", "kind": "ConfigMap", "metadata": {"name": STATE, "namespace": ns}, "data": {"open": json.dumps(state)}}
    if stored is None:
        kube.call("POST", f"/api/v1/namespaces/{ns}/configmaps", configmap)
    elif state != previous:
        configmap["metadata"]["resourceVersion"] = stored["metadata"]["resourceVersion"]
        kube.call("PUT", f"/api/v1/namespaces/{ns}/configmaps/{STATE}", configmap)


if __name__ == "__main__":
    main()
