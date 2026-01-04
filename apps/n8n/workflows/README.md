# Reddit IPTV Base64 Email workflow

Workflow file: `reddit-iptv-base64-email.json`

## Usage

1. Import the JSON file into n8n (`Workflow > Import from File`).
2. Add or select an SMTP credential in the **Send Email** node (the workflow ships without credentials). Use `n8n@erix-homelab.site` or any other desired sender address.
3. If you prefer a different polling cadence, adjust the **Check Hourly** Cron node (defaults to once per hour).
4. Activate the workflow once you validate that outbound email works. New posts that contain long Base64 blobs in the title or body will be decoded, aggregated into a single message, and emailed to `erik.simko@gmail.com`.
