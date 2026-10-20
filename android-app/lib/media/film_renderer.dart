import 'dart:io';

import 'package:flutter/services.dart';

import '../data/story_store.dart';
import '../domain/story.dart';
import '../domain/templates.dart';

class FilmRenderer {
  static const _channel = MethodChannel('com.cassie.one_day/media');

  Future<File> render(Story story, StoryStore store, String language) async {
    final paths = <String>[];
    final labels = <String>[];
    for (var index = 0; index < story.moments.length; index++) {
      if (!story.moments[index].isRecorded) continue;
      final file = store.clipFile(story, index);
      if (!await file.exists()) {
        throw StateError('A source clip is missing');
      }
      paths.add(file.path);
      labels.add(
        story.moments[index].prompt ??
            momentTitle(story.moments[index].key, language, index + 1),
      );
    }
    if (paths.isEmpty) throw StateError('Record a moment first');

    final output = store.filmFile(story);
    await output.parent.create(recursive: true);
    final result = await _channel.invokeMethod<String>('render', {
      'paths': paths,
      'labels': labels,
      'output': output.path,
      'orientation': story.orientation.name,
    });
    if (result == null || !await File(result).exists()) {
      throw StateError('Film export did not create a file');
    }
    return File(result);
  }

  Future<void> saveToGallery(File film, String title) async {
    await _channel.invokeMethod<String>('saveToGallery', {
      'path': film.path,
      'title': title,
    });
  }
}
