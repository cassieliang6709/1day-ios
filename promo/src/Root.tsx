import React from 'react';
import {Composition} from 'remotion';
import {Promo, totalFrames} from './Promo';
import {DemoClip, demoClips} from './DemoClip';
import {friendsShots, soloShots} from './shots';
import {APP_H, APP_W, FPS} from './theme';

export const RemotionRoot: React.FC = () => (
  <>
    {/* 单人版 · 小红书 / 视频号: 9:16 with a branded frame around the recording. */}
    <Composition
      id="SoloXHS"
      component={Promo}
      durationInFrames={totalFrames('XHS', soloShots)}
      fps={FPS}
      width={1080}
      height={1920}
      defaultProps={{variant: 'XHS' as const, shots: soloShots}}
    />
    {/*
      单人版 · App Store 6.9" preview: full-bleed device capture, 886x1920.
      Apple's ceiling is 30s, and the hook card is dropped because a preview is
      supposed to be app footage rather than a poster.
    */}
    <Composition
      id="SoloAppStore"
      component={Promo}
      durationInFrames={totalFrames('AppStore', soloShots)}
      fps={FPS}
      width={APP_W}
      height={APP_H}
      defaultProps={{variant: 'AppStore' as const, shots: soloShots}}
    />
    {/*
      双人版 · 小红书 only. The room is the app's local demo, so this one does
      not go to the App Store, where a preview has to be the real experience.
    */}
    <Composition
      id="FriendsXHS"
      component={Promo}
      durationInFrames={totalFrames('XHS', friendsShots)}
      fps={FPS}
      width={1080}
      height={1920}
      defaultProps={{variant: 'XHS' as const, shots: friendsShots}}
    />
    {/*
      Stand-in clips for the app's local room demo. 960x540 / 3s: landscape so
      VideoStitcher.grid stacks them instead of putting them side by side, and
      the exact size LocalRoomClipImporter exports to — see DemoClip.
    */}
    {demoClips.map(({id, src, drift}) => (
      <Composition
        key={id}
        id={id}
        component={DemoClip}
        durationInFrames={FPS * 3}
        fps={FPS}
        width={960}
        height={540}
        defaultProps={{src, drift}}
      />
    ))}
  </>
);
