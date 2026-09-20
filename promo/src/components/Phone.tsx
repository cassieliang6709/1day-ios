import React from 'react';
import {OffthreadVideo, staticFile, useCurrentFrame, interpolate} from 'remotion';
import {APP_H, APP_W} from '../theme';

/**
 * The recording inside a soft-edged screen. No drawn bezel: the source is a
 * clean full-screen capture, so a rounded mask reads as a phone without the
 * plastic-looking fake hardware that dates a promo video.
 */
export const Phone: React.FC<{
  src: string;
  width: number;
  /** Slow push-in; 0 disables it. */
  zoom?: number;
}> = ({src, width, zoom = 0.04}) => {
  const frame = useCurrentFrame();
  const height = Math.round((width / APP_W) * APP_H);
  const scale = interpolate(frame, [0, 200], [1, 1 + zoom], {
    extrapolateRight: 'clamp',
  });

  return (
    <div
      style={{
        width,
        height,
        borderRadius: width * 0.085,
        overflow: 'hidden',
        transform: `scale(${scale})`,
        boxShadow:
          '0 40px 90px rgba(16, 32, 58, 0.22), 0 4px 14px rgba(16, 32, 58, 0.10)',
      }}
    >
      <OffthreadVideo
        src={staticFile(src)}
        style={{width: '100%', height: '100%', objectFit: 'cover'}}
        muted
      />
    </div>
  );
};
