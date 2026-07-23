#!/usr/bin/env node
/**
 * generate-clips.js
 * Creates 7 fake "daily vlog" test clips (2 seconds each) so you can
 * test the stitching pipeline without recording real videos.
 *
 * Each clip is a solid color with "Day N" text, 1080x1920 (vertical,
 * like a phone recording), with a beep tone as audio.
 *
 * Usage: node generate-clips.js
 */
const { execFileSync } = require('node:child_process');
const { mkdirSync } = require('node:fs');
const path = require('node:path');

const CLIPS_DIR = path.join(__dirname, 'clips');
mkdirSync(CLIPS_DIR, { recursive: true });

// One color per day — just to make each clip visually distinct
const DAYS = [
  { day: 1, color: '0x264653' },
  { day: 2, color: '0x2a9d8f' },
  { day: 3, color: '0xe9c46a' },
  { day: 4, color: '0xf4a261' },
  { day: 5, color: '0xe76f51' },
  { day: 6, color: '0x9b5de5' },
  { day: 7, color: '0x00b4d8' },
];

const DURATION = 2; // seconds, matching your 2-3s snippet idea

// Some ffmpeg builds (e.g. current Homebrew bottle) ship without the
// drawtext filter. Fall back to color-only clips when it's missing —
// the point of this PoC is the stitching, not the label.
const hasDrawtext = (() => {
  try {
    return execFileSync('ffmpeg', ['-hide_banner', '-filters'])
      .toString().includes('drawtext');
  } catch {
    return false;
  }
})();
if (!hasDrawtext) {
  console.log('Note: this ffmpeg build lacks drawtext — clips will be color-only.');
}

for (const { day, color } of DAYS) {
  const out = path.join(CLIPS_DIR, `day${day}.mp4`);
  console.log(`Generating ${out} ...`);
  execFileSync('ffmpeg', [
    '-y',
    // video: solid color canvas
    '-f', 'lavfi', '-i', `color=c=${color}:s=1080x1920:d=${DURATION}:r=30`,
    // audio: a short tone, different pitch per day so you can HEAR the cuts
    '-f', 'lavfi', '-i', `sine=frequency=${300 + day * 100}:duration=${DURATION}`,
    // draw "Day N" label when the build supports it
    ...(hasDrawtext
      ? ['-vf', `drawtext=text='Day ${day}':fontsize=160:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2`]
      : []),
    // Encode to match what iPhone cameras produce as closely as possible —
    // AVFoundation (especially the iOS simulator) is picky about ffmpeg's
    // default mp4 mux settings (video timescale 1000 trips it up).
    '-c:v', 'libx264', '-profile:v', 'high', '-pix_fmt', 'yuv420p',
    '-video_track_timescale', '600',
    '-movflags', '+faststart',
    '-c:a', 'aac', '-shortest',
    out,
  ], { stdio: ['ignore', 'ignore', 'inherit'] });
}

console.log(`\nDone. 7 clips in ${CLIPS_DIR}`);
console.log('Next: node stitch.js');
