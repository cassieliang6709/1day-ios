# Setlog-style 7-day vlog stitching PoC

Validates the core pipeline of the group-challenge vlog app: 7 daily
snippets in → one weekly vlog out. This mirrors what the production
renderer will do (server-side FFmpeg, or on-device AVFoundation in the
Swift app).

## Run it

```bash
node generate-clips.js   # creates clips/day1.mp4 ... day7.mp4 (2s each)
node stitch.js           # hard cuts, stream-copy (instant)
node stitch.js --fade    # 0.3s crossfades, re-encodes (slower, prettier)
open output/week_vlog.mp4
```

## What each mode proves

- **Hard cuts** (`-f concat -c copy`): when every clip comes from the same
  app-controlled recorder (same codec/resolution/fps), stitching is a
  stream copy — milliseconds, no quality loss. This should be the default
  production path.
- **Crossfade** (`xfade` + `acrossfade`): the "edited vlog" look. Requires
  a full re-encode, so budget real CPU time per render job.

## Verified output

- Hard cuts: 14.0s (7 × 2s), ~178 KB
- Crossfade: 12.3s (14s − 6 transitions × 0.3s overlap), ~192 KB

## Note on this machine's ffmpeg

The current Homebrew ffmpeg bottle lacks the `drawtext` filter, so test
clips are color-coded (plus a different audio pitch per day) instead of
labeled "Day N". `generate-clips.js` auto-detects and uses drawtext when
available (e.g. in a Docker/Cloud Run image with a full ffmpeg build).

## Swift equivalent

In the iOS app, the same stitch can run **on-device with AVFoundation**
(no FFmpeg needed): `AVMutableComposition` to append each clip's tracks
back-to-back, `AVVideoComposition` for crossfades, then
`AVAssetExportSession` to write the final .mp4.
