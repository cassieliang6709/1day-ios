#!/usr/bin/env python3
"""Read-only look at 1Day's live D1 database, as evidence that an action on
the phone reached the server.

    d1_read.py recent [MINUTES]     rows written in the last N minutes (default 10)
    d1_read.py room CODE            how many rows each table has for one room
    d1_read.py sql "SELECT …"       any single read-only query

Runs `wrangler d1 execute oneday --remote --json` from workers/api. Refuses
anything that isn't one SELECT/WITH statement. Mood diary text is never
selected by the presets: it is private to its owner.
Exit codes: 0 ok, 1 wrangler or query failed, 2 bad usage.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
import time
from pathlib import Path

DATABASE = "oneday"
WORKER_DIR = Path("workers/api")
CODE = re.compile(r"^[A-Z0-9]{4,12}$")

# One statement per table: D1 refuses a UNION of this many SELECTs.
RECENT = [
    "SELECT 'room' AS kind, code AS id, owner_id AS who, created_at AS at FROM rooms WHERE created_at > {since}",
    "SELECT 'member' AS kind, id, user_id AS who, updated_at AS at FROM members WHERE updated_at > {since}",
    "SELECT 'clip' AS kind, id, author_id AS who, updated_at AS at FROM clips WHERE updated_at > {since}",
    "SELECT 'reaction' AS kind, id, author_id AS who, created_at AS at FROM reactions WHERE created_at > {since}",
    "SELECT 'comment' AS kind, id, author_id AS who, created_at AS at FROM comments WHERE created_at > {since}",
    "SELECT 'poke' AS kind, id, author_id AS who, created_at AS at FROM pokes WHERE created_at > {since}",
    "SELECT 'mood' AS kind, day AS id, user_id AS who, updated_at AS at FROM moods WHERE updated_at > {since}",
    "SELECT 'device' AS kind, substr(token, 1, 8) AS id, user_id AS who, updated_at AS at FROM devices WHERE updated_at > {since}",
]

ROOM = """
SELECT
 (SELECT COUNT(*) FROM rooms WHERE code = '{code}') AS room,
 (SELECT COUNT(*) FROM members WHERE room_code = '{code}') AS members,
 (SELECT COUNT(*) FROM clips WHERE room_code = '{code}') AS clips,
 (SELECT COUNT(*) FROM reactions WHERE room_code = '{code}') AS reactions,
 (SELECT COUNT(*) FROM comments WHERE room_code = '{code}') AS comments,
 (SELECT COUNT(*) FROM pokes WHERE room_code = '{code}') AS pokes,
 (SELECT COUNT(*) FROM device_rooms WHERE room_code = '{code}') AS push_devices
"""


def find_worker_dir(start: Path) -> Path | None:
    for folder in [start, *start.parents]:
        if (folder / WORKER_DIR / "wrangler.toml").is_file():
            return folder / WORKER_DIR
    return None


def is_read_only(sql: str) -> bool:
    body = sql.strip().rstrip(";").strip()
    if ";" in body:
        return False
    return re.match(r"(?is)^\s*(select|with)\b", body) is not None and not re.search(
        r"(?i)\b(insert|update|delete|drop|alter|create|replace|attach|pragma|vacuum)\b", body)


def build_sql(argv: list[str]) -> list[str] | None:
    """The statements to run. Presets are fixed text; only `sql` takes the
    caller's query, and that one has to pass `is_read_only`."""
    if not argv:
        return None
    command, rest = argv[0], argv[1:]
    if command == "recent":
        minutes = int(rest[0]) if rest and rest[0].isdigit() else 10
        since = int((time.time() - minutes * 60) * 1000)
        return [q.format(since=since) for q in RECENT]
    if command == "room" and len(rest) == 1 and CODE.match(rest[0]):
        return [ROOM.format(code=rest[0])]
    if command == "sql" and len(rest) == 1:
        return [rest[0]]
    return None


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    statements = build_sql(argv)
    if statements is None:
        print(__doc__, file=sys.stderr)
        return 2
    if not all(is_read_only(sql) for sql in statements):
        print("error: only one SELECT/WITH statement is allowed", file=sys.stderr)
        return 2
    worker = find_worker_dir(Path.cwd()) or find_worker_dir(Path(__file__).resolve())
    if worker is None:
        print("error: workers/api/wrangler.toml not found; run from the 1day repo", file=sys.stderr)
        return 2
    command = ["npx", "--no-install", "wrangler", "d1", "execute", DATABASE,
               "--remote", "--json", "--command", "; ".join(" ".join(q.split()) for q in statements)]
    result = subprocess.run(command, cwd=worker, capture_output=True, text=True)
    try:
        rows = [row for part in json.loads(result.stdout) for row in part["results"]]
    except (ValueError, LookupError, TypeError):
        tail = (result.stderr or result.stdout).strip().splitlines()[-5:]
        print("error: wrangler failed:\n  " + "\n  ".join(tail), file=sys.stderr)
        return 1
    if argv[0] == "recent":
        rows.sort(key=lambda row: -row["at"])
        for row in rows:
            row["at"] = time.strftime("%m-%d %H:%M:%S", time.localtime(row["at"] / 1000))
    for row in rows:
        print(json.dumps(row, ensure_ascii=False))
    if not rows:
        print("(no rows)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
