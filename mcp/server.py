"""Anki MCP server - exposes an Anki collection via AnkiConnect as MCP tools.

Transports:
- streamable HTTP on http://<host>:8890/mcp (default; docker compose service)
- stdio via `python server.py --stdio` for local use

Environment:
    ANKICONNECT_URL  default http://anki-connect:8765
    MCP_HOST         bind address (default 0.0.0.0)
    MCP_PORT         bind port (default 8000)
"""

from __future__ import annotations

import html
import os
import re
import sys
from typing import Any

import httpx
from mcp.server.fastmcp import FastMCP

ANKICONNECT_URL = os.environ.get("ANKICONNECT_URL", "http://anki-connect:8765")

mcp = FastMCP("anki", host=os.environ.get("MCP_HOST", "0.0.0.0"), port=int(os.environ.get("MCP_PORT", "8000")))


async def _anki(action: str, **params: Any):
    payload: dict[str, Any] = {"action": action, "version": 6}
    if params:
        payload["params"] = params
    async with httpx.AsyncClient(timeout=90) as client:
        res = await client.post(ANKICONNECT_URL, json=payload)
        res.raise_for_status()
        data = res.json()
    if data.get("error"):
        raise RuntimeError(f"AnkiConnect: {data['error']}")
    return data["result"]


def _strip_html(text: str) -> str:
    text = re.sub(r"(<br\s*/?>|</div>|</p>|\n)+", "\n", text or "", flags=re.I)
    text = re.sub(r"<[^>]+>", "", text)
    return html.unescape(text).strip()


@mcp.tool()
async def deck_stats(deck_names: list[str] | None = None) -> dict:
    """Card counts / due statistics for decks. All decks when deck_names is omitted."""
    decks = list(deck_names) if deck_names else await _anki("deckNames")
    stats = await _anki("getDeckStats", decks=decks)
    return {
        s.get("name", deck_id): {
            "total_cards": s.get("total_in_deck"),
            "new": s.get("new_count"),
            "learning": s.get("learn_count"),
            "review_due": s.get("review_count"),
            "suspended": s.get("suspended_count"),
        }
        for deck_id, s in stats.items()
    }


@mcp.tool()
async def create_deck(name: str) -> str:
    """Create one or more decks (names like 'A::B::C' create the full hierarchy)."""
    await _anki("createDeck", deck=name)
    return f"Deck created: {name}"


@mcp.tool()
async def search_cards(query: str, limit: int = 20) -> list[dict]:
    """Search notes with Anki search syntax (e.g. 'deck:Japanese is:due', 'word:ism')."""
    note_ids = (await _anki("findNotes", query=query))[: max(1, int(limit))]
    if not note_ids:
        return []
    notes = await _anki("notesInfo", notes=note_ids)
    card_ids = [n["cards"][0] for n in notes if n.get("cards")]
    cards = await _anki("cardsInfo", cards=card_ids) if card_ids else []
    deck_by_card = {c["cardId"]: c.get("deckName", "?") for c in cards}
    out = []
    for n in notes:
        fields = n.get("fields", {})
        out.append(
            {
                "note_id": n.get("noteId"),
                "deck": deck_by_card.get(n.get("cards", [None])[0], "?") if n.get("cards") else "?",
                "front": _strip_html(fields.get("Front", {}).get("value", "")),
                "back": _strip_html(fields.get("Back", {}).get("value", "")),
                "tags": n.get("tags", []),
            }
        )
    return out


@mcp.tool()
async def add_note(deck: str, front: str, back: str, tags: list[str] | None = None, model: str = "Basic") -> int:
    """Add a note (HTML allowed in front/back). Uses the given note type; default 'Basic'."""
    result = await _anki(
        "addNote",
        note={
            "deckName": deck,
            "modelName": model,
            "fields": {"Front": front, "Back": back},
            "tags": tags or [],
            "options": {"allowDuplicate": True, "duplicateScope": "deck"},
        },
    )
    # AnkiConnect returns the note id as a bare int (null on failure).
    if result is None:
        raise RuntimeError("addNote failed (invalid deck or model?)")
    note_id = result if isinstance(result, int) else result.get("noteId", result)

    # Some Anki/AnkiConnect combinations ignore deckName on addNote and drop
    # the cards into the current deck (e.g. the localized default deck);
    # move them to the requested deck if they landed elsewhere.
    card_ids = await _anki("findCards", query=f"nid:{note_id}")
    if card_ids:
        cards = await _anki("cardsInfo", cards=card_ids)
        if cards and cards[0].get("deckName", "") != deck:
            await _anki("changeDeck", cards=card_ids, deck=deck)
    return note_id


@mcp.tool()
async def delete_notes(note_ids: list[int]) -> str:
    """Delete notes by id. Ask the user to confirm before calling this."""
    await _anki("deleteNotes", notes=note_ids)
    return f"Deleted {len(note_ids)} note(s)"


@mcp.tool()
async def sync_with_ankiweb() -> str:
    """Synchronize the collection with AnkiWeb."""
    await _anki("sync")
    return "Sync requested"


@mcp.tool()
async def collection_overview() -> dict:
    """Decks with card counts and what is due."""
    decks = await _anki("deckNames")
    stats = await _anki("getDeckStats", decks=decks)
    summary = {
        (s.get("name") or deck_id): {
            "total_cards": s.get("total_in_deck"),
            "new": s.get("new_count"),
            "learning": s.get("learn_count"),
            "review_due": s.get("review_count"),
        }
        for deck_id, s in stats.items()
    }
    totals = {}
    for s in summary.values():
        for k, v in s.items():
            totals[k] = totals.get(k, 0) + (v if isinstance(v, int) else 0)
    return {"decks": summary, "totals": totals}


@mcp.prompt()
def study_session(deck: str | None = None) -> str:
    """Review upcoming cards together."""
    scope = f" in deck {deck}" if deck else ""
    return f"Help me review the cards due now{scope}. Quiz me one card at a time, then correct me."


if __name__ == "__main__":
    if "--stdio" in sys.argv:
        mcp.run()  # stdio transport
    else:
        mcp.run(transport="streamable-http")
