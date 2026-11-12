# Behavior-level verification

## Camera and recording

Entry: Camera tab. Owner: `ClipRecorder` and `RecordClipView`.
Check front/back, dual camera, portrait/landscape, capture, keep, re-record, and leaving during configuration. A switching camera cannot start a take. Re-entering must show a working preview without relighting a camera that has been left. Camera hardware needs a physical iPhone; simulated footage is not hardware proof.

## Rooms and profile

Entry: Rooms, then one room. Owners: `ChallengeStore`, `RoomSyncService`, `AvatarImageCache`.
Check cached roster, avatar replacement/removal, and interaction visibility while videos are held. Refresh twice and deliver responses backwards; old data must not overwrite the new result. Sign out while requests are held; releasing them must not repopulate the previous account. Use existing injected transports for deterministic tests, not production writes.

## Playback and export

Entry: a recorded clip, then the film. Owners: `ClipPlayback`, `VlogPlayer`, `VideoStitcher`.
Check re-recording at the same path, editing a second caption and its position, leaving during export, changing look, opening full-screen and returning, and backgrounding. No duplicate sound or continued idle decoding. Cache eviction may remove unused derived videos, never source footage or an active preview's file. Verify Photos denial and retry separately from export success.

## UI polish

Entry: tab bar and timeline with recorded and empty slots. Keep the current brand and media hierarchy.
Compare small iPhone and a larger one; English and Chinese; light/dark; default and largest Dynamic Type; Reduce Motion on/off; VoiceOver. Reduce Motion should stop decorative pulse and moving selection while preserving visible selection, labels and activation. Do not treat fixed-size text or a Dynamic Type cap as an accessibility solution. Native screenshots and an interaction pass remain required before visual sign-off.
