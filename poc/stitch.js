#!/usr/bin/env node
/**
 * stitch.js
 * The core proof-of-concept: takes the 7 daily clips and stitches them
 * into one "weekly group vlog" — exactly what your cloud function (or
 * on-device AVFoundation code in Swift) will do in the real app.
 *
 * Two modes:
 *   node stitch.js            → hard cuts (fast, no re-encode of layout)
 *   node stitch.js --fade     → 0.3s crossfade between every clip
 *
 * Output: output/week_vlog.mp4
 */
const { execFileSync } = require('node:child_process');
const { mkdirSync, writeFileSync, existsSync } = require('node:fs');
const path = require('node:path');

const CLIPS_DIR = path.join(__dirname, 'clips');
const OUT_DIR = path.join(__dirname, 'output');
mkdirSync(OUT_DIR, { recursive: true });

const clips = Array.from({ length: 7 }, (_, i) =>
  path.join(CLIPS_DIR, `day${i + 1}.mp4`)
);
for (const c of clips) {
  if (!existsSync(c)) {
    console.error(`Missing ${c} — run "node generate-clips.js" first.`);
    process.exit(1);
  }
}

const useFade = process.argv.includes('--fade');
const out = path.join(OUT_DIR, 'week_vlog.mp4');

if (!useFade) {
  // --- Mode 1: simple concat (hard cuts) -------------------------------
  // The concat demuxer just glues files together. Because all clips share
  // the same codec/resolution/framerate we can stream-copy: no re-encode,
  // finishes in milliseconds. This is the "cheap path" your server should
  // prefer whenever clips come from the same app-controlled recorder.
  const listFile = path.join(OUT_DIR, 'list.txt');
  writeFileSync(listFile, clips.map((c) => `file '${c}'`).join('\n'));
  execFileSync('ffmpeg', [
    '-y', '-f', 'concat', '-safe', '0', '-i', listFile,
    '-c', 'copy',
    out,
  ], { stdio: ['ignore', 'ignore', 'inherit'] });
} else {
  // --- Mode 2: crossfade (xfade + acrossfade filters) ------------------
  // Re-encodes everything, so it's ~100x slower, but looks like a real
  // edited vlog. Each transition starts 0.3s before the current clip ends.
  const FADE = 0.3;
  const CLIP_LEN = 2; // must match generate-clips.js

  const inputs = clips.flatMap((c) => ['-i', c]);
  let filter = '';
  let vPrev = '0:v';
  let aPrev = '0:a';
  let offset = CLIP_LEN - FADE;
  for (let i = 1; i < clips.length; i++) {
    const vNext = `v${i}`;
    const aNext = `a${i}`;
    filter += `[${vPrev}][${i}:v]xfade=transition=fade:duration=${FADE}:offset=${offset}[${vNext}];`;
    filter += `[${aPrev}][${i}:a]acrossfade=d=${FADE}[${aNext}];`;
    vPrev = vNext;
    aPrev = aNext;
    offset += CLIP_LEN - FADE;
  }

  execFileSync('ffmpeg', [
    '-y', ...inputs,
    '-filter_complex', filter,
    '-map', `[${vPrev}]`, '-map', `[${aPrev}]`,
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac',
    out,
  ], { stdio: ['ignore', 'ignore', 'inherit'] });
}

console.log(`\nStitched → ${out}`);
execFileSync('ffprobe', [
  '-v', 'error', '-show_entries', 'format=duration,size',
  '-of', 'default=noprint_wrappers=1', out,
], { stdio: 'inherit' });
