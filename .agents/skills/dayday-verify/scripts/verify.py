#!/usr/bin/env python3
"""Project-local checks. Static success is never native verification."""

import argparse
from collections import Counter
import json
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
SUITES = {
    "avatar": ["MemberProfileSyncTests"],
    "media": ["LocalRoomMediaKeyTests", "RoomClipCacheTests",
              "RoomPreviewMediaScopeTests", "VideoStitcherTests"],
    "rooms": ["RoomSyncLifecycleTests", "RoomUploadRetryTests"],
    "ui": ["CaptureReviewUITests", "RoomNavigationUITests"],
}


def output(*command):
    return subprocess.check_output(command, cwd=ROOT, text=True).strip()


def doctor():
    missing = [name for name in ("xcodebuild", "xcrun", "xcodegen") if not shutil.which(name)]
    if platform.system() != "Darwin" or missing:
        print(f"NATIVE UNAVAILABLE: host={platform.system()}, missing={','.join(missing) or 'macOS'}")
        return 2
    version = output("xcodebuild", "-version")
    print(version)
    if not re.search(r"^Xcode 26\.2(?:\s|$)", version):
        print("NATIVE UNAVAILABLE: repository validation is pinned to Xcode 26.2")
        return 2
    print("Native prerequisites found; app behavior is not yet verified")
    return 0


def static_checks(base):
    base = base or output("git", "merge-base", "HEAD", "origin/main")
    subprocess.run(["git", "diff", "--check", base], cwd=ROOT, check=True)
    tracked = set(output("git", "ls-tree", "-r", "--name-only", base).splitlines())
    violations = []
    debt = []
    for directory, pattern in (
        ("Models", r"Strings\."),
        ("Presentation", r"^\s*import SwiftUI\b|\.now\b"),
    ):
        for file in sorted((ROOT / "ios/AISetlog" / directory).rglob("*.swift")):
            name = file.relative_to(ROOT).as_posix()
            old = output("git", "show", f"{base}:{name}") if name in tracked else ""
            current = re.findall(pattern, file.read_text(), re.MULTILINE)
            previous = re.findall(pattern, old, re.MULTILINE)
            if Counter(current) - Counter(previous):
                violations.append(name)
            elif current:
                debt.append(name)
    for name in debt:
        print(f"EXISTING BOUNDARY DEBT: {name}")
    for name in violations:
        print(f"NEW BOUNDARY VIOLATION: {name}")
    print("Static diff/boundary checks: " + ("FAILED" if violations else "PASSED"))
    print("Swift type checking, XCTest, screenshots and performance traces: NOT RUN")
    return 1 if violations else 0


def native_tests(target, device):
    if doctor():
        return 2
    inventory = json.loads(output("xcrun", "simctl", "list", "devices", "available", "--json"))
    candidates = []
    for runtime, devices in inventory["devices"].items():
        if ".iOS-" not in runtime:
            continue
        version = tuple(map(int, re.findall(r"\d+", runtime.split(".iOS-")[1])))
        for item in devices:
            if item.get("isAvailable") and item["name"].startswith("iPhone"):
                candidates.append((version, item["udid"]))
    if device and device not in [item[1] for item in candidates]:
        print("NATIVE UNAVAILABLE: requested iPhone simulator is not available")
        return 2
    if not candidates:
        print("NATIVE UNAVAILABLE: no available iPhone simulator; none was created")
        return 2
    device = device or max(candidates)[1]
    artifacts = Path(tempfile.mkdtemp(prefix="dayday-verify-"))
    result = artifacts / "Tests.xcresult"
    print(f"Artifacts: {artifacts}", flush=True)
    subprocess.run(["xcodegen", "generate", "--spec", "project.yml"], cwd=ROOT / "ios", check=True)
    bundle = "AISetlogUITests" if target == "ui" else "AISetlogTests"
    command = ["xcodebuild", "test", "-project", "AISetlog.xcodeproj", "-scheme", "AISetlog",
               "-destination", f"id={device}", "-derivedDataPath", str(artifacts / "DerivedData"),
               "-resultBundlePath", str(result), "-jobs", "2", "CODE_SIGNING_ALLOWED=NO"]
    command += [f"-only-testing:{bundle}/{suite}" for suite in SUITES[target]]
    run = subprocess.run(command, cwd=ROOT / "ios")
    if run.returncode:
        return run.returncode
    summary = json.loads(output("xcrun", "xcresulttool", "get", "test-results", "summary",
                                "--path", str(result)))
    (artifacts / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    passed = summary.get("passedTests")
    failed = summary.get("failedTests")
    if not isinstance(passed, int) or not isinstance(failed, int) or passed + failed == 0:
        print("NOT VERIFIED: no executed tests confirmed by the current result bundle")
        return 1
    print(f"Executed tests: passed={passed}, failed={failed}, skipped={summary.get('skippedTests')}")
    return 1 if failed else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("doctor")
    static = commands.add_parser("static")
    static.add_argument("--base", help="Git baseline; defaults to merge-base with origin/main")
    test = commands.add_parser("test")
    test.add_argument("--target", choices=SUITES, required=True)
    test.add_argument("--device", help="UDID of an existing available iPhone simulator")
    args = parser.parse_args()
    if args.command == "doctor":
        return doctor()
    if args.command == "static":
        return static_checks(args.base)
    return native_tests(args.target, args.device)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)
    except (OSError, ValueError, KeyError) as error:
        print(f"VERIFICATION ERROR: {error}", file=sys.stderr)
        sys.exit(2)
