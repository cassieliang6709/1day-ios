import React from 'react';
import {
  AbsoluteFill,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';

/**
 * A stand-in "recorded clip" for the app's local room demo.
 *
 * 960x540 and three seconds are not style choices.
 *
 * The size is landscape on purpose. `VideoStitcher.grid` reads the shape of
 * the takes — `sourceAspect < 1 ? (1, count) : (count, 1)` — so portrait takes
 * go side by side and landscape takes stack. Rendering these portrait put two
 * landscape illustrations into 270-wide columns, which is how a perfectly
 * correct layout produced a film that was mostly blur. Handing the stitcher
 * the shape the content actually is lets its own rule do the right thing.
 *
 * 960x540 is also what `DemoClipFactory` draws for landscape and exactly what
 * `LocalRoomClipImporter.trim` exports through `AVAssetExportPreset960x540`,
 * which additionally keeps only the first three seconds.
 *
 * The stills are 1200x720 (1.667) against a 1.778 frame, so `cover` trims
 * about 7% of the height and nothing needs to be padded or blurred.
 */
export const DemoClip: React.FC<{src: string; drift?: number}> = ({
  src,
  drift = 0.06,
}) => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();

  // A slow push-in across the whole clip: enough that the frame is obviously
  // moving, not so much that three seconds ends somewhere different.
  const scale = interpolate(frame, [0, durationInFrames], [1, 1 + drift], {
    extrapolateRight: 'clamp',
  });

  return (
    <AbsoluteFill style={{backgroundColor: '#0f2e6b', overflow: 'hidden'}}>
      <AbsoluteFill
        style={{
          backgroundImage: `url(${staticFile(src)})`,
          backgroundSize: 'cover',
          backgroundPosition: 'center',
          transform: `scale(${scale})`,
        }}
      />
    </AbsoluteFill>
  );
};

/**
 * One clip per member per moment, in the order the room's import menu lists
 * them: moment first, then member. Rendering them in that order means the
 * photo picker's grid reads 1-6 left to right, top to bottom, and the import
 * pass is six straight picks with nothing to match up by eye.
 *
 * The pairs are two people living different days at the same hours — which is
 * the thing a shared room is for, and the reason 小蓝 is never doing what 小白
 * is doing.
 */
export const demoClips = [
  {id: 'DemoClip1', src: 'blue-morning.jpg', drift: 0.06}, // 晨光 · 小蓝
  {id: 'DemoClip2', src: 'blue-focus.jpg', drift: 0.05}, //   晨光 · 小白
  {id: 'DemoClip3', src: 'blue-cooking.jpg', drift: 0.05}, // 午饭 · 小蓝
  {id: 'DemoClip4', src: 'blue-adventure.jpg', drift: 0.08}, // 午饭 · 小白
  {id: 'DemoClip5', src: 'blue-perfect.jpg', drift: 0.06}, // 傍晚 · 小蓝
  {id: 'DemoClip6', src: 'blue-reset.jpg', drift: 0.04}, //   傍晚 · 小白
] as const;
