import importlib.util
import os
from datetime import UTC, datetime

# Run: uv run --with pytest python -m pytest apps/alerts/test_watcher.py
spec = importlib.util.spec_from_file_location("watcher", os.path.join(os.path.dirname(__file__), "watcher.py"))
w = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w)

NOW = datetime(2026, 10, 23, 12, 0, tzinfo=UTC)


def cronjob(name, max_age="26h", last=None, created="2026-10-01T00:00:00Z", suspend=False):
    meta = {"namespace": "ns", "name": name, "creationTimestamp": created}
    if max_age:
        meta["annotations"] = {w.ANNOTATION: max_age}
    return {"metadata": meta, "spec": {"suspend": suspend}, "status": {"lastSuccessfulTime": last} if last else {}}


def job(name, owner, created, failed=False):
    conditions = [{"type": "Failed", "status": "True", "reason": "BackoffLimitExceeded", "message": "Job has reached the specified backoff limit"}] if failed else [{"type": "Complete", "status": "True"}]
    return {"metadata": {"namespace": "ns", "name": name, "creationTimestamp": created, "ownerReferences": [{"kind": "CronJob", "name": owner}]}, "status": {"conditions": conditions}}


def test_failed_latest_run_is_a_problem_with_its_log():
    cjs = [cronjob("db-backup", last="2026-10-23T01:00:00Z")]
    jobs = [job("db-backup-1", "db-backup", "2026-10-22T01:00:00Z"), job("db-backup-2", "db-backup", "2026-10-23T01:00:00Z", failed=True)]
    problems = w.cronjob_problems(cjs, jobs, NOW, logs=lambda j: "Permission denied")
    assert list(problems) == ["cronjob ns/db-backup"]
    assert "db-backup-2 failed: BackoffLimitExceeded" in problems["cronjob ns/db-backup"]
    assert problems["cronjob ns/db-backup"].endswith("Permission denied")


def test_a_later_success_clears_an_earlier_failure():
    cjs = [cronjob("db-backup", last="2026-10-23T01:00:00Z")]
    jobs = [job("old", "db-backup", "2026-10-22T01:00:00Z", failed=True), job("new", "db-backup", "2026-10-23T01:00:00Z")]
    assert w.cronjob_problems(cjs, jobs, NOW) == {}


def test_no_success_within_max_age_is_a_problem_and_unannotated_or_suspended_are_ignored():
    cjs = [
        cronjob("stale", last="2026-10-21T01:00:00Z"),
        cronjob("never", created="2026-10-20T00:00:00Z"),
        cronjob("fresh", last="2026-10-23T01:00:00Z"),
        cronjob("ignored", max_age=None, last="2026-01-01T00:00:00Z"),
        cronjob("paused", last="2026-01-01T00:00:00Z", suspend=True),
    ]
    problems = w.cronjob_problems(cjs, [], NOW)
    assert sorted(problems) == ["cronjob ns/never", "cronjob ns/stale"]
    assert "since 2026-10-21T01:00:00Z" in problems["cronjob ns/stale"]


def test_health_url_problems_list_the_reported_problems():
    answers = {"http://a/healthz/sync": (503, '{"ok": false, "problems": ["trakt: login needs renewing"]}'), "http://b/": (200, "{}"), "http://c/": (0, "unreachable: refused")}
    problems = w.url_problems({"a": "http://a/healthz/sync", "b": "http://b/", "c": "http://c/"}, answers.get)
    assert problems == {"health a": "http://a/healthz/sync answered 503\ntrakt: login needs renewing", "health c": "http://c/ answered 0\nunreachable: refused"}


def test_each_problem_is_reported_once_when_it_opens_and_once_when_it_clears():
    opened, resolved, state = w.changes({}, {"x": "broken"}, NOW)
    assert opened == {"x": "broken"} and resolved == {}
    later = datetime(2026, 10, 23, 12, 10, tzinfo=UTC)
    opened, resolved, state2 = w.changes(state, {"x": "still broken"}, later)
    assert opened == {} and resolved == {} and state2["x"]["since"] == state["x"]["since"]
    opened, resolved, state3 = w.changes(state2, {}, later)
    assert opened == {} and list(resolved) == ["x"] and state3 == {}
    msg = w.compose({}, resolved, 0)
    assert msg["Subject"] == "[homelab] 1 resolved" and "RESOLVED x (open since 2026-10-23T12:00:00+00:00)" in msg.get_content()


def test_emails_carry_date_and_message_id():
    msg = w.compose({"x": "broken"}, {}, 1)
    assert msg["Date"] and msg["Message-ID"].endswith("@erix-homelab.site>")
