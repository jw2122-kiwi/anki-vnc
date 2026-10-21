# Anki Web + VNC in Docker

Self-contained container running **Anki desktop** with the **AnkiConnect**
plugin and a lightweight virtual desktop (Xvfb + openbox + x11vnc + noVNC):

- connect from any browser or VNC client and use the full Anki GUI,
- click **Sync** once to attach your existing **AnkiWeb** account —
  afterwards every boot re-syncs automatically,
- drive Anki programmatically over the AnkiConnect HTTP API.

Built on **Alpine Linux** — the image is ~1.5 GB and the container idles at
~300 MB RAM, about half of the equivalent Ubuntu-based image.

Works on `amd64` and `arm64` (incl. Apple Silicon / ARM servers).

## Quickstart

```bash
git clone https://github.com/jw2122-kiwi/anki-vnc.git && cd anki-vnc
docker compose up -d --build      # first run builds the image (~2-4 min)
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
| `8890` | **MCP server** (streamable HTTP) | endpoint `/mcp`, exposes the collection to AI clients |

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

- `Dockerfile` — Alpine base + `anki` package (bundles PyQt6/QtWebEngine),
  AnkiConnect plugin, X stack, fonts
- `compose.yaml` — services (Anki desktop, MCP server), ports, persistence
  (`./data`), healthcheck
- `mcp/` — MCP server bridging AnkiConnect (`server.py`)
- `s6-rc.d/`, `user-bundles.d/` — process management inside the container
  (s6-overlay, Alpine's native supervisor)
- `anki-launcher` — X display wait, AnkiConnect refresh, profile pick
- `seed-prefs.py` — first-run wizard skip (writes `prefs21.db`)
- `.github/workflows/` — `build.yml` (two-arch images on every push),
  `update.yml` (weekly dependency-bump PR)

## Optional fonts

Language fonts are **build args and disabled by default**. Most deployments
only use the AnkiConnect API and the MCP server and never render a card, so
the fonts would be pure overhead — the CJK set alone is 88 MB.

Enable only what your collection needs, in `compose.yaml` or a `.env` file:

```sh
# .env
FONT_ARABIC=true
```

| Flag | Package | Size | Languages |
| --- | --- | --- | --- |
| `FONT_ARABIC` | `font-noto-arabic` | 18 MB | Arabic, Persian, Urdu |
| `FONT_CJK` | `font-noto-cjk` | 88 MB | Chinese, Japanese, Korean |
| `FONT_DEVANAGARI` | `font-noto-devanagari` | 26 MB | Hindi, Nepali, Sanskrit |
| `FONT_BENGALI` | `font-noto-bengali` | 18 MB | Bengali, Assamese |
| `FONT_THAI` | `font-noto-thai` | 5 MB | Thai |
| `FONT_HEBREW` | `font-noto-hebrew` | 2 MB | Hebrew |
| `FONT_SYMBOLS` | `font-noto-symbols` | 3 MB | symbols, arrows |
| `FONT_MATH` | `font-noto-math` | 1 MB | mathematical notation |

A flag change needs a rebuild:

```sh
docker compose up -d --build
```

Check which fonts ended up in the image:

```sh
docker exec anki-lite fc-list | wc -l
docker exec anki-lite fc-list :lang=ar
```

Without the matching font, cards in that script render as empty boxes.

## MCP server (AI assistants)

The `mcp` service (in `./mcp`) bridges AnkiConnect into the
[Model Context Protocol](https://modelcontextprotocol.io): your AI client can
list decks, search cards, add notes, and trigger AnkiWeb sync.

Streamable HTTP endpoint:

```
http://<host>:8890/mcp
```

For clients that only support stdio transport, bridge with
[`mcp-remote`](https://github.com/geelen/mcp-remote):

```json
{
  "mcpServers": {
    "anki": { "command": "npx", "args": ["-y", "mcp-remote", "http://localhost:8890/mcp"] }
  }
}
```

Tools: `collection_overview`, `deck_stats`, `create_deck`, `search_cards`,
`add_note`, `delete_notes`, `sync_with_ankiweb` — plus a `study_session`
prompt. The server is unauthenticated; protect port 8890 like the rest.

## Alpine specifics

The image uses Alpine's own `anki` package, not the upstream Linux tarball
(that one is glibc-linked and cannot run on musl). Consequences:

- **Anki version** tracks the Alpine package (currently 26.08.1) and can lag
  behind the [upstream release](https://github.com/ankitects/anki/releases).
  Rebuild the image to pick up a newer package.
- **Process supervision** uses s6-overlay rather than `supervisor`, which is
  not packaged for Alpine.
- **`localhost` resolves to `::1` first**, and AnkiConnect binds IPv4 only —
  the healthcheck therefore targets `127.0.0.1`.
- **`/dev/shm` is raised to 256 MB** (`shm_size` in `compose.yaml`); Chromium
  needs more than Docker's 64 MB default.
- **Fonts**: `font-noto` is always installed. The language fonts are optional
  build args, see [Optional fonts](#optional-fonts).
- **HTTPS**: `py3-truststore` is required, otherwise Anki cannot use the
  system certificate store and the AnkiWeb sync is not safe.

## Automated updates

A scheduled workflow (`.github/workflows/update.yml`, Mondays 06:00 UTC)
compares the pinned AnkiConnect version in the `Dockerfile` against the latest
[AnkiConnect](https://github.com/FooSoft/anki-connect/releases) release and
opens a PR when it is outdated. The `anki` version itself is not pinned — it
comes from the Alpine package repo and is updated by rebuilding. Merging a PR
triggers the multi-arch build workflow; rebuild your deployment with
`docker compose up -d --build`. Run it on demand via
*Actions → update-deps → Run workflow*.

## Security notes

VNC on 5900 and noVNC on 8780 are unauthenticated. Options:

- restrict ports to localhost (`127.0.0.1:5900:5900`) and tunnel via SSH,
- put noVNC behind an authenticating reverse proxy,
- front the API port as above.

## Troubleshooting

- `docker logs anki-lite` and
  `docker exec anki-lite s6-svstat /run/service/anki-launcher`
- if a setup/sync dialog is showing in Anki instead of the deck list, finish it
