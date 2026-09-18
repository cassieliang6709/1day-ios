#!/usr/bin/env python3
"""Fill a story that already exists in the simulator with real footage.

The App Store needs a screenshot of a finished film, and the simulator cannot
produce one: the fake camera writes colour bars, and the app deliberately
offers no photo-library import for clips. The only screen that shows a film
made of real video is the room demo, and that one carries a debug bar
("本地示例 · 不上传房间") that has no business being in a store screenshot.

So seed a solo story instead. The persistence format is plain:

  * `challenges.v2` in the app's UserDefaults — a JSON-encoded `[Challenge]`
  * `Documents/clips/<challenge id>/day<N>.mp4` — one file per filmed moment
    (`DiskClipFileStore`)

and `Challenge.recordedCount` is just `cards.filter { clipFileName != nil }`,
so writing the files and setting the field is the whole of "this day was
filmed". Clips are cut from `Resources/Onboarding/sample-film.mp4`, the footage
already shipping as the onboarding sample, at staggered offsets so no two
moments repeat the same shot.

Run with the app NOT running — the write goes through `defaults` so cfprefsd
does not overwrite it from cache:

    python3 seed_film.py <sim-udid> [zh|en]
"""
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
# Clock times for the seven moments, so the film's "完整的一天" timeline reads
# as a day rather than as seven takes a second apart.
HOURS = [6.5, 7.5, 8.5, 9.0, 12.5, 16.0, 17.0]
# Staggered starts in an 11.9s source, two seconds each.
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

    # `startDate` is seconds since the Apple reference date, which is what
    # JSONEncoder writes for a Date — an absolute instant, not a wall clock.
    # Going through the Unix epoch and `fromtimestamp` is what puts midnight in
    # the machine's own timezone; adding the hours to a naive
    # `APPLE_EPOCH + seconds` instead shifts every moment by the UTC offset and
    # a 6:30am wake-up renders as "14:30 – 01:00".
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

    # `simctl spawn … defaults write` looks like the right tool and is not: it
    # writes to the simulator's own preference domains, not into the app's
    # sandboxed container, so the story came back 0/7. Writing the plist works,
    # but cfprefsd holds the old copy and flushes it back over the file, so the
    # simulator has to be restarted before the app reads it.
    print("restarting simulator so cfprefsd drops its cached copy…")
    subprocess.run(["xcrun", "simctl", "shutdown", udid], capture_output=True)
    subprocess.run(["xcrun", "simctl", "boot", udid], capture_output=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
