import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_day/data/story_store.dart';
import 'package:one_day/domain/story.dart';
import 'package:one_day/domain/templates.dart';

Story sampleStory({StoryMode mode = StoryMode.oneDay, DateTime? start}) =>
    Story(
      id: 'd1da9aac-86e5-4c77-9a0a-f188cf473cf5',
      title: 'Perfect Day',
      startDate: start ?? DateTime(2026, 9, 26, 10),
      mode: mode,
      clipSeconds: 2,
      orientation: StoryOrientation.portrait,
      templateKey: 'Perfect Day',
      moments: const [
        StoryMoment(key: 'wake_up'),
        StoryMoment(key: 'coffee'),
      ],
    );

void main() {
  test(
    'custom prompts survive persistence and a replacement recording',
    () async {
      final root = await Directory.systemTemp.createTemp('oneday-custom-');
      addTearDown(() => root.delete(recursive: true));
      final store = await StoryStore.open(root);
      final story = Story(
        id: Story.newId(),
        title: 'My walk',
        startDate: DateTime.now(),
        mode: StoryMode.oneDay,
        clipSeconds: 2,
        orientation: StoryOrientation.portrait,
        templateKey: 'custom',
        moments: const [StoryMoment(key: 'custom_1', prompt: '湖边的风')],
      );
      await store.add(story);
      final clip = File('${root.path}/source.mp4')..writeAsBytesSync([1, 2, 3]);
      await store.saveClip(story.id, 0, clip);
      final reopened = await StoryStore.open(root);
      expect(reopened.find(story.id)!.moments.first.prompt, '湖边的风');
      expect(reopened.find(story.id)!.moments.first.key, 'custom_1');
      expect(StoryMoment.fromJson({'key': 'coffee'}).prompt, isNull);
    },
  );

  test('stable moment keys survive a localized round trip', () {
    final original = sampleStory();
    final decoded = Story.fromJson(original.toJson());
    expect(decoded.moments.map((moment) => moment.key), ['wake_up', 'coffee']);
    expect(momentTitle(decoded.moments.first.key, 'zh', 1), '起床');
    expect(momentTitle(decoded.moments.first.key, 'en', 1), 'Wake up');
    expect(decoded.roomCode, isNull);
  });

  test('built-in templates keep unique identities and translatable slots', () {
    expect(storyTemplates.length, 13);
    expect(
      storyTemplates.map((template) => template.key).toSet().length,
      storyTemplates.length,
    );
    for (final template in storyTemplates) {
      expect(template.momentKeys.length, 7);
      for (var index = 0; index < template.momentKeys.length; index++) {
        expect(
          momentTitle(template.momentKeys[index], 'zh', index + 1),
          isNotEmpty,
        );
        expect(
          momentTitle(template.momentKeys[index], 'en', index + 1),
          isNotEmpty,
        );
      }
    }
  });

  test('seven-day filming uses calendar days rather than 24-hour windows', () {
    final story = sampleStory(
      mode: StoryMode.sevenDay,
      start: DateTime(2026, 9, 26, 23, 50),
    );
    expect(story.canRecord(0, DateTime(2026, 9, 26, 23, 55)), isTrue);
    expect(story.canRecord(0, DateTime(2026, 9, 27, 0, 1)), isFalse);
    expect(story.canRecord(1, DateTime(2026, 9, 27, 0, 1)), isTrue);
  });

  test(
    'saving a new take preserves the previous take until replacement commits',
    () async {
      final root = await Directory.systemTemp.createTemp('one-day-store-test-');
      addTearDown(() => root.delete(recursive: true));
      final store = await StoryStore.open(root);
      final now = DateTime.now();
      final story = sampleStory(start: now);
      await store.add(story);

      final firstSource = File('${root.path}/first.mp4')
        ..writeAsBytesSync([1, 2, 3]);
      await store.saveClip(story.id, 0, firstSource);
      final first = store.clipFile(store.find(story.id)!, 0);
      expect(await first.exists(), isTrue);

      final nextSource = File('${root.path}/next.mp4')
        ..writeAsBytesSync([4, 5, 6]);
      await store.saveClip(story.id, 0, nextSource);
      final next = store.clipFile(store.find(story.id)!, 0);
      expect(await next.readAsBytes(), [4, 5, 6]);
      expect(await first.exists(), isFalse);

      final reopened = await StoryStore.open(root);
      expect(reopened.find(story.id)!.recordedCount, 1);
      expect(
        await reopened.clipFile(reopened.find(story.id)!, 0).readAsBytes(),
        [4, 5, 6],
      );
    },
  );
}
