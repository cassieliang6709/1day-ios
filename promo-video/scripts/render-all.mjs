import {mkdirSync} from 'node:fs';
import {spawnSync} from 'node:child_process';

const compositions = [
  'FriendsTogether',
  'NoPressureVlog',
  'SevenDayChallenge',
  'FilmMadeOnIPhone',
  'IActuallyBuiltIt',
];

mkdirSync('out', {recursive: true});

for (const composition of compositions) {
  const result = spawnSync(
    'npx',
    ['remotion', 'render', 'src/index.ts', composition, `out/${composition}.mp4`, '--codec=h264', '--crf=18', '--pixel-format=yuv420p'],
    {stdio: 'inherit'},
  );
  if (result.status !== 0) process.exit(result.status ?? 1);
}
