#!/usr/bin/env python3
from __future__ import annotations

import json
import plistlib
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

BUNDLE = "com.cassie.AISetlog"
APPLE_EPOCH = datetime(2001, 1, 1)
SOURCE = Path(__file__).resolve().parents[3] / "AISetlog/Resources/Onboarding/sample-film.mp4"

CAPTIONS = {
    "zh": ["天刚亮", "第一口", "今天穿这件", "出门了", "正午的光", "回家路上", "今天就这样"],
    "en": ["Just light out", "First sip", "This one today", "Out the door",
           "Midday light", "On the way home", "That was today"],
}
HOURS = [6.5, 7.5, 8.5, 9.0, 12.5, 16.0, 17.0]
OFFSETS = [0.0, 1.6, 3.2, 4.8, 6.4, 8.0, 9.6]


def run(*args: str) -> str:
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout.strip()


def main() -> int:
    udid = sys.argv[1]
    lang = sys.argv[2] if len(sys.argv) > 2 else "zh"
    captions = CAPTIONS[lang]

    container = Path(run("xcrun", "simctl", "get_app_container", udid, BUNDLE, "data"))
    prefs = container / "Library/Preferences" / f"{BUNDLE}.plist"
    with prefs.open("rb") as fh:
        defaults = plistlib.load(fh)

    challenges = json.loads(defaults["challenges.v2"])
    if not challenges:
        print("no story in challenges.v2 — create one in the app first")
        return 1
    story = challenges[0]
    cid = story["id"]
    print(f"story {story['title']} ({cid}) with {len(story['cards'])} cards")

    clips = container / "Documents/clips" / cid
    clips.mkdir(parents=True, exist_ok=True)

    unix_offset = (APPLE_EPOCH - datetime(1970, 1, 1)).total_seconds()
    start_local = datetime.fromtimestamp(story["startDate"] + unix_offset)
    midnight = start_local.replace(hour=0, minute=0, second=0, microsecond=0)

    for index, card in enumerate(story["cards"]):
        name = f"day{card['day']}.mp4"
        subprocess.run(
            ["ffmpeg", "-y", "-ss", str(OFFSETS[index % len(OFFSETS)]),
             "-i", str(SOURCE), "-t", "2", "-an",
             "-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", "veryfast",
             str(clips / name)],
            capture_output=True, check=True,
        )
        card["clipFileName"] = name
        card["recordedAt"] = (
            midnight + timedelta(hours=HOURS[index % len(HOURS)])
        ).timestamp() - unix_offset
        card["overlayText"] = captions[index % len(captions)]
        print(f"  day{card['day']}  {name}  {card['overlayText']}")

    payload = json.dumps(challenges, ensure_ascii=False, separators=(",", ":")).encode()
    defaults["challenges.v2"] = payload
    with prefs.open("wb") as fh:
        plistlib.dump(defaults, fh)
    print(f"wrote {len(payload)} bytes to challenges.v2")

    print("restarting simulator so cfprefsd drops its cached copy…")
    subprocess.run(["xcrun", "simctl", "shutdown", udid], capture_output=True)
    subprocess.run(["xcrun", "simctl", "boot", udid], capture_output=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
