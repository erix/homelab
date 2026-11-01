# OpenPosterDB

Self-hosted RPDB drop-in (https://github.com/PNRxA/openposterdb) that renders
posters with rating badges. Used by AIOMetadata as a Custom Art URL.

- URL: https://openposterdb.erix-homelab.site (LAN/Tailscale via Traefik, same as aiometadata)
- Image: pinned `ghcr.io/pnrxa/openposterdb` tag + digest, no image automation.
- Data: `/data` (SQLite db + image cache) on PVC `openposterdb-data` (local-path).
- Secrets: `openposterdb-secret` (SealedSecret: JWT_SECRET, ADMIN_USERNAME,
  ADMIN_PASSWORD; admin seeded only when no admin exists). TMDB, MDBList,
  Fanart and Trakt keys are referenced from `aiometadata-secret`.
- API keys: create in the admin UI (API keys page); poster template for AIOMetadata:
  `https://openposterdb.erix-homelab.site/<key>/imdb/poster-default/{imdb_id}.jpg`
