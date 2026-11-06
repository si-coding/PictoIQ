import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Plays one video full screen so it can be looked at before an album is
/// chosen. [loadUrl] gives a `content://` address or a file path.
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key, required this.loadUrl, this.poster});

  final Future<String?> Function() loadUrl;

  /// A still picture shown while loading, or if the video cannot be played.
  final Uint8List? poster;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    VideoPlayerController? controller;
    try {
      final url = await widget.loadUrl();
      if (url == null || url.isEmpty) throw StateError('No video address.');
      controller = url.startsWith('content://')
          ? VideoPlayerController.contentUri(Uri.parse(url))
          : url.startsWith('/')
          ? VideoPlayerController.file(File(url))
          : VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.play();
      setState(() => _controller = controller);
    } catch (error) {
      debugPrint('Video could not be played: ${error.runtimeType}');
      await controller?.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: controller != null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AspectRatio(
                      aspectRatio: controller.value.aspectRatio == 0
                          ? 16 / 9
                          : controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
                    const SizedBox(height: 8),
                    VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: controller,
                      builder: (context, value, _) => IconButton(
                        iconSize: 48,
                        color: Colors.white,
                        tooltip: value.isPlaying ? 'Pause' : 'Play',
                        icon: Icon(
                          value.isPlaying
                              ? Icons.pause_circle_outline
                              : Icons.play_circle_outline,
                        ),
                        onPressed: () => value.isPlaying
                            ? controller.pause()
                            : controller.play(),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.poster != null)
                      Flexible(
                        child: Image.memory(widget.poster!, fit: BoxFit.contain),
                      ),
                    const SizedBox(height: 16),
                    if (_failed)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'This video could not be played here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    else
                      const CircularProgressIndicator(),
                  ],
                ),
        ),
      ),
    );
  }
}
