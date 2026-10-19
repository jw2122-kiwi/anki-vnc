# Anki Web + VNC in Docker

Self-contained container running **Anki desktop** with the **AnkiConnect**
plugin and a lightweight virtual desktop (Xvfb + openbox + x11vnc + noVNC):

- connect from any browser or VNC client and use the full Anki GUI,
- click **Sync** once to attach your existing **AnkiWeb** account —
  afterwards every boot re-syncs automatically,
- drive Anki programmatically over the AnkiConnect HTTP API.

Works on `amd64` and `arm64` (incl. Apple Silicon / ARM servers).

## Quickstart

```bash
git clone https://github.com/<you>/anki-vnc.git && cd anki-vnc
docker compose up -d --build      # first run builds the image (~3-5 min)
```

Then open in a browser:

```
http://localhost:8780/vnc.html?autoconnect=1
```

Anki will already be open on the deck list. Click **Sync**, enter your
AnkiWeb email + password once — done. Your data (collection, media, login
session) persists in `./data` across container restarts and upgrades.

## Ports

| Port  | Service | Notes |
|-------|---------|-------|
| `8765` | AnkiConnect HTTP API | binds to the container's `0.0.0.0`; only reachable from the host by default |
| `5900` | VNC (x11vnc) | ⚠️ no password — use on trusted networks or via SSH tunnel |
| `8780` | noVNC web client | browser-based VNC, no client install needed |

## AnkiConnect

```bash
curl http://localhost:8765 -X POST \
  -d '{"action": "deckNames", "version": 6}'
# {"result": ["Default"], "error": null}
```

The port answers once the deck list is open (~15-40 s after start).
For remote automation, put it behind your reverse proxy / SSH tunnel, and
consider setting an API key in `data/addons21/AnkiConnect/config.json`
(`"apiKey": "..."`) — then pass `"key"` in every request.

## How a fresh boot behaves

1. `docker compose up` builds and starts Xvfb, openbox, x11vnc, noVNC, Anki.
2. On first boot the launcher seeds Anki's prefs so the interactive
   first-run wizard is skipped and the default profile **User 1** opens
   automatically (you can import/sync into it).
3. After you log into AnkiWeb once, subsequent boots auto-open the profile
   and sync unattended (AnkiConnect also comes up on its own).

## Files

- `Dockerfile` — pinned Anki release + AnkiConnect plugin + X stack
- `compose.yaml` — ports, persistence (`./data`), healthcheck
- `supervisord.conf` — process management inside the container
- `anki-launcher` — X display wait, AnkiConnect refresh, profile pick
- `seed-prefs.py` — first-run wizard skip (writes `prefs21.db`)

## Upgrading

- Anki: bump the pinned version + URL in `Dockerfile`, then
  `docker compose up -d --build`. Collections sync safely with AnkiWeb.
- AnkiConnect: bump `ANKICONNECT_VERSION` (github.com/FooSoft/anki-connect).

## Security notes

VNC on 5900 and noVNC on 8780 are unauthenticated. Options:

- restrict ports to localhost (`127.0.0.1:5900:5900`) and tunnel via SSH,
- put noVNC behind an authenticating reverse proxy,
- front the API port as above.

## Troubleshooting

- `docker logs anki-connect` and `docker exec anki-connect supervisorctl status`
- if a setup/sync dialog is showing in Anki instead of the deck list, finish it
  in the browser — everything is clickable over noVNC.
