#!/usr/bin/env python3
import base64
import json
import subprocess
import sys
from pathlib import Path

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
WIDTH, HEIGHT = 1320, 2868

PAGE = """<!doctype html><html><head><meta charset="utf-8"><style>
* {{ box-sizing:border-box; margin:0; padding:0; }}
html, body {{ width:{w}px; height:{h}px; overflow:hidden; }}
body {{ background:#FFCB45; font-family:"Arial Rounded MT Bold","Hiragino Sans GB","Hiragino Sans",sans-serif; color:#3A2B1B; position:relative; }}
.head {{ position:absolute; left:110px; right:110px; top:190px; font-size:124px; font-weight:900; line-height:1.18; letter-spacing:1px; }}
.sub {{ position:absolute; left:114px; right:110px; top:{sub_top}px; font-size:56px; font-weight:800; color:#6B4300; line-height:1.35; }}
.phone {{ position:absolute; left:210px; top:{phone_top}px; width:900px; border-radius:128px; overflow:hidden;
  border:26px solid #1d1d1d; background:#000; transform:rotate(-5deg); box-shadow:0 70px 140px rgba(0,0,0,.28); }}
.phone img {{ display:block; width:100%; }}
.pop {{ position:absolute; background:#fff; border-radius:56px; padding:30px 42px; font-size:50px; font-weight:900;
  box-shadow:0 30px 70px rgba(0,0,0,.22); display:flex; align-items:center; gap:22px; white-space:nowrap; }}
.pop .face {{ width:76px; height:76px; border-radius:50%; background:#22356e; color:#fff; font-size:38px; font-weight:900;
  display:grid; place-items:center; flex:0 0 auto; }}
</style></head><body>
<div class="head">{head}</div>
<div class="sub">{sub}</div>
<div class="phone"><img src="data:image/png;base64,{img}"></div>
{pops}
</body></html>"""


def pop_html(pop):
    face = f'<span class="face">{pop["face"]}</span>' if pop.get("face") else ""
    return f'<div class="pop" style="{pop["style"]}">{face}<span>{pop["text"]}</span></div>'


def render(shot, lang, raw_dir, out_dir):
    copy = shot[lang]
    image = base64.b64encode((raw_dir / lang / shot["raw"]).read_bytes()).decode()
    lines = copy["head"].count("<br>") + 1
    sub_top = 190 + lines * 140 + 30
    html = PAGE.format(
        w=WIDTH, h=HEIGHT, head=copy["head"], sub=copy["sub"], img=image,
        sub_top=sub_top, phone_top=sub_top + 190,
        pops="\n".join(pop_html(p) for p in copy.get("pops", [])))
    page = out_dir / f"{shot['name']}-{lang}.html"
    page.write_text(html, encoding="utf-8")
    png = out_dir / f"{shot['name']}-{lang}.png"
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    f"--window-size={WIDTH},{HEIGHT}", "--force-device-scale-factor=1",
                    f"--screenshot={png}", page.as_uri()],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    page.unlink()
    return png


def main():
    if len(sys.argv) != 4:
        print("usage: render.py shots.json raw_dir out_dir  (raw_dir/zh and raw_dir/en hold the app screenshots)")
        return 2
    shots = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    raw_dir, out_dir = Path(sys.argv[2]).resolve(), Path(sys.argv[3]).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    for shot in shots:
        for lang in ("zh", "en"):
            print(render(shot, lang, raw_dir, out_dir))
    return 0


if __name__ == "__main__":
    sys.exit(main())
