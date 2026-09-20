import React from 'react';
import {interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {brand, fontStack} from '../theme';

export const Caption: React.FC<{text: string; size: number}> = ({
  text,
  size,
}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const rise = spring({frame, fps, config: {damping: 200}, durationInFrames: 18});
  const opacity = interpolate(rise, [0, 1], [0, 1]);

  return (
    <div
      style={{
        fontFamily: fontStack,
        fontSize: size,
        fontWeight: 600,
        letterSpacing: '0.01em',
        color: brand.ink,
        textAlign: 'center',
        opacity,
        transform: `translateY(${interpolate(rise, [0, 1], [18, 0])}px)`,
      }}
    >
      {text}
    </div>
  );
};

export const TitleCard: React.FC<{
  title: string;
  sub?: string;
  note?: string;
  size: number;
}> = ({title, sub, note, size}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const rise = spring({frame, fps, config: {damping: 200}, durationInFrames: 22});

  return (
    <div
      style={{
        fontFamily: fontStack,
        textAlign: 'center',
        opacity: interpolate(rise, [0, 1], [0, 1]),
        transform: `translateY(${interpolate(rise, [0, 1], [26, 0])}px)`,
        padding: '0 8%',
      }}
    >
      <div
        style={{
          fontSize: size,
          fontWeight: 700,
          lineHeight: 1.35,
          color: brand.ink,
          whiteSpace: 'pre-line',
        }}
      >
        {title}
      </div>
      {sub ? (
        <div
          style={{
            marginTop: size * 0.7,
            fontSize: size * 0.46,
            fontWeight: 500,
            color: brand.blue,
          }}
        >
          {sub}
        </div>
      ) : null}
      {note ? (
        <div
          style={{
            marginTop: size * 0.45,
            fontSize: size * 0.3,
            fontWeight: 400,
            color: 'rgba(16, 32, 58, 0.5)',
          }}
        >
          {note}
        </div>
      ) : null}
    </div>
  );
};
