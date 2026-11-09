import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../data/story_store.dart';
import '../domain/templates.dart';
import '../media/film_renderer.dart';
import 'app_style.dart';
import 'record_screen.dart';

class FilmScreen extends StatefulWidget {
  const FilmScreen({super.key, required this.store, required this.storyId});

  final StoryStore store;
  final String storyId;

  @override
  State<FilmScreen> createState() => _FilmScreenState();
}

class _FilmScreenState extends State<FilmScreen> {
  final renderer = FilmRenderer();
  VideoPlayerController? player;
  File? film;
  String? error;
  bool saving = false;
  bool loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!loading && film == null && player == null && error == null) {
      _render();
    }
  }

  Future<void> _render() async {
    loading = true;
    try {
      final story = widget.store.find(widget.storyId)!;
      final output = await renderer.render(
        story,
        widget.store,
        Localizations.localeOf(context).languageCode,
      );
      final video = VideoPlayerController.file(output);
      await video.initialize();
      if (!mounted) {
        await video.dispose();
        return;
      }
      setState(() {
        film = output;
        player = video;
      });
      await video.play();
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      loading = false;
    }
  }

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  Future<void> _saveGallery() async {
    final output = film;
    if (output == null || saving) return;
    setState(() => saving = true);
    try {
      await renderer.saveToGallery(
        output,
        widget.store.find(widget.storyId)!.title,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(say(context, '已保存到相册。', 'Saved to Photos.'))),
      );
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${say(context, '保存失败', 'Could not save')}: $exception',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _share() async {
    final output = film;
    if (output == null) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(output.path, mimeType: 'video/mp4')],
        title: widget.store.find(widget.storyId)?.title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(say(context, '我的短片', 'My film'))),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: player?.value.isInitialized == true
                    ? AspectRatio(
                        aspectRatio: player!.value.aspectRatio,
                        child: GestureDetector(
                          onTap: () => player!.value.isPlaying
                              ? player!.pause()
                              : player!.play(),
                          child: VideoPlayer(player!),
                        ),
                      )
                    : error != null
                    ? Text(
                        '${say(context, '成片暂时无法生成。', 'Could not make the film.')}\n$error',
                        textAlign: TextAlign.center,
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            say(
                              context,
                              '正在把片段拼成短片…',
                              'Putting your moments together…',
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            if (film != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: saving ? null : _saveGallery,
                icon: const Icon(Icons.download_outlined),
                label: Text(say(context, '保存到相册', 'Save to Photos')),
              ),
              const SizedBox(height: 9),
              OutlinedButton.icon(
                onPressed: _share,
                icon: const Icon(Icons.share_outlined),
                label: Text(say(context, '分享 MP4', 'Share MP4')),
              ),
            ] else if (error != null)
              FilledButton(
                onPressed: () {
                  setState(() => error = null);
                  _render();
                },
                child: Text(say(context, '再试一次', 'Try again')),
              ),
          ],
        ),
      ),
    ),
  );
}

class ClipScreen extends StatefulWidget {
  const ClipScreen({
    super.key,
    required this.store,
    required this.storyId,
    required this.index,
  });

  final StoryStore store;
  final String storyId;
  final int index;

  @override
  State<ClipScreen> createState() => _ClipScreenState();
}

class _ClipScreenState extends State<ClipScreen> {
  VideoPlayerController? player;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final story = widget.store.find(widget.storyId)!;
      final video = VideoPlayerController.file(
        widget.store.clipFile(story, widget.index),
      );
      await video.initialize();
      if (!mounted) {
        await video.dispose();
        return;
      }
      setState(() => player = video);
      await video.play();
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    }
  }

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.store.find(widget.storyId)!;
    final language = Localizations.localeOf(context).languageCode;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          story.moments[widget.index].prompt ??
              momentTitle(
                story.moments[widget.index].key,
                language,
                widget.index + 1,
              ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: player?.value.isInitialized == true
                      ? AspectRatio(
                          aspectRatio: player!.value.aspectRatio,
                          child: GestureDetector(
                            onTap: () => player!.value.isPlaying
                                ? player!.pause()
                                : player!.play(),
                            child: VideoPlayer(player!),
                          ),
                        )
                      : Text(error ?? say(context, '正在打开片段…', 'Opening clip…')),
                ),
              ),
              if (story.canRecord(widget.index, DateTime.now()))
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => RecordScreen(
                        store: widget.store,
                        storyId: widget.storyId,
                        index: widget.index,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.replay),
                  label: Text(say(context, '重拍这个时刻', 'Re-record this moment')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
