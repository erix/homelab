# Subscription Tracker API Notes

Session-derived notes for querying Erik's `subscription-tracker` app in the k3s homelab without exposing secrets.

## Access pattern

The app runs in `default` as `deployment/subscription-tracker`, listens on container port `8000`, and has public ingress host `subs.erix-homelab.site`. For safe internal API probing, exec inside the pod/deployment and call localhost:

```bash
export KUBECONFIG=/home/erix/.kube/config
K=/home/erix/.local/bin/kubectl

$K -n default exec deploy/subscription-tracker -- python - <<'PY'
import json, urllib.request
print(urllib.request.urlopen('http://127.0.0.1:8000/api/health').read().decode())
print(json.dumps(json.load(urllib.request.urlopen('http://127.0.0.1:8000/openapi.json'))['paths'].keys(), indent=2, default=list))
PY
```

If heredoc exec quoting is awkward, use `python -c` instead.

## Useful endpoints

- `GET /api/health` — health check.
- `GET /openapi.json` — discover current API schema.
- `GET /api/categories` — list categories.
- `GET /api/transactions` — paginated transaction query.
- `PATCH /api/transactions/{tx_id}` — update `user_category_id`; optional `save_as_mapping`.
- `GET /api/categorize/suggestions` — pending categorization suggestions.

`/api/transactions` query parameters observed:

- `start_date` / `end_date`: ISO dates, inclusive.
- `category_id`: integer effective category filter.
- `direction`: string, e.g. `out`.
- `search`: text search.
- `uncategorized`: boolean; in app code this means `category_id IS NULL AND user_category_id IS NULL`.
- `page`: default 1.
- `limit`: 1..200; use `limit=1` when only the count is needed because response includes `total`.

## Counting unattended / uncategorized transactions

The API's `uncategorized=true` is the closest match for "unattended": no auto category and no user category. Query `limit=1` and read `total`:

```bash
$K -n default exec deploy/subscription-tracker -- python -c '
import json, urllib.parse, urllib.request
params={"start_date":"YYYY-MM-DD","end_date":"YYYY-MM-DD","uncategorized":"true","limit":"1"}
url="http://127.0.0.1:8000/api/transactions?"+urllib.parse.urlencode(params)
print(json.load(urllib.request.urlopen(url))["total"])
'
```

Be explicit about the date interpretation:

- Rolling last 30 days from the host date.
- Previous calendar month.

Use a tool for date arithmetic; don't compute dates mentally.

## Nuance

`is_user_categorized=false` is broader than `uncategorized=true`: transactions may have an automatic/system category (`category_id`) but no user override (`user_category_id`). If the user asks for "not manually reviewed/categorized", clarify or report both counts.