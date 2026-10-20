# 1Day for Android

Flutter client for personal, offline stories. The native Android media module uses
Media3 Transformer to export MP4 entirely on the device.

## Current flow

1. Choose a one-day or seven-day built-in template and name the story.
2. Pick a 2, 5, or 10-second clip length and portrait or landscape framing.
3. Record a moment with the front or rear camera, review it, and keep or retake.
4. Reopen recorded moments, replace today's take, and assemble recorded clips
   in moment order. The film adds each moment's caption and can be saved to the
   gallery or shared as MP4.

Story metadata is written to a versioned JSON manifest in app support storage;
original clips and generated films stay in the app's private files. The app has no account requirement. Optional AI suggestions send only the entered
sentence, requested count, language, and a random installation ID to the existing
1Day Worker. Videos stay on the device. Uninstalling the app removes
that private library, so save finished films to the gallery before uninstalling.

## Run

Install Flutter, the Android SDK, and an Android 10+ device or emulator. From
this directory:

```sh
flutter pub get
flutter run
flutter test
flutter build apk --debug
flutter build apk --release
```

The Android package ID is `com.cassie.one_day`. Camera and microphone access is
requested when opening the recorder. Android 10 is the minimum supported version
for saving films through scoped storage.

The universal release APK is written to `build/app/outputs/flutter-apk/app-release.apk`.
It requests network access for optional AI suggestions, but no external-storage read permission. It is signed with the
generated debug key for local testing, **not** with a Play Store release key.
The debug APK retains Flutter's development network permission for hot reload.

## Shared rooms

The iOS app currently stores shared rooms in CloudKit. Android cannot join those
rooms directly. Both apps must use the same room service before an Android user
can join an iOS user's room. The local `Story` model retains the iOS template
identity, language-independent moment keys, one-based slot order, clip length,
orientation, and optional room code for that migration. A shared room service
must define participant identity, room creation/joining, clip upload/download,
authorization, and reactions/comments for **both** clients. Existing CloudKit
rooms also need an explicit migration or compatibility policy. The present app
does not display an invitation action because it has no shared backend yet.

## Differences from iOS today

Android currently exports sequential cuts with captions. Media3 Transformer does
not support crossfades in a composition. Custom stories now support editable prompts and optional AI suggestions. Saving
reusable custom templates, caption sticker controls, reminders, and collaborative
rooms have not been ported yet.

## Custom stories

Choose “Write my own moments”, enter three to seven prompts for a one-day story
or seven prompts for a seven-day story, then name and create it. Optional AI
suggestions can fill seven editable prompts. Errors keep existing input and
show a retry message. Custom prompts persist across recordings and become export
captions.

For this checkout, use Java 17 when building: `JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home flutter build apk --debug`.
