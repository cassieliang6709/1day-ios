import React from 'react';
import {
  AbsoluteFill,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';

export const DemoClip: React.FC<{src: string; drift?: number}> = ({
  src,
  drift = 0.06,
}) => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();

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

export const demoClips = [
  {id: 'DemoClip1', src: 'blue-morning.jpg', drift: 0.06},
  {id: 'DemoClip2', src: 'blue-focus.jpg', drift: 0.05},
  {id: 'DemoClip3', src: 'blue-cooking.jpg', drift: 0.05},
  {id: 'DemoClip4', src: 'blue-adventure.jpg', drift: 0.08},
  {id: 'DemoClip5', src: 'blue-perfect.jpg', drift: 0.06},
  {id: 'DemoClip6', src: 'blue-reset.jpg', drift: 0.04},
] as const;
