#!/usr/bin/env python3
"""Builds the copy table Cassie edits by hand: `docs/1day-copy.csv` and
`docs/1day-copy-editor.html`.

Source of truth is `Strings` in Localization.swift. Everything else this script
touches is an annotation on top of it:

- which page a string shows up on, scanned out of the view files
- `docs/1day-copy-notes.json`: hand-written per-key notes, the two entries whose
  English the literal scanner cannot read whole, and which strings are small
  print that could be deleted outright rather than reworded
- the rewrite options from `docs/1day-copy-rewrites.json`
- her own edits so far, from `docs/1day-copy-edits.json`, pre-filled back in

Run it after editing Localization.swift:

    python3 scripts/build-copy-editor.py
"""

from __future__ import annotations

import csv
import json
import pathlib
import re
import collections

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "ios/AISetlog/Resources/Localization/Localization.swift"
APP = ROOT / "ios/AISetlog"
CSV_OUT = ROOT / "docs/1day-copy.csv"
HTML_OUT = ROOT / "docs/1day-copy-editor.html"
REWRITES = ROOT / "docs/1day-copy-rewrites.json"
EDITS = ROOT / "docs/1day-copy-edits.json"
NOTES = ROOT / "docs/1day-copy-notes.json"

# Which page / moment each file is. Read off the view hierarchy once, by hand,
# because a file name alone ("StoryPieces.swift") does not tell her anything.
SCENES = {
    "Views/Plans/PlansHomeView.swift": "首页",
    "Views/Components/StoryCard.swift": "首页 · 故事卡片",
    "Views/Components/TimelineClip.swift": "故事页 · 时间线上的片段",
    "Views/Components/TemplateCard.swift": "新建故事 · 题目卡片",
    "Views/Components/TemplateCoverPicker.swift": "题目封面选择",
    "Views/Components/AvatarStack.swift": "头像",
    "Views/Components/VlogPlayer.swift": "播放器",
    "Views/RootShellView.swift": "底部标签栏（计划 / 拍摄）",
    "Views/Home/FirstRunOnboardingView.swift": "第一次打开的引导页",
    "Views/Home/JoinInviteSheet.swift": "输邀请码加入房间",
    "Views/Home/BuildTemplateView.swift": "自己建题目模板",
    "Views/Compose/StoryComposerView.swift": "新建故事",
    "Views/Compose/ComposerSteps.swift": "新建故事 · 海报和设置",
    "Views/Compose/GuidedMomentsView.swift": "自己写题目（AI 写瞬间）",
    "Views/Record/RecordClipView.swift": "拍摄页",
    "Views/Record/CameraComponents.swift": "拍摄页 · 相机上的控件",
    "Views/Record/ClipPreviewView.swift": "回看页（拍完看这一段）",
    "Views/Record/ClipPreviewComponents.swift": "回看页 · 表情和留言",
    "Views/Record/ClipDeckReview.swift": "回看页 · 左右翻看",
    "Views/Record/ClipDraftsView.swift": "草稿箱",
    "Views/Record/LookPanel.swift": "回看页 · 调色面板",
    "Views/Timeline/StoryTimelineView.swift": "故事页",
    "Views/Timeline/TimelineHeader.swift": "故事页 · 顶部",
    "Views/Timeline/StoryPieces.swift": "故事页 · 各行卡片",
    "Views/Timeline/StoryCoverSheet.swift": "故事页 · 换封面",
    "Views/Timeline/StoryGridView.swift": "故事页 · 九宫格",
    "Views/Timeline/RoomChatView.swift": "瞬间聊天",
    "Views/Timeline/RoomRoster.swift": "故事页 · 房间成员",
    "Views/Timeline/LocalRoomDemoView.swift": "房间演示（调试用）",
    "Views/Timeline/LocalRoomImportControls.swift": "房间演示（调试用）",
    "Views/Film/FilmView.swift": "成片页",
    "Views/Film/FinalFilmTimeline.swift": "成片页 · 底部按钮",
    "Views/Film/GeneratingFilm.swift": "成片生成中",
    "Views/Film/AdjustFilmSheet.swift": "成片页 · 调整",
    "Views/Settings/SettingsView.swift": "设置页「我」",
    "Views/Settings/SignInView.swift": "登录",
    "Views/Settings/NotificationPrimerView.swift": "第一次开通知的说明页",
    "Views/Settings/RoomNotificationsView.swift": "设置 · 按房间管通知",
    "Views/Settings/SettingsOptionPage.swift": "设置 · 外观 / 语言",
    "Views/Board/BoardTheme.swift": "房间看板",
    "Services/ReminderService.swift": "晚间提醒的手机通知",
    "Services/Notifications/SharedActivityNotificationService.swift": "好友动态的手机通知",
    "Services/Cloud/CloudKitService.swift": "房间同步失败时的报错",
    "Services/ChallengeStore.swift": "出错提示",
    "Services/PromptSuggestionService.swift": "AI 写瞬间失败时的提示",
    "Presentation/ChallengePresenter.swift": "故事标题 / 瞬间名的组装",
    "Presentation/RoomCast.swift": "房间成员名字的组装",
    "Presentation/StorySchedule.swift": "时长和日期的组装",
    "Models/ChallengeTemplate.swift": "内置题目的名字",
}

CJK = re.compile(r"[　-〿一-鿿＀-￯]")


def literals(block: str) -> list[str]:
    """String literals in a `Strings` entry, in source order."""
    out, i = [], 0
    while i < len(block):
        if block[i] == '"':
            j, buf = i + 1, []
            while j < len(block) and block[j] != '"':
                if block[j] == "\\" and j + 1 < len(block):
                    buf.append(block[j : j + 2])
                    j += 2
                    continue
                buf.append(block[j])
                j += 1
            out.append("".join(buf))
            i = j + 1
            continue
        i += 1
    return out


def entries() -> list[dict]:
    """Every `Strings` member, with its MARK group and doc comment."""
    text = SRC.read_text(encoding="utf-8")
    start = text.index("enum Strings {")
    # Stop at the enum's closing brace: the file has helper types after it whose
    # members are not copy.
    end = text.index("\n}", start)
    lines = text[start:end].splitlines()

    rows, group, doc = [], "Common", []
    i = 0
    while i < len(lines):
        line = lines[i]
        mark = re.match(r"\s*// MARK:\s*(.+)", line)
        if mark:
            group = mark.group(1).strip()
            doc = []
            i += 1
            continue
        if re.match(r"\s*///", line):
            doc.append(re.sub(r"\s*///\s?", "", line).strip())
            i += 1
            continue
        # `private` members are plumbing that other entries call (name lists,
        # plural helpers); their text reaches the screen through the public one.
        member = re.match(r"\s{4}static\s+(?:var|func)\s+(\w+)", line)
        if not member:
            if line.strip():
                doc = []
            i += 1
            continue

        # Take the whole declaration: a one-liner, or up to the closing brace
        # at the member's indentation.
        chunk = [line]
        if not (line.count("{") == line.count("}") and line.rstrip().endswith("}")):
            j = i + 1
            while j < len(lines) and lines[j] != "    }":
                chunk.append(lines[j])
                j += 1
            i = j
        lits = literals("\n".join(chunk))
        zh = next((s for s in lits if CJK.search(s)), "")
        en = next((s for s in lits if not CJK.search(s) and s.strip()), "")
        if zh or en:
            rows.append(
                {
                    "k": member.group(1),
                    "zh": zh,
                    "en": en,
                    "ph": "\\(" in zh or "\\(" in en,
                    "g": group,
                    "note": " ".join(doc),
                }
            )
        doc = []
        i += 1
    return rows


def where_used(keys: list[str]) -> dict[str, str]:
    hits = collections.defaultdict(list)
    patterns = {k: re.compile(r"Strings\." + k + r"\b") for k in keys}
    for path in APP.rglob("*.swift"):
        if "Localization" in path.name:
            continue
        text = path.read_text(encoding="utf-8")
        rel = str(path.relative_to(APP))
        for key, pattern in patterns.items():
            if pattern.search(text):
                hits[key].append(rel)

    out = {}
    for key in keys:
        files = hits.get(key, [])
        if not files:
            out[key] = "间接引用（拼在别的文案里）"
            continue
        names, seen = [], set()
        for f in files:
            name = SCENES.get(f) or f.split("/")[-1].removesuffix(".swift")
            if name not in seen:
                seen.add(name)
                names.append(name)
        out[key] = " / ".join(names[:3]) + ("" if len(names) <= 3 else f" 等 {len(names)} 处")
    return out


def build() -> list[dict]:
    rows = entries()
    notes = json.loads(NOTES.read_text(encoding="utf-8"))

    # The one entry that is two sentences in one function: the else branch shows
    # when nothing has been filmed yet, and she needs to edit it separately.
    for extra in notes["extra"]:
        row = {
            "k": extra["k"], "zh": extra["zh"], "en": extra["en"],
            "ph": "\\(" in extra["zh"] or "\\(" in extra["en"],
            "g": extra["g"], "note": extra["note"], "branchOf": extra["after"],
        }
        at = next((i for i, r in enumerate(rows) if r["k"] == extra["after"]), len(rows) - 1)
        rows.insert(at + 1, row)

    scenes = where_used([r["k"] for r in rows])
    rewrites = json.loads(REWRITES.read_text(encoding="utf-8"))
    edits = {e["key"]: e for e in json.loads(EDITS.read_text(encoding="utf-8"))["edits"]}

    for row in rows:
        hand = notes["rows"].get(row["k"], {})
        # An entry whose English interpolates a quoted string reads as
        # truncated to the literal scanner; the sidecar carries the whole one.
        row["en"] = hand.get("en", row["en"])
        row["note"] = hand.get("note") or row["note"]
        row["lockEn"] = bool(hand.get("lockEn"))
        row["opt"] = bool(hand.get("optional"))
        parent = row.get("branchOf")
        row["s"] = scenes[parent] if parent else scenes[row["k"]]
        row["o"] = rewrites.get(row["k"], [])
        mine = edits.get(row["k"])
        if mine:
            row["mine"] = {k: v for k, v in mine.items() if k in ("zh", "en")}
    return rows


# MARK: - Output


def write_csv(rows: list[dict]) -> None:
    with CSV_OUT.open("w", newline="", encoding="utf-8-sig") as fh:
        w = csv.writer(fh)
        w.writerow(
            ["键名", "中文（改这一列）", "English（改这一列）", "占位符（别改）",
             "分组", "用在哪一页", "说明"]
        )
        for r in rows:
            zh = r.get("mine", {}).get("zh", r["zh"])
            en = r.get("mine", {}).get("en", r["en"])
            w.writerow([r["k"], zh, en, "YES" if r["ph"] else "", r["g"], r["s"], r["note"]])


PAGE = """<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>1Day 文案表 · __N__ 条</title>
<style>
  :root{color-scheme:light;--plane:#f9f9f7;--surface:#fff;--line:#e3e2db;
        --ink:#111;--soft:#5d5c57;--faint:#93918a;--blue:#1677ff;--warn:#b5610a;--done:#0ca30c}
  @media (prefers-color-scheme:dark){:root{--plane:#101010;--surface:#191919;--line:#2d2d2b;
        --ink:#f4f4f2;--soft:#b9b8b0;--faint:#7d7c76}}
  *{box-sizing:border-box}
  body{margin:0;font:14px/1.55 system-ui,-apple-system,sans-serif;background:var(--plane);color:var(--ink)}
  header{position:sticky;top:0;z-index:5;background:var(--plane);border-bottom:1px solid var(--line);padding:14px 20px 12px}
  h1{font-size:19px;margin:0 0 3px;font-weight:800}
  .sub{font-size:13px;color:var(--soft);margin:0 0 10px;max-width:92ch}
  input[type=search]{flex:1;min-width:190px;font:14px system-ui;padding:8px 11px;border-radius:9px;
        border:1px solid var(--line);background:var(--surface);color:var(--ink)}
  select{font:13px system-ui;padding:8px 9px;border-radius:9px;border:1px solid var(--line);
        background:var(--surface);color:var(--ink)}
  .bar{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
  button{font:13px/1 system-ui;font-weight:700;padding:9px 14px;border-radius:9px;border:0;
        background:var(--blue);color:#fff;cursor:pointer}
  .count{font-size:12.5px;color:var(--faint);margin-left:auto}
  main{padding:0 20px 60px}
  table{width:100%;border-collapse:collapse}
  th{position:sticky;top:118px;background:var(--plane);text-align:left;font-size:11px;
     text-transform:uppercase;letter-spacing:.05em;color:var(--faint);padding:8px;
     border-bottom:1px solid var(--line);z-index:4}
  td{padding:7px 8px;border-bottom:1px solid var(--line);vertical-align:top}
  tr.hidden{display:none}
  tr.edited td:first-child{box-shadow:inset 3px 0 0 var(--done)}
  tr.dropped td:first-child{box-shadow:inset 3px 0 0 var(--warn)}
  tr.dropped textarea{opacity:.4}
  .k{font:11.5px ui-monospace,Menlo,monospace;color:var(--faint);white-space:nowrap}
  .g{font-size:11px;color:var(--faint);white-space:nowrap}
  .note{font-size:11.5px;color:var(--faint);max-width:26ch}
  .scene{font-size:12px;color:var(--soft);max-width:22ch}
  textarea{width:100%;font:13.5px/1.45 system-ui;padding:6px 8px;border-radius:7px;
     border:1px solid var(--line);background:var(--surface);color:var(--ink);resize:vertical;
     min-height:34px;field-sizing:content}
  textarea:focus{outline:2px solid var(--blue);outline-offset:-1px}
  textarea[readonly]{background:var(--plane);color:var(--faint)}
  .ph{color:var(--warn);font-size:11px;font-weight:700}
  .opts{margin-top:5px;display:flex;flex-direction:column;gap:4px}
  .opt{text-align:left;font:12.5px/1.4 system-ui;font-weight:500;background:var(--surface);
       color:var(--ink);border:1px solid var(--line);border-radius:7px;padding:5px 8px;cursor:pointer}
  .opt:hover{border-color:var(--blue)}
  .opt b{color:var(--faint);font:11px ui-monospace,Menlo,monospace;font-weight:400;margin-right:6px}
  .row-acts{margin-top:5px;display:flex;gap:6px;flex-wrap:wrap}
  .flat{font:12px system-ui;font-weight:600;background:none;border:1px dashed var(--line);
       color:var(--soft);border-radius:7px;padding:5px 8px;cursor:pointer}
  .flat:hover{border-color:var(--blue);color:var(--blue)}
  .flat.on{border-style:solid;border-color:var(--blue);color:var(--blue)}
  .flat.kill.on{border-color:var(--warn);color:var(--warn)}
  .why{font-size:11.5px;color:var(--warn);margin-top:4px;display:none}
  tr.dropped .why{display:block}
  .tag{font-size:10.5px;color:var(--faint);margin-top:3px}
  .done{background:var(--done)}
</style></head><body>
<header>
  <h1>1Day 文案表</h1>
  <p class="sub">直接在格子里改，改过的行左边有绿条。<b>中文格子只填中文，English 只填英文</b>，两边分开存。
  <b>「用在哪一页」是从代码里扫出来的</b>，就是这句话真正出现的页面。
  每一行下面都有<b>「这里不用写提示」</b>：点了我就把这句话从界面上删掉，连代码里的声明一起删 —— 不是留个空字符串。
  按钮和标题也能点，但那种拿掉会空一块，我会先回来问你一句。带 <code>\\(…)</code> 的地方别动。</p>
  <div class="bar">
    <input type="search" id="q" placeholder="搜中文、英文、键名、页面…">
    <select id="grp"></select>
    <select id="only">
      <option value="">全部 __N__ 条</option>
      <option value="opt">只看有重写选项的（__NOPT__）</option>
      <option value="edited">只看我改过的</option>
      <option value="ask">只看我标了要重写的</option>
      <option value="drop">只看我说不用写的</option>
      <option value="optional">只看可以整句删掉的（__NDROP__）</option>
      <option value="ph">只看带占位符的</option>
    </select>
    <button id="save">改完了，交给 Claude</button>
    <span class="count" id="count"></span>
  </div>
</header>
<main><table><thead><tr>
  <th style="width:15%">键名 / 分组</th><th style="width:15%">用在哪一页</th>
  <th style="width:35%">中文</th><th style="width:35%">English</th>
</tr></thead><tbody id="body"></tbody></table></main>

<script type="application/json" id="data">__DATA__</script>
<script>
const DATA = JSON.parse(document.getElementById('data').textContent);
const body = document.getElementById('body');
const ask = new Set(), drop = new Set();

const esc = s => s.replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));

DATA.forEach((d, i) => {
  const tr = document.createElement('tr');
  tr.dataset.i = i;
  const opts = d.o.length
    ? `<div class="opts">${d.o.map((o, n) =>
        `<button class="opt" data-pick="${n}"><b>${o.length}字</b>${esc(o)}</button>`).join('')}</div>`
    : '';
  const cell = (field, value) => (field === 'en' && d.lockEn)
    ? `<textarea readonly>${esc(value)}</textarea>`
    : `<textarea data-f="${field}">${esc(value)}</textarea>`;
  tr.innerHTML = `
    <td><div class="k">${d.k}</div><div class="g">${esc(d.g)}</div>
        ${d.ph ? '<div class="ph">有占位符</div>' : ''}
        ${d.opt ? '<div class="tag">这句是小字，可以整句删掉</div>' : ''}
        ${d.note ? `<div class="note">${esc(d.note)}</div>` : ''}</td>
    <td><div class="scene">${esc(d.s)}</div></td>
    <td>${cell('zh', d.zh)}${opts}
        <div class="row-acts">
          <button class="flat kill" data-drop>这里不用写提示</button>
          ${d.o.length ? '' : '<button class="flat" data-ask>帮我重写</button>'}
        </div>
        <div class="why">${d.opt
          ? '记下了：这句从界面上拿掉。'
          : '记下了。这是按钮或标题的字，拿掉会空一块 —— 我会先回来问你怎么办。'}</div></td>
    <td>${cell('en', d.en)}</td>`;
  body.appendChild(tr);
});

function mark(i){ body.children[i].classList.add('edited'); }

function collect(){
  window.__1dayCopyEdits = DATA.filter(d => d.zh !== d.zh0 || d.en !== d.en0)
    .map(d => ({ key: d.k, zh: d.zh, en: d.en }));
  window.__1dayCopyAsk = [...ask].map(i => DATA[i].k);
  window.__1dayCopyDrop = [...drop].map(i => ({ key: DATA[i].k, optional: DATA[i].opt }));
  // Survives a reload, which is the whole point: the page holds no server and
  // half-finished edits used to die on refresh. Guarded because a page opened
  // from a `data:` URL is not allowed to rewrite its own location.
  if (location.protocol === 'data:') return;
  try {
    location.replace('#' + encodeURIComponent(JSON.stringify({
      keep: window.__1dayCopyEdits, asked: window.__1dayCopyAsk, dropped: window.__1dayCopyDrop
    })));
  } catch {}
}

body.addEventListener('input', e => {
  const ta = e.target.closest('textarea[data-f]');
  if (!ta) return;
  const i = +ta.closest('tr').dataset.i;
  DATA[i][ta.dataset.f] = ta.value;
  mark(i);
  collect();
  refresh();
});

body.addEventListener('click', e => {
  const tr = e.target.closest('tr');
  if (!tr) return;
  const i = +tr.dataset.i;

  const pick = e.target.closest('[data-pick]');
  if (pick){
    const text = DATA[i].o[+pick.dataset.pick];
    const ta = tr.querySelector('[data-f=zh]');
    if (!ta) return;
    ta.value = text; DATA[i].zh = text; mark(i); collect(); refresh();
    return;
  }
  if (e.target.closest('[data-ask]')){
    const b = e.target.closest('[data-ask]');
    if (ask.has(i)){ ask.delete(i); b.classList.remove('on'); b.textContent = '帮我重写'; }
    else { ask.add(i); b.classList.add('on'); b.textContent = '已标记，等 Claude 重写'; }
    collect(); refresh();
    return;
  }
  if (e.target.closest('[data-drop]')){
    const b = e.target.closest('[data-drop]');
    if (drop.has(i)){
      drop.delete(i); tr.classList.remove('dropped');
      b.classList.remove('on'); b.textContent = '这里不用写提示';
    } else {
      drop.add(i); tr.classList.add('dropped');
      b.classList.add('on'); b.textContent = '✓ 不用写，删掉这句';
    }
    collect(); refresh();
  }
});

function refresh(){
  const q = document.getElementById('q').value.trim().toLowerCase();
  const g = document.getElementById('grp').value;
  const only = document.getElementById('only').value;
  let shown = 0;
  DATA.forEach((d, i) => {
    const tr = body.children[i];
    const hay = (d.k + d.zh + d.en + d.g + d.s + d.note).toLowerCase();
    let ok = (!q || hay.includes(q)) && (!g || d.g === g);
    if (ok && only === 'opt') ok = d.o.length > 0;
    if (ok && only === 'edited') ok = tr.classList.contains('edited');
    if (ok && only === 'ask') ok = ask.has(i);
    if (ok && only === 'drop') ok = drop.has(i);
    if (ok && only === 'optional') ok = d.opt;
    if (ok && only === 'ph') ok = d.ph;
    tr.classList.toggle('hidden', !ok);
    if (ok) shown++;
  });
  const edits = DATA.filter(d => d.zh !== d.zh0 || d.en !== d.en0).length;
  document.getElementById('count').textContent =
    `显示 ${shown} / ${DATA.length} · 改了 ${edits} 条 · 标重写 ${ask.size} 条 · 不用写 ${drop.size} 条`;
}

function restore(){
  if (!location.hash) return;
  let saved;
  try { saved = JSON.parse(decodeURIComponent(location.hash.slice(1))); } catch { return; }
  const byKey = new Map(DATA.map((d, i) => [d.k, i]));
  for (const e of saved.keep || []){
    const i = byKey.get(e.key ?? e.k);
    if (i === undefined) continue;
    DATA[i].zh = e.zh; DATA[i].en = e.en;
    const zh = body.children[i].querySelector('[data-f=zh]');
    const en = body.children[i].querySelector('[data-f=en]');
    if (zh) zh.value = e.zh;
    if (en) en.value = e.en;
    mark(i);
  }
  for (const k of saved.asked || []){
    const i = byKey.get(k);
    if (i === undefined) continue;
    ask.add(i);
    const b = body.children[i].querySelector('[data-ask]');
    if (b){ b.classList.add('on'); b.textContent = '已标记，等 Claude 重写'; }
  }
  for (const d of saved.dropped || []){
    const i = byKey.get(d.key ?? d);
    if (i === undefined) continue;
    drop.add(i);
    body.children[i].classList.add('dropped');
    const b = body.children[i].querySelector('[data-drop]');
    if (b){ b.classList.add('on'); b.textContent = '✓ 不用写，删掉这句'; }
  }
}

const grp = document.getElementById('grp');
grp.innerHTML = '<option value="">全部分组</option>' +
  [...new Set(DATA.map(d => d.g))].map(g => `<option>${esc(g)}</option>`).join('');

['q','grp','only'].forEach(id =>
  document.getElementById(id).addEventListener('input', refresh));
document.getElementById('save').addEventListener('click', () => {
  collect(); refresh();
  const b = document.getElementById('save');
  b.textContent = `改了 ${window.__1dayCopyEdits.length} · 标重写 ${ask.size} · 不用写 ${drop.size} —— 回去说一句`;
  b.classList.add('done');
});
restore();
collect();
refresh();
</script></body></html>
"""


def write_html(rows: list[dict]) -> None:
    data = []
    for r in rows:
        # Line breaks are real ones in the editing box; they get escaped back to
        # `\n` when the edits land in Localization.swift.
        soft = lambda s: s.replace("\\n", "\n")
        zh = soft(r.get("mine", {}).get("zh", r["zh"]))
        en = soft(r.get("mine", {}).get("en", r["en"]))
        data.append(
            {
                "k": r["k"], "zh": zh, "en": en,
                # Originals, so "edited" means edited relative to the shipped
                # string rather than to whatever the page last rendered.
                "zh0": soft(r["zh"]), "en0": soft(r["en"]),
                "ph": r["ph"], "g": r["g"], "note": r["note"], "s": r["s"],
                "o": r["o"], "lockEn": r["lockEn"], "opt": r["opt"],
            }
        )
    # Embedded as JSON in a non-executing script tag: a `\(name)` placeholder in
    # a JS string literal would have its backslash eaten by the parser and she
    # would edit, and save back, a broken placeholder.
    blob = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
    page = (
        PAGE.replace("__DATA__", blob)
        .replace("__NOPT__", str(sum(1 for r in rows if r["o"])))
        .replace("__NDROP__", str(sum(1 for r in rows if r["opt"])))
        .replace("__N__", str(len(rows)))
    )
    HTML_OUT.write_text(page, encoding="utf-8")


if __name__ == "__main__":
    rows = build()
    write_csv(rows)
    write_html(rows)
    print(f"{len(rows)} 条 → {CSV_OUT.name} + {HTML_OUT.name}")
    print(f"  可以整句删掉的 {sum(1 for r in rows if r['opt'])} 条")
    print(f"  有重写选项的 {sum(1 for r in rows if r['o'])} 条")
    print(f"  英文栏锁住的 {sum(1 for r in rows if r['lockEn'])} 条")
