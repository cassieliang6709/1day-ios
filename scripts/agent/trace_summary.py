import argparse
import collections
import sys
import xml.etree.ElementTree as ET

APP_BINARIES = ("AISetlog", "1Day")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("xml")
    ap.add_argument("--top", type=int, default=25)
    args = ap.parse_args()

    root = ET.parse(args.xml).getroot()
    by_id = {}
    for el in root.iter():
        if "id" in el.attrib:
            by_id[el.attrib["id"]] = el

    def resolve(el):
        return by_id.get(el.attrib["ref"], el) if "ref" in el.attrib else el

    self_w = collections.Counter()
    total_w = collections.Counter()
    app_self = collections.Counter()
    app_total = collections.Counter()
    all_weight = 0
    samples = 0

    for row in root.iter("row"):
        weight_el = row.find("weight")
        weight = int(resolve(weight_el).text or 0) if weight_el is not None else 1
        bt = row.find("tagged-backtrace")
        if bt is None:
            bt = row.find("backtrace")
        if bt is None:
            continue
        bt = resolve(bt)
        frames = []
        for f in bt.findall("frame"):
            f = resolve(f)
            binary = f.find("binary")
            bname = resolve(binary).attrib.get("name", "") if binary is not None else ""
            frames.append((f.attrib.get("name", "?"), bname))
        if not frames:
            continue
        samples += 1
        all_weight += weight
        self_w[frames[0]] += weight
        for fr in set(frames):
            total_w[fr] += weight
        app_frames = [fr for fr in frames if fr[1].startswith(APP_BINARIES)]
        if app_frames:
            app_self[app_frames[0]] += weight
            for fr in set(app_frames):
                app_total[fr] += weight

    if not samples:
        print("no samples in trace (app idle, or the wrong process was traced)")
        return

    def show(title, counter):
        print(f"\n## {title}")
        for (name, binary), w in counter.most_common(args.top):
            print(f"{100 * w / all_weight:5.1f}%  {name[:110]}  [{binary}]")

    print(f"samples: {samples}, total weight: {all_weight / 1e6:.0f} ms")
    show("1Day code, total (incl. what it calls)", app_total)
    show("1Day code, topmost 1Day frame", app_self)
    show("all code, self", self_w)


if __name__ == "__main__":
    sys.exit(main())
