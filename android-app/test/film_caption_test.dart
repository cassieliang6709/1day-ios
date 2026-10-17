import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_day/data/story_store.dart';
import 'package:one_day/domain/story.dart';
import 'package:one_day/media/film_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native export receives custom captions and skips unrecorded moments',
    () async {
      final root = await Directory.systemTemp.createTemp('oneday-caption-');
      addTearDown(() => root.delete(recursive: true));
      final store = await StoryStore.open(root);
      final story = Story(
        id: 'caption-test',
        title: 'Walk',
        startDate: DateTime.now(),
        mode: StoryMode.oneDay,
        clipSeconds: 2,
        orientation: StoryOrientation.portrait,
        templateKey: 'custom',
        moments: const [
          StoryMoment(
            key: 'custom_1',
            prompt: '湖边的风',
            clipFileName: 'first.mp4',
          ),
          StoryMoment(key: 'custom_2', prompt: 'Not yet filmed'),
          StoryMoment(key: 'coffee', clipFileName: 'second.mp4'),
        ],
      );
      for (final index in [0, 2]) {
        final clip = store.clipFile(story, index);
        await clip.parent.create(recursive: true);
        await clip.writeAsBytes([1]);
      }
      const channel = MethodChannel('com.cassie.one_day/media');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'render');
            expect(call.arguments['labels'], ['湖边的风', 'Coffee']);
            expect(call.arguments['paths'], hasLength(2));
            final output = File(call.arguments['output'] as String);
            await output.writeAsBytes([1]);
            return output.path;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      expect(
        (await FilmRenderer().render(story, store, 'en')).path,
        store.filmFile(story).path,
      );
    },
  );
}
