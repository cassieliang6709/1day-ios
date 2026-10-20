import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/story.dart';

/// The solo app keeps metadata and original clips in private app storage.
/// Writing a new clip never removes the previous take until metadata is saved.
class StoryStore extends ChangeNotifier {
  StoryStore._(this.root, this._stories);

  final Directory root;
  List<Story> _stories;

  List<Story> get stories => List.unmodifiable(_stories);

  static Future<StoryStore> open(Directory root) async {
    await root.create(recursive: true);
    final manifest = File('${root.path}/stories.json');
    if (!await manifest.exists()) return StoryStore._(root, []);
    final decoded =
        jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    if (decoded['version'] != 1) {
      throw const FormatException('Unsupported story library version');
    }
    final stories = (decoded['stories'] as List)
        .map((item) => Story.fromJson(item as Map<String, dynamic>))
        .toList();
    return StoryStore._(root, stories);
  }

  Story? find(String id) {
    for (final story in _stories) {
      if (story.id == id) return story;
    }
    return null;
  }

  File clipFile(Story story, int index) {
    final name = story.moments[index].clipFileName;
    if (name == null) throw StateError('Moment has no clip');
    return File('${root.path}/clips/${story.id}/$name');
  }

  File filmFile(Story story) => File('${root.path}/films/${story.id}.mp4');

  Future<void> add(Story story) async {
    if (find(story.id) != null) throw StateError('Story already exists');
    final updated = [story, ..._stories];
    await _write(updated);
    _stories = updated;
    notifyListeners();
  }

  Future<void> saveClip(String storyId, int index, File source) async {
    final story = find(storyId);
    if (story == null) throw StateError('Story not found');
    if (!story.canRecord(index, DateTime.now())) {
      throw StateError('This moment is not available today');
    }
    if (!await source.exists() || await source.length() == 0) {
      throw StateError('Recorded video is missing');
    }

    final directory = Directory('${root.path}/clips/$storyId');
    await directory.create(recursive: true);
    final name = 'day${index + 1}_${DateTime.now().microsecondsSinceEpoch}.mp4';
    final destination = File('${directory.path}/$name');
    await source.copy(destination.path);
    final previous = story.moments[index].clipFileName;
    final updatedStory = story.withRecording(index, name, DateTime.now());
    final updated = _stories
        .map((candidate) => candidate.id == storyId ? updatedStory : candidate)
        .toList();
    try {
      await _write(updated);
    } catch (_) {
      await destination.delete();
      rethrow;
    }
    _stories = updated;
    notifyListeners();
    if (previous != null && previous != name) {
      final oldFile = File('${directory.path}/$previous');
      try {
        if (await oldFile.exists()) await oldFile.delete();
      } on FileSystemException {
        // The new take is already committed; cleanup can happen later.
      }
    }
    final oldFilm = filmFile(story);
    try {
      if (await oldFilm.exists()) await oldFilm.delete();
    } on FileSystemException {
      // The stale film stays playable until the next export replaces it.
    }
  }

  Future<void> _write(List<Story> stories) async {
    final manifest = File('${root.path}/stories.json');
    final pending = File('${root.path}/stories.json.pending');
    final payload = jsonEncode({
      'version': 1,
      'stories': stories.map((story) => story.toJson()).toList(),
    });
    await pending.writeAsString(payload, flush: true);
    await pending.rename(manifest.path);
  }
}
