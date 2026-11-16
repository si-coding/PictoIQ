import 'dart:typed_data';

import 'package:flutter/material.dart';

/// One photo in [PhotoViewerPage]: a small preview to show at once, and a way
/// to load a sharper picture.
class ViewerPhoto {
  const ViewerPhoto({
    required this.title,
    required this.preview,
    required this.loadLarge,
    this.details = const [],
    this.isPrivate = false,
    this.onPrivateChanged,
  });

  /// True when the person marked this photo private: it is never shared or
  /// put in a reel.
  final bool isPrivate;

  /// Called when the person marks or unmarks the photo as private. When null
  /// the viewer has no private button.
  final ValueChanged<bool>? onPrivateChanged;

  final String title;
  final Uint8List? preview;
  final Future<Uint8List?> Function() loadLarge;

  /// Facts about how this photo was judged. When not empty, the viewer shows
  /// an info button that opens them as "Why is this here?".
  final List<String> details;
}

/// Opens the "Why is this here?" panel with [details].
Future<void> showPhotoDetails(
  BuildContext context,
  String title,
  List<String> details,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          shrinkWrap: true,
          children: [
            const Text(
              'Why is this here?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            for (final line in details)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(line, style: const TextStyle(fontSize: 14)),
              ),
            const SizedBox(height: 4),
            const Text(
              'All of this was worked out on your phone. Nothing was sent anywhere.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
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
  late final List<bool> _private = [
    for (final photo in widget.photos) photo.isPrivate,
  ];

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
        actions: [
          if (photos[_index].onPrivateChanged != null)
            IconButton(
              icon: Icon(
                _private[_index] ? Icons.lock : Icons.lock_open_outlined,
              ),
              tooltip: _private[_index]
                  ? 'Private: never shared. Tap to undo'
                  : 'Mark as private (never shared)',
              onPressed: () {
                final value = !_private[_index];
                setState(() => _private[_index] = value);
                photos[_index].onPrivateChanged?.call(value);
              },
            ),
          if (photos[_index].details.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'Why is this here?',
              onPressed: () => showPhotoDetails(
                context,
                photos[_index].title,
                photos[_index].details,
              ),
            ),
        ],
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
