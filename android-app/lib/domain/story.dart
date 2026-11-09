import 'dart:math';

enum StoryMode { oneDay, sevenDay }

enum StoryOrientation { portrait, landscape }

/// A slot has a stable key. Its translated label is never used as its identity.
class StoryMoment {
  const StoryMoment({
    required this.key,
    this.clipFileName,
    this.recordedAt,
    this.prompt,
  });

  final String key;
  final String? prompt;
  final String? clipFileName;
  final DateTime? recordedAt;

  bool get isRecorded => clipFileName != null;

  StoryMoment withRecording(String fileName, DateTime at) => StoryMoment(
    key: key,
    clipFileName: fileName,
    recordedAt: at,
    prompt: prompt,
  );

  Map<String, Object?> toJson() => {
    'key': key,
    if (prompt != null) 'prompt': prompt,
    'clipFileName': clipFileName,
    'recordedAt': recordedAt?.toUtc().toIso8601String(),
  };

  factory StoryMoment.fromJson(Map<String, dynamic> json) => StoryMoment(
    key: json['key'] as String,
    prompt: json['prompt'] as String?,
    clipFileName: json['clipFileName'] as String?,
    recordedAt: json['recordedAt'] == null
        ? null
        : DateTime.parse(json['recordedAt'] as String).toLocal(),
  );
}

class Story {
  const Story({
    required this.id,
    required this.title,
    required this.startDate,
    required this.mode,
    required this.clipSeconds,
    required this.orientation,
    required this.templateKey,
    required this.moments,
    this.roomCode,
  });

  final String id;
  final String title;
  final DateTime startDate;
  final StoryMode mode;
  final int clipSeconds;
  final StoryOrientation orientation;
  final String templateKey;
  final List<StoryMoment> moments;

  /// Reserved for a future shared backend. A local story is always null.
  final String? roomCode;

  int get recordedCount => moments.where((moment) => moment.isRecorded).length;
  bool get isComplete => recordedCount == moments.length;

  int get currentDay {
    final start = DateTime.utc(startDate.year, startDate.month, startDate.day);
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    return today.difference(start).inDays + 1;
  }

  bool canRecord(int index, DateTime now) {
    if (index < 0 || index >= moments.length) return false;
    final start = DateTime.utc(startDate.year, startDate.month, startDate.day);
    final day =
        DateTime.utc(now.year, now.month, now.day).difference(start).inDays + 1;
    return mode == StoryMode.oneDay ? day == 1 : day == index + 1;
  }

  Story withRecording(int index, String fileName, DateTime at) {
    if (index < 0 || index >= moments.length) {
      throw RangeError.index(index, moments);
    }
    final updated = List<StoryMoment>.of(moments);
    updated[index] = updated[index].withRecording(fileName, at);
    return Story(
      id: id,
      title: title,
      startDate: startDate,
      mode: mode,
      clipSeconds: clipSeconds,
      orientation: orientation,
      templateKey: templateKey,
      moments: updated,
      roomCode: roomCode,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'startDate': startDate.toUtc().toIso8601String(),
    'mode': mode.name,
    'clipSeconds': clipSeconds,
    'orientation': orientation.name,
    'templateKey': templateKey,
    'moments': moments.map((moment) => moment.toJson()).toList(),
    'roomCode': roomCode,
  };

  factory Story.fromJson(Map<String, dynamic> json) => Story(
    id: json['id'] as String,
    title: json['title'] as String,
    startDate: DateTime.parse(json['startDate'] as String).toLocal(),
    mode: StoryMode.values.byName(json['mode'] as String),
    clipSeconds: json['clipSeconds'] as int,
    orientation: StoryOrientation.values.byName(json['orientation'] as String),
    templateKey: json['templateKey'] as String,
    moments: (json['moments'] as List)
        .map((item) => StoryMoment.fromJson(item as Map<String, dynamic>))
        .toList(),
    roomCode: json['roomCode'] as String?,
  );

  static String newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
