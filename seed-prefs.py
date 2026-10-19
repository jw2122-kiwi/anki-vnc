#!/usr/bin/env python3
"""Seed a minimal Anki prefs21.db that skips the first-run language/wizard."""
import pickle, sqlite3, sys, time, random

db = sys.argv[1]
con = sqlite3.connect(db)
con.execute(
    "CREATE TABLE IF NOT EXISTS profiles "
    "(name text primary key collate nocase, data blob not null)"
)
con.execute(
    "INSERT OR IGNORE INTO profiles VALUES ('_global', ?)",
    (
        pickle.dumps(
            {
                "ver": 0,
                "updates": True,
                "created": int(time.time()),
                "id": random.getrandbits(60),
                "lastMsg": 0,
                "suppressUpdate": False,
                "firstRun": False,
                "defaultLang": "en_US",
            }
        ),
    ),
)
con.commit()
con.close()
print("seeded", db)
