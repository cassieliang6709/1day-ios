# 1Day 上架素材包 · 2026-09-07

定位：**选个主题，把日常拍成 Vlog。** 英文副标题：**Pick a Theme. Make a Vlog.** 小蓝的陪伴与朋友共同记录是辅助卖点。

## 可以直接上传的素材

- `zh-Hans/`：5 张简体中文商店截图，以及名称、副标题、关键词、推广文案、描述和更新说明的独立 `.txt` 文件。
- `en-US/`：同样完整的英文素材。请对应 App Store Connect 的 English (U.S.) 本地化，不要与中文截图混用。
- `metadata.json`：两套文案的结构化版本。
- `preview-zh.png` / `preview-en.png`：截图总览，仅用于检查，不上传。
- [完整上架文案与 ASO 策略](../AppStoreMetadata.md)。

### 截图顺序

| 顺序 | 文件 | 传达的信息 |
|---|---|---|
| 1 | `01-theme.png` | 选个主题，开始今天的 Vlog；展示实际主题选择页 |
| 2 | `02-moments.png` | 跟着提示，每次拍几秒；展示小蓝日常片段时间轴 |
| 3 | `03-daily-vlog.png` | 自动成片；展示实际成片预览与保存、分享入口 |
| 4 | `04-record-by-time.png` | 不写脚本，按时间记录 |
| 5 | `05-blue-and-private.png` | 小蓝陪伴与本地保存；独自记录无需账号 |

每张 **1320 × 2868、PNG、RGB、不透明**，适用于 Apple 当前接受的 6.9 英寸 iPhone 截图规格。没有添加虚构评分、奖项、用户评价或未经验证的多人房间。

## 截图来源

当前代码构建（1.2 / build 10），iPhone 17 Pro Max、iOS 26.5 模拟器，明亮外观，中英文分别采集。`raw/` 保留未经装饰的原始截图；`artwork/` 保留可重新排版的 HTML 源文件。营销标题在设备画面之外，App UI 没有重绘或修改。

故事内容是专用本地测试数据：将仓库已有蓝色角色插画制成短示例片段，交给 App 的真实播放器、时间轴及合成流程显示。不是用户私人录像，不代表真实用户故事。图片底部注明“实际 App 界面 · 示例故事”。当前素材不包含好友功能截图，因为没有用虚构房间冒充真实多人测试。

落地页使用同一批本地化截图的网页尺寸版本，分享卡片为 1200 × 630。

## 使用前最后确认

1. 在 App Store Connect 选择实际提交的 1.2 构建；素材包按当前 build 10 准备，不会自动上传或提交审核。
2. 将各语言目录的五张截图按编号上传，文本逐项复制。文案末尾的换行仅是文本文件格式，不计入字段内容。
3. What's New 按当前仓库功能撰写；确认这些功能确实在本次提交构建内。未声称与某个已上架二进制做过完整差异验证。
4. 单人视频本地保存不等于所有功能离线：朋友房间使用 CloudKit，可选智能题目建议使用在线服务。旧 `docs/app-store-submission.md` 的“零网络请求”等表述已标记为历史内容，不能直接复制。
5. 隐私问卷、AI 数据分享告知与许可、账号删除、用户内容举报/屏蔽、CloudKit 生产环境和真实双机同步，仍应按发布构建核查。本次完成的是网站和上架素材，不替代 App 发布验收。

## SEO / ASO

“ATS”通常指简历筛选系统；本次按应用商店 **ASO** 与网站 **SEO** 完成。未承诺搜索排名。

名称和副标题上限 30 字符，关键词 100，推广文案 170，描述与更新说明 4000；已校验。名称、副标题覆盖核心搜索意图，关键词扩展真实相关场景，未塞入竞品或健身等无关词。

[Apple 产品页指南](https://developer.apple.com/app-store/product-page/) · [截图规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications) · [Google 多语言页面](https://developers.google.com/search/docs/specialty/international/localized-versions)
