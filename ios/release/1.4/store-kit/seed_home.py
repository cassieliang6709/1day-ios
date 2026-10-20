#!/usr/bin/env python3
"""Give the home screen more than one story to show.

`capture.sh` shoots 02-home straight after onboarding, so it shows the empty
state — a mascot and "No story yet today". That is honest and it is also the
least interesting screen in the app: a store page's job is to show what the
thing looks like once someone is using it.

So this runs *after* `seed_film.py` and adds two more stories beside the
finished one, in the two states the list is actually built to show:

  * a shared room, part-filmed — `Challenge.isShared` is just `roomCode != nil`
  * a solo story from yesterday, part-filmed

Everything is real app data in the app's own format; nothing is drawn on. The
moment keys are copied from the real templates (`ChallengeTemplate.swift`) so
each story's cover, title and moment names agree with each other — cloning
Perfect Day's moments under a Cook With Me cover would look right on home and
wrong the moment anyone tapped it.

Run with the app NOT running, same as seed_film.py, and for the same reason:
the write goes through the container's plist and cfprefsd caches it.

    python3 seed_home.py <sim-udid> [zh|en]
"""
from __future__ import annotations

import json
import plistlib
import subprocess
import sys
import uuid
from datetime import datetime, timedelta
from pathlib import Path

BUNDLE = "com.cassie.AISetlog"
APPLE_EPOCH = datetime(2001, 1, 1)
SOURCE = Path(__file__).resolve().parents[3] / "AISetlog/Resources/Onboarding/sample-film.mp4"
OFFSETS = [0.0, 1.6, 3.2, 4.8, 6.4, 8.0, 9.6]

# (templateName, title en/zh, momentKeys, filled, days_ago, roomCode, ownerName)
EXTRAS = [
    (
        "Little Adventure",
        {"en": "Little Adventure", "zh": "出门冒险"},
        ["heading_out", "first_stop", "street_snack", "found_a_spot",
         "people_watching", "golden_light", "back_home"],
        4, 0, "K7M2QX", {"en": "Cassie", "zh": "Cassie"},
    ),
    (
        "Cook With Me",
        {"en": "Cook With Me", "zh": "和我做饭"},
        ["ingredients", "prep", "the_sizzle", "taste_test",
         "plate_it", "first_bite", "clean_up"],
        3, 1, None, None,
    ),
]


def run(*args: str) -> str:
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout.strip()


def main() -> int:
    udid = sys.argv[1]
    lang = sys.argv[2] if len(sys.argv) > 2 else "zh"

    container = Path(run("xcrun", "simctl", "get_app_container", udid, BUNDLE, "data"))
    prefs = container / "Library/Preferences" / f"{BUNDLE}.plist"
    with prefs.open("rb") as fh:
        defaults = plistlib.load(fh)

    challenges = json.loads(defaults["challenges.v2"])
    if not challenges:
        print("no story in challenges.v2 — run capture.sh first")
        return 1

    base = challenges[0]
    unix_offset = (APPLE_EPOCH - datetime(1970, 1, 1)).total_seconds()
    base_start = datetime.fromtimestamp(base["startDate"] + unix_offset)

    for template, titles, keys, filled, days_ago, room, owner in EXTRAS:
        cid = str(uuid.uuid4()).upper()
        start = base_start - timedelta(days=days_ago)
        midnight = start.replace(hour=0, minute=0, second=0, microsecond=0)

        clips = container / "Documents/clips" / cid
        clips.mkdir(parents=True, exist_ok=True)

        cards = []
        for index in range(len(keys)):
            card = {"day": index + 1, "reactions": [], "comments": []}
            if index < filled:
                name = f"day{index + 1}.mp4"
                subprocess.run(
                    ["ffmpeg", "-y", "-ss", str(OFFSETS[index % len(OFFSETS)]),
                     "-i", str(SOURCE), "-t", "2", "-an",
                     "-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", "veryfast",
                     str(clips / name)],
                    capture_output=True, check=True,
                )
                card["clipFileName"] = name
                card["recordedAt"] = (
                    midnight + timedelta(hours=7 + index * 1.5)
                ).timestamp() - unix_offset
            cards.append(card)

        story = {
            "id": cid,
            "cards": cards,
            "templateName": template,
            "clipLength": base["clipLength"],
            "title": titles[lang],
            "startDate": start.timestamp() - unix_offset,
            "momentTitles": keys,
            "mode": "oneDay",
            "orientation": "portrait",
        }
        if room:
            story["roomCode"] = room
            story["ownerName"] = owner[lang]
        challenges.append(story)
        kind = f"room {room}" if room else "solo"
        print(f"  + {story['title']}  {filled}/{len(keys)}  {kind}")

    payload = json.dumps(challenges, ensure_ascii=False, separators=(",", ":")).encode()
    defaults["challenges.v2"] = payload
    with prefs.open("wb") as fh:
        plistlib.dump(defaults, fh)
    print(f"wrote {len(payload)} bytes to challenges.v2 ({len(challenges)} stories)")

    print("restarting simulator so cfprefsd drops its cached copy…")
    subprocess.run(["xcrun", "simctl", "shutdown", udid], capture_output=True)
    subprocess.run(["xcrun", "simctl", "boot", udid], capture_output=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
