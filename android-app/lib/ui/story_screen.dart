import 'package:flutter/material.dart';

import '../data/story_store.dart';
import '../domain/story.dart';
import '../domain/templates.dart';
import 'app_style.dart';
import 'film_screen.dart';
import 'record_screen.dart';

class StoryScreen extends StatelessWidget {
  const StoryScreen({super.key, required this.store, required this.storyId});

  final StoryStore store;
  final String storyId;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final story = store.find(storyId);
      if (story == null) {
        return Scaffold(
          body: Center(child: Text(say(context, '故事不存在。', 'Story not found.'))),
        );
      }
      final language = Localizations.localeOf(context).languageCode;
      return Scaffold(
        appBar: AppBar(title: const Text('1Day')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Text(
                story.title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '${story.mode == StoryMode.oneDay ? say(context, '一天的故事', 'One-day story') : say(context, '七天的故事', 'Seven-day story')}  ·  '
                '${story.clipSeconds} s  ·  ${story.recordedCount}/${story.moments.length}',
                style: const TextStyle(color: Color(0xFF5B7099)),
              ),
              const SizedBox(height: 22),
              LinearProgressIndicator(
                value: story.recordedCount / story.moments.length,
                minHeight: 7,
                borderRadius: BorderRadius.circular(7),
                backgroundColor: oneDayMist,
              ),
              const SizedBox(height: 25),
              for (var index = 0; index < story.moments.length; index++) ...[
                _MomentRow(
                  store: store,
                  story: story,
                  index: index,
                  title:
                      story.moments[index].prompt ??
                      momentTitle(
                        story.moments[index].key,
                        language,
                        index + 1,
                      ),
                ),
                const SizedBox(height: 11),
              ],
              if (story.recordedCount > 0) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          FilmScreen(store: store, storyId: story.id),
                    ),
                  ),
                  icon: const Icon(Icons.movie_creation_outlined),
                  label: Text(say(context, '生成我的短片', 'Make my film')),
                ),
              ],
              const SizedBox(height: 15),
              Text(
                say(
                  context,
                  '每个时刻只保留你选中的那一段；重拍会替换旧片段。',
                  'Each moment keeps one chosen take. Re-recording replaces it.',
                ),
                style: const TextStyle(color: Color(0xFF7186AA), fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _MomentRow extends StatelessWidget {
  const _MomentRow({
    required this.store,
    required this.story,
    required this.index,
    required this.title,
  });

  final StoryStore store;
  final Story story;
  final int index;
  final String title;

  @override
  Widget build(BuildContext context) {
    final moment = story.moments[index];
    final available = story.canRecord(index, DateTime.now());
    final recorded = moment.isRecorded;
    final status = recorded
        ? say(context, '已拍摄 · 点按预览', 'Recorded · tap to preview')
        : available
        ? say(context, '拍下这个时刻', 'Film this moment')
        : story.mode == StoryMode.sevenDay && story.currentDay < index + 1
        ? say(context, '第 ${index + 1} 天开放', 'Opens on day ${index + 1}')
        : say(context, '已错过', 'Past moment');
    return BluePanel(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: recorded
            ? () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ClipScreen(store: store, storyId: story.id, index: index),
                ),
              )
            : available
            ? () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RecordScreen(
                    store: store,
                    storyId: story.id,
                    index: index,
                  ),
                ),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: recorded ? oneDayBlue : oneDayMist,
                foregroundColor: recorded ? Colors.white : oneDayBlue,
                child: recorded
                    ? const Icon(Icons.check_rounded)
                    : Text(
                        '${index + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: oneDayNavy,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      status,
                      style: const TextStyle(
                        color: Color(0xFF5B7099),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (recorded || available)
                Icon(
                  recorded
                      ? Icons.play_circle_outline
                      : Icons.videocam_outlined,
                  color: oneDayBlue,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
