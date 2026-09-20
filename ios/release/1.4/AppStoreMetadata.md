# 1Day 1.4 — App Store copy

Prepared 2026-09-20, for the `1.4 准备提交` version record in App Store Connect.
Build 23.

## What actually changes in the store listing

1.4 is two corrections, not a feature release. Only one field has to change —
but one thing 1.3 *added* to the listing now describes behaviour this build
removes, so it has to come back out.

| Field | Where it lives in ASC | Action |
| --- | --- | --- |
| 名称 | App 信息 → 可本地化信息 | Unchanged from 1.3. |
| 副标题 | App 信息 → 可本地化信息 | Unchanged from 1.3. |
| 关键词 | 版本页 | Unchanged. |
| 推广文本 | 版本页 | Unchanged. Can be edited later without review if you want to. |
| 描述 | 版本页 | **Check and remove one section** — see below. |
| 此版本的新增内容 | 版本页 | **New.** Text below. |

### The 1.3 description section that has to go

1.3's kit offered an optional description section built around the accent
colour following your avatar. **If you added it to the live listing, remove it
now** — the app no longer does that, and a description that promises it is a
description Apple can reject on a metadata check.

Look for these and delete the whole section if present:

```text
A LOOK THAT IS YOURS
Pick your avatar color and the whole app follows it. …
```

```text
一眼就是你的样子
挑一个头像颜色，整个 App 的主色跟着变。…
```

Covers and replay captions — the other two things that section mentioned — are
unchanged, so if you want to keep a section there, keep only those two
sentences and drop the accent-colour one.

## en-US

### What's New (272 characters)

```text
Two fixes.

• Your avatar colour now only colours your avatar. It used to re-tint the whole app, so a warm pick ended up fighting the blue everything else is built on.

• Clips waiting to be filed no longer hover over your stories. They sit in the list, scroll with it, and cover nothing.
```

## zh-Hans

### What's New (118 characters)

```text
两处修正。

• 头像颜色只改头像了。之前它会把整个 App 的主色一起换掉，挑个暖色就和蓝色的底撞在一起。

• 「待归档」不再浮在内容上面，改成列表里的一行，跟着页面滚，不挡故事。
```

## Screenshots

Unchanged from 1.3. Nothing in this build changes a screen that appears in the
set — the accent was already blue in those shots (they were taken before anyone
had picked a colour), and none of them had a clip waiting to be filed.

Re-shoot only if you want the drafts row visible in one of them, which is not
worth a review cycle.

## Privacy questionnaire

**No change.** 1.4 adds no network call, no new stored field and no new
permission. The answers filed for 1.3 still hold.

Do still re-read `docs/app-store-submission.md` before submitting — that
document carries its own warning that it predates the optional remote prompt
suggestions, so it is not a safe copy-paste source for the questionnaire.

## Review notes

Nothing new to explain. The demo-room launch arguments added in this branch are
inside `#if DEBUG || LOCAL_ROOM_CHAT_DEMO` and are not compiled into a Release
build; a reviewer cannot reach them.
