import React from 'react';
import {Composition} from 'remotion';
import {Promo, totalFrames} from './Promo';
import {DemoClip, demoClips} from './DemoClip';
import {friendsShots, soloShots} from './shots';
import {APP_H, APP_W, FPS} from './theme';

export const RemotionRoot: React.FC = () => (
  <>
    {                                                                                         }
    <Composition
      id="SoloXHS"
      component={Promo}
      durationInFrames={totalFrames('XHS', soloShots)}
      fps={FPS}
      width={1080}
      height={1920}
      defaultProps={{variant: 'XHS' as const, shots: soloShots}}
    />
    {
      }
    <Composition
      id="SoloAppStore"
      component={Promo}
      durationInFrames={totalFrames('AppStore', soloShots)}
      fps={FPS}
      width={APP_W}
      height={APP_H}
      defaultProps={{variant: 'AppStore' as const, shots: soloShots}}
    />
    {
      }
    <Composition
      id="FriendsXHS"
      component={Promo}
      durationInFrames={totalFrames('XHS', friendsShots)}
      fps={FPS}
      width={1080}
      height={1920}
      defaultProps={{variant: 'XHS' as const, shots: friendsShots}}
    />
    {
      }
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
