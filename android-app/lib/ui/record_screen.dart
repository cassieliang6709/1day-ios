import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../data/story_store.dart';
import '../domain/story.dart';
import '../domain/templates.dart';
import 'app_style.dart';

class RecordScreen extends StatefulWidget {
  const RecordScreen({
    super.key,
    required this.store,
    required this.storyId,
    required this.index,
  });

  final StoryStore store;
  final String storyId;
  final int index;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  VideoPlayerController? _player;
  List<CameraDescription> _cameras = [];
  CameraLensDirection _lens = CameraLensDirection.back;
  File? _captured;
  Timer? _timer;
  DateTime? _startedAt;
  String? _error;
  bool _initializing = false;
  bool _recording = false;
  bool _stopping = false;
  bool _saving = false;
  double _elapsed = 0;

  Story get story => widget.store.find(widget.storyId)!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final orientations = story.orientation == StoryOrientation.portrait
        ? [DeviceOrientation.portraitUp]
        : [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight];
    unawaited(SystemChrome.setPreferredOrientations(orientations));
    unawaited(_initializeCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_camera == null && _captured == null) unawaited(_initializeCamera());
      return;
    }
    if (_recording && !_stopping) {
      unawaited(_stopRecording());
    } else if (_camera != null) {
      final old = _camera;
      _camera = null;
      unawaited(old!.dispose());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_camera?.dispose() ?? Future<void>.value());
    unawaited(_player?.dispose() ?? Future<void>.value());
    final leftover = _captured;
    if (leftover != null) {
      unawaited(leftover.delete().catchError((_) => leftover));
    }
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    if (_initializing || _captured != null) return;
    _initializing = true;
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw StateError('No camera available');
      final description = _cameras.firstWhere(
        (camera) => camera.lensDirection == _lens,
        orElse: () => _cameras.first,
      );
      final controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: true,
      );
      await controller.initialize();
      await controller.lockCaptureOrientation(
        story.orientation == StoryOrientation.portrait
            ? DeviceOrientation.portraitUp
            : DeviceOrientation.landscapeLeft,
      );
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      _initializing = false;
    }
  }

  Future<void> _switchCamera() async {
    if (_recording || _stopping || _cameras.length < 2) return;
    final previous = _camera;
    setState(() => _camera = null);
    await previous?.dispose();
    _lens = _lens == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    await _initializeCamera();
  }

  Future<void> _startRecording() async {
    final camera = _camera;
    if (camera == null || _recording || _stopping) return;
    try {
      await camera.startVideoRecording();
      if (!mounted) return;
      _startedAt = DateTime.now();
      setState(() {
        _recording = true;
        _elapsed = 0;
      });
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        final start = _startedAt;
        if (!mounted || start == null) return;
        final elapsed = DateTime.now().difference(start).inMilliseconds / 1000;
        setState(() => _elapsed = elapsed);
        if (elapsed >= story.clipSeconds) unawaited(_stopRecording());
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _stopRecording() async {
    final camera = _camera;
    if (!_recording || _stopping || camera == null) return;
    _stopping = true;
    _timer?.cancel();
    File? videoFile;
    try {
      final video = await camera.stopVideoRecording();
      await camera.dispose();
      _camera = null;
      final file = File(video.path);
      videoFile = file;
      if (!mounted) {
        await file.delete();
        return;
      }
      final player = VideoPlayerController.file(file);
      await player.initialize();
      if (!mounted) {
        await player.dispose();
        await file.delete();
        return;
      }
      setState(() {
        _captured = file;
        _player = player;
        _recording = false;
        _elapsed = 0;
      });
      await player.play();
    } catch (error) {
      final leftover = videoFile;
      if (leftover != null && await leftover.exists()) await leftover.delete();
      if (mounted) {
        setState(() {
          _error = error.toString();
          _recording = false;
        });
      }
    } finally {
      _stopping = false;
    }
  }

  Future<void> _retake() async {
    final file = _captured;
    final player = _player;
    setState(() {
      _captured = null;
      _player = null;
    });
    await player?.dispose();
    if (file != null && await file.exists()) await file.delete();
    await _initializeCamera();
  }

  Future<void> _save() async {
    final file = _captured;
    if (file == null || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.store.saveClip(widget.storyId, widget.index, file);
      if (!mounted) return;
      await _player?.dispose();
      _player = null;
      _captured = null;
      if (await file.exists()) await file.delete();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    final label =
        story.moments[widget.index].prompt ??
        momentTitle(
          story.moments[widget.index].key,
          language,
          widget.index + 1,
        );
    final camera = _camera;
    final player = _player;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(label),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (camera != null && !_recording && _cameras.length > 1)
            IconButton(
              tooltip: say(context, '切换摄像头', 'Switch camera'),
              onPressed: _switchCamera,
              icon: const Icon(Icons.flip_camera_android),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: player != null && player.value.isInitialized
                    ? AspectRatio(
                        aspectRatio: player.value.aspectRatio,
                        child: GestureDetector(
                          onTap: () => player.value.isPlaying
                              ? player.pause()
                              : player.play(),
                          child: VideoPlayer(player),
                        ),
                      )
                    : camera != null && camera.value.isInitialized
                    ? CameraPreview(camera)
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error == null
                                  ? say(context, '正在打开相机…', 'Opening camera…')
                                  : say(
                                      context,
                                      '相机暂时无法打开。请检查相机和麦克风权限。',
                                      'Could not open the camera. Check camera and microphone access.',
                                    ),
                              style: const TextStyle(color: Colors.white),
                              textAlign: TextAlign.center,
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: _initializeCamera,
                                child: Text(say(context, '重试', 'Try again')),
                              ),
                            ],
                          ],
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: player != null
                  ? Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _saving ? null : _retake,
                            child: Text(say(context, '重拍', 'Retake')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _saving ? null : _save,
                            child: Text(
                              _saving
                                  ? say(context, '保存中…', 'Saving…')
                                  : say(context, '保留这段', 'Keep this clip'),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Text(
                          _recording
                              ? '${_elapsed.clamp(0, story.clipSeconds).toStringAsFixed(1)} / ${story.clipSeconds} s'
                              : say(
                                  context,
                                  '拍 ${story.clipSeconds} 秒的小片段',
                                  'Film ${story.clipSeconds} seconds',
                                ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 68,
                          width: 68,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _recording
                                  ? Colors.redAccent
                                  : Colors.white,
                              shape: const CircleBorder(),
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: camera == null || _stopping
                                ? null
                                : _recording
                                ? _stopRecording
                                : _startRecording,
                            child: Icon(
                              _recording ? Icons.stop_rounded : Icons.circle,
                              color: _recording ? Colors.white : oneDayBlue,
                              size: 32,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
