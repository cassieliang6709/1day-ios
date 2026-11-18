---
name: 1day-design-system
description: 维护 1Day iOS App 的设计规范 DESIGN.md，并把页面里的组件、字号、圆角、间距、颜色统一到规范上。用户说「组件不统一」「统一一下」「定设计规范」「加一个新组件」「这页和那页长得不一样」，或要新建一个可复用的 SwiftUI 组件、要定下某个 token 的值（哪怕只是一个圆角或间距）时使用。不用于：只问代码里现在用的是哪个颜色或字号变量（直接回答）；与 1Day 无关的通用 UI/UX 评审（用 oiloil-ui-ux-guide）；只想看 App 现在什么样（用 run-1day）；验证功能能不能用（用 1day-verify）。
---

# 1day-design-system

`DESIGN.md`（仓库根目录）是 1Day 界面的唯一依据。代码落点：`ios/AISetlog/Resources/Theme.swift` 里的 `OneDay` token，和 `ios/AISetlog/Views/DesignSystem/` 里的共用组件。本 Skill 只做两件事：**改规范**和**按规范统一页面**。

## 第 0 步：量现状

每次开始都先跑一次检查脚本，记下数字：

```bash
python3 .claude/skills/1day-design-system/scripts/design_lint.py
```

它数出 `ios/AISetlog/Views` 里手写的字号、圆角、padding、spacing、十六进制颜色，并列出最多的文件。

- 还没有基线文件 `docs/design/design-lint-baseline.json` 时，加 `--write-baseline docs/design/design-lint-baseline.json` 存一份，告诉用户存了。
- 已有基线时，加 `--baseline docs/design/design-lint-baseline.json`。退出码 1 表示有文件比基线更差，先看是谁加的。

## 选路径

| 用户要的 | 走 |
| --- | --- |
| 定规范、改 token、加组件条目 | 路径 A |
| 把某类组件或某几页统一到规范 | 路径 B |
| 两个都要 | 先 A 后 B，A 定下来之前不动页面 |

## 路径 A：改规范

1. 读完整的 `DESIGN.md`。
2. 找出这次要定的条目。标 **【待定】** 的条目优先。
3. 有审美取舍的地方，不自己拍板。准备 2～3 个选项，每个写一句取舍。能在真机上看的，按 run-1day 装到 iPhone 上截图给用户比较。
4. 等用户选定，再改 `DESIGN.md`：删掉【待定】标记，写上定下的值和用途。
5. 需要新 token 时，加到 `Theme.swift` 的 `OneDay` 里，名字和 `DESIGN.md` 完全一致。
6. 编译一次（测试第 1 档：只编译）。

停止条件：用户还没选的条目保持【待定】，不替用户填。

## 路径 B：统一页面

一次只统一**一类组件**（例如所有片段小图），不和功能改动混在一起。

1. 在 `DESIGN.md` 第 6 节找到这类组件的合并目标。没有目标时先走路径 A 定下来。
2. 用 `grep` 列出所有用到旧组件或手写样式的文件。
3. 把要改的文件清单和改法告诉用户。超过 3 个文件或约 100 行时，等用户说「可以」再动。
4. 先在 `Views/DesignSystem/` 做好目标组件（或确认已有的能用），只用 token。
5. 改动前，在 iPhone 上给每个受影响的页面截一张图，作为对比基准。
6. 一页一页把调用方换成目标组件。每换完一页：编译，再到 iPhone 上截同一个画面。
7. 对比前后截图。除了本来就要统一的地方，其他视觉变化（尺寸跳动、文字截断、颜色变了）都先停下，把两张图给用户看。
8. 旧组件没有任何调用方以后，再删掉它。用 `grep` 确认没人用了。
9. 更新 `DESIGN.md` 第 6 节：状态改成「已统一」。
10. 跑 `design_lint.py --baseline …`，确认没有变差，再用 `--write-baseline` 存新基线。
11. 跑测试第 2 档：编译 + 受影响页面对应的单元测试；有 UI 测试用到被改元素的 identifier 时跑那一个。

## 规则

- 页面代码只写 `OneDay.xxx`。确实需要写数字的（`DESIGN.md` 第 7 节的例外），在那一行写注释 `// design-lint: allow` 加一句原因。
- 新组件先在 `DESIGN.md` 第 6 节有一行，再写代码。
- 不改组件的行为、无障碍标签和 accessibility identifier；UI 测试靠它们找元素。
- 截图看的是用户的 iPhone。手机连不上时才用模拟器，并说明用的是模拟器。

## 交付时说

- 统一了哪类组件，改了哪几页。
- 前后截图各一张（同一个画面）。
- `design_lint.py` 的数字前后各是多少。
- 跑了哪一档测试，结果如何。
- 还剩哪些页面没统一。
