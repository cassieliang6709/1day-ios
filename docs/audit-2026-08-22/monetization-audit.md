# 1Day monetization audit

Date: 2026-08-22

## Verdict

1Day already has a convincing payoff: several tiny recordings become a finished film on-device. The product is not short on features; it is short on a fast first success, a clear buyer/use case, and a purchase surface at the moment of highest value.

The recommended launch model is freemium plus a non-consumable one-time unlock. Do not lead with a recurring subscription until 1Day provides recurring paid value such as cross-device backup, continuously released film styles, or a substantial content library.

## Recommended offer

### Free

- Create and preview the first complete film.
- Join a friend's room and contribute clips for free.
- Export with a short, tasteful 1Day end card.

### 1Day Plus — one-time purchase

- Launch price: CNY 18 for early adopters.
- Regular price: CNY 28.
- Clean HD exports without the 1Day end card.
- Unlimited stories and custom prompts.
- Host shared rooms; invited contributors remain free.
- Restore purchases.

### Later, only after retention is proven

An optional CNY 68/year plan can be tested if it includes ongoing cloud backup and sync, regularly added themes and film styles, and richer collaboration. Those capabilities are not currently strong enough to justify a subscription.

## Best paywall moment

Let the user watch the finished film first. Intercept Save or Share with this offer:

> 把今天完整留下
>
> 你的影片已经生成好了。
>
> 1Day Plus · 一次买断 ¥28
>
> 无水印高清保存 · 无限故事 · 发起好友合拍

Primary action: `解锁并保存`

Secondary action: `保留 1Day 片尾并免费导出`

Footer: `恢复购买`

Disclose the branded free export before the user records, so the paywall does not feel like a surprise.

## Highest-impact product changes

1. Make the first-run story three moments, not seven. The first film should be reachable in under two minutes.
2. Position the product around one sharp wedge: “和重要的人，把同一天拍成一支片。” The shared-day film is more differentiated than a generic video diary.
3. Prevent duplicate empty stories from accumulating. Keep one featured active story and move old or abandoned stories to a quiet archive.
4. Make Share the primary action on the film screen and fix the floating tab bar overlapping the facts card.
5. Add the purchase state, StoreKit purchase/restore/error handling, and a clear Plus section in Settings.
6. Measure the funnel: first open → story created → first clip → film preview → paywall → purchase → share. Do not optimize price from anecdotes alone.
7. Add pricing, a concrete use case, and one proof point to the landing page. The current page explains the mechanics well but has no offer or evidence that someone finished and valued the experience.

## Captured flow

1. Home: healthy visual hierarchy, but duplicate empty challenges create management noise.
2. Theme selection: polished and understandable, but seven moments is a heavy first commitment.
3. Setup: collaboration is visible and potentially differentiating; there is no indication of what is free or paid.
4. Timeline: progress and preview are clear, but shared-room setup can block users before the payoff.
5. Film ready: strongest value moment and best place to sell; bottom navigation visibly overlaps content.
6. Landing page: strong craft and sample-film emphasis, but positioning is broad and pricing/social proof are absent.

## Evidence limits

The audit used the current iOS Simulator build and local landing page. Camera hardware, microphone permissions, two-device CloudKit collaboration, App Store purchase review, VoiceOver order, Dynamic Type extremes, reduced motion behavior, and physical-device export performance were not fully verified.
