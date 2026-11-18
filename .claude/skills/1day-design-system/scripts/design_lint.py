#!/usr/bin/env python3
"""Count hand-written design values in 1Day's SwiftUI views.

DESIGN.md says page code uses `OneDay.*` tokens, not numbers. This lists
where it doesn't: font sizes, corner radii, padding, stack spacing and hex
colors written as literals.

    design_lint.py                         summary + worst files
    design_lint.py --json                  everything, machine-readable
    design_lint.py --write-baseline FILE   save today's counts
    design_lint.py --baseline FILE         exit 1 if any file got worse

`Views/DesignSystem/` is skipped: that is where tokens become components.
A line carrying `design-lint: allow` is skipped (DESIGN.md section 7).
Exit codes: 0 ok, 1 got worse than the baseline, 2 bad usage.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

KINDS = {
    "font": re.compile(r"\.system\(size:"),
    "radius": re.compile(r"cornerRadius:\s*[0-9]"),
    "padding": re.compile(r"\.padding\((?:\s*\.[A-Za-z]+\s*,)?\s*[0-9]"),
    "spacing": re.compile(r"\bspacing:\s*[0-9]"),
    "hex": re.compile(r"\b(?:UI)?Color\(\s*hex:"),
}
ALLOW = "design-lint: allow"
SKIP_DIR = "DesignSystem"
VIEWS = Path("ios/AISetlog/Views")


def find_repo_root(start: Path) -> Path | None:
    for folder in [start, *start.parents]:
        if (folder / VIEWS).is_dir():
            return folder
    return None


def scan(views: Path) -> dict[str, dict[str, int]]:
    """{relative file: {kind: count}} for files with at least one hit."""
    counts: dict[str, dict[str, int]] = {}
    for path in sorted(views.rglob("*.swift")):
        rel = path.relative_to(views)
        if rel.parts and rel.parts[0] == SKIP_DIR:
            continue
        found = {kind: 0 for kind in KINDS}
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            if ALLOW in line:
                continue
            code = line.split("//", 1)[0]
            for kind, pattern in KINDS.items():
                found[kind] += len(pattern.findall(code))
        if any(found.values()):
            counts[rel.as_posix()] = found
    return counts


def totals(counts: dict[str, dict[str, int]]) -> dict[str, int]:
    out = {kind: 0 for kind in KINDS}
    for found in counts.values():
        for kind, n in found.items():
            out[kind] += n
    return out


def regressions(now: dict, before: dict) -> list[str]:
    """Every (file, kind) whose count went up, as readable lines."""
    worse = []
    for rel, found in sorted(now.items()):
        old = before.get(rel, {})
        for kind, n in found.items():
            if n > old.get(kind, 0):
                worse.append(f"{rel}: {kind} {old.get(kind, 0)} -> {n}")
    return worse


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, help="repo root (found from the current directory by default)")
    parser.add_argument("--json", action="store_true", help="print every count as JSON")
    parser.add_argument("--top", type=int, default=8, help="how many worst files to list")
    parser.add_argument("--baseline", type=Path, help="fail if any file is worse than this saved count")
    parser.add_argument("--write-baseline", type=Path, help="save the current counts here")
    args = parser.parse_args(argv)

    root = args.root or find_repo_root(Path.cwd()) or find_repo_root(Path(__file__).resolve())
    if root is None or not (root / VIEWS).is_dir():
        print(f"error: no {VIEWS} found; pass --root <1day repo>", file=sys.stderr)
        return 2
    counts = scan(root / VIEWS)
    total = totals(counts)

    if args.write_baseline:
        args.write_baseline.write_text(json.dumps(counts, indent=1, sort_keys=True) + "\n", encoding="utf-8")

    worse: list[str] = []
    if args.baseline:
        if not args.baseline.is_file():
            print(f"error: baseline {args.baseline} not found", file=sys.stderr)
            return 2
        worse = regressions(counts, json.loads(args.baseline.read_text(encoding="utf-8")))

    if args.json:
        print(json.dumps({"totals": total, "files": counts, "regressions": worse}, ensure_ascii=False, indent=1))
    else:
        print("hand-written values: " + ", ".join(f"{k} {v}" for k, v in total.items()))
        print(f"files with any: {len(counts)}")
        ranked = sorted(counts.items(), key=lambda item: -sum(item[1].values()))
        for rel, found in ranked[: args.top]:
            detail = " ".join(f"{k}={n}" for k, n in found.items() if n)
            print(f"  {sum(found.values()):4d}  {rel}  ({detail})")
        if args.write_baseline:
            print(f"baseline saved: {args.write_baseline}")
        if args.baseline:
            print("no file got worse" if not worse else "WORSE than baseline:")
            for line in worse:
                print(f"  {line}")
    return 1 if worse else 0


if __name__ == "__main__":
    sys.exit(main())
