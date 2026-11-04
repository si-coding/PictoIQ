import 'dart:typed_data';

import 'package:flutter/material.dart';

/// One photo in [PhotoViewerPage]: a small preview to show at once, and a way
/// to load a sharper picture.
class ViewerPhoto {
  const ViewerPhoto({
    required this.title,
    required this.preview,
    required this.loadLarge,
  });

  final String title;
  final Uint8List? preview;
  final Future<Uint8List?> Function() loadLarge;
}

/// Full-screen viewer. Swipe left or right for the next or previous photo;
/// pinch or double-finger zoom to look closer (swiping is paused while zoomed
/// in so panning does not turn the page).
class PhotoViewerPage extends StatefulWidget {
  const PhotoViewerPage({
    super.key,
    required this.photos,
    this.initialIndex = 0,
  });

  final List<ViewerPhoto> photos;
  final int initialIndex;

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  final ValueNotifier<bool> _zoomed = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _controller.dispose();
    _zoomed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          photos.length > 1
              ? '${_index + 1} of ${photos.length}  ·  ${photos[_index].title}'
              : photos[_index].title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
      ),
      body: ValueListenableBuilder<bool>(
        valueListenable: _zoomed,
        builder: (context, zoomed, _) => PageView.builder(
          controller: _controller,
          physics: zoomed
              ? const NeverScrollableScrollPhysics()
              : const PageScrollPhysics(),
          itemCount: photos.length,
          onPageChanged: (index) {
            _zoomed.value = false;
            setState(() => _index = index);
          },
          itemBuilder: (context, index) => _ViewerPage(
            key: ValueKey(index),
            photo: photos[index],
            onZoomChanged: (zoomed) {
              if (index == _index) _zoomed.value = zoomed;
            },
          ),
        ),
      ),
    );
  }
}

class _ViewerPage extends StatefulWidget {
  const _ViewerPage({
    super.key,
    required this.photo,
    required this.onZoomChanged,
  });

  final ViewerPhoto photo;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<_ViewerPage> {
  final TransformationController _transform = TransformationController();
  Uint8List? _shown;
  bool _loading = true;
  bool _zoomedIn = false;

  @override
  void initState() {
    super.initState();
    _shown = widget.photo.preview;
    _transform.addListener(_onTransform);
    widget.photo.loadLarge().then((bytes) {
      if (!mounted) return;
      setState(() {
        _shown = bytes ?? _shown;
        _loading = false;
      });
    }).catchError((Object _) {
      if (mounted) setState(() => _loading = false);
    });
  }

  void _onTransform() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.02;
    if (zoomed == _zoomedIn) return;
    setState(() => _zoomedIn = zoomed);
    widget.onZoomChanged(zoomed);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (shown != null)
          InteractiveViewer(
            transformationController: _transform,
            minScale: 1,
            maxScale: 6,
            // Panning only while zoomed in, so a swipe turns the page.
            panEnabled: _zoomedIn,
            child: Center(
              child: Image.memory(
                shown,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                filterQuality: FilterQuality.high,
              ),
            ),
          )
        else if (!_loading)
          const Center(
            child: Text(
              'This photo cannot be shown.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        if (_loading)
          const Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Chip(
                avatar: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                label: Text('Loading sharper photo…'),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
      ],
    );
  }
}
