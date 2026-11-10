import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:pictoiq_mobile/core/video/video_reel_service.dart';
import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart';
import 'package:pictoiq_mobile/features/settings/app_settings.dart';

const _green = Color(0xFF54744C);

class ReelConfiguration {
  const ReelConfiguration({
    required this.photos,
    required this.audioPath,
    required this.title,
    required this.titleStyle,
  });

  final List<FolderScanPhoto> photos;
  final String? audioPath;
  final String title;
  final ReelTitleStyle titleStyle;
}

class ReelConfigurationPage extends StatefulWidget {
  const ReelConfigurationPage({
    super.key,
    required this.photos,
    required this.maxPhotos,
    required this.secondsPerPhoto,
    required this.transitionMillis,
    required this.titleStyle,
    required this.pickAudio,
    required this.discardAudio,
    required this.reelProgress,
    required this.onCreate,
    required this.onCancel,
  });

  final List<FolderScanPhoto> photos;
  final int maxPhotos;
  final int secondsPerPhoto;
  final int transitionMillis;
  final ReelTitleStyle titleStyle;
  final Future<String?> Function() pickAudio;
  final Future<void> Function(String path) discardAudio;
  final Stream<double> reelProgress;
  final Future<void> Function(ReelConfiguration configuration) onCreate;
  final Future<void> Function() onCancel;

  @override
  State<ReelConfigurationPage> createState() => _ReelConfigurationPageState();
}

class _ReelConfigurationPageState extends State<ReelConfigurationPage> {
  late final List<FolderScanPhoto> _photos = [...widget.photos];
  late final TextEditingController _titleController = TextEditingController();
  late ReelTitleStyle _titleStyle = widget.titleStyle;
  String? _audioPath;
  bool _choosingAudio = false;
  bool _creating = false;
  bool _cancelling = false;
  double _progress = 0;
  StreamSubscription<double>? _progressSubscription;
  final _scrollController = ScrollController();
  final _scrollKey = GlobalKey();
  Timer? _autoScrollTimer;
  double _autoScrollStep = 0;

  @override
  void initState() {
    super.initState();
    _progressSubscription = widget.reelProgress.listen(
      (progress) {
        if (mounted && _creating) {
          setState(() => _progress = progress.clamp(0, 1));
        }
      },
      onError: (Object error, StackTrace stack) {
        debugPrint('Reel progress updates failed: $error\n$stack');
      },
    );
  }

  /// Scrolls the page while a photo is dragged near the top or bottom edge,
  /// so a photo can be moved further than the screen shows.
  void _autoScroll(double pointerY) {
    final box = _scrollKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    const zone = 90.0;
    if (pointerY < top + zone) {
      _autoScrollStep = -14;
    } else if (pointerY > bottom - zone) {
      _autoScrollStep = 14;
    } else {
      _stopAutoScroll();
      return;
    }
    _autoScrollTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      _scrollController.jumpTo(
        (position.pixels + _autoScrollStep).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  Future<void> _chooseAudio() async {
    if (_choosingAudio) return;
    setState(() => _choosingAudio = true);
    try {
      final path = await widget.pickAudio();
      if (!mounted) {
        if (path != null) unawaited(widget.discardAudio(path));
        return;
      }
      if (path != null) {
        final previousPath = _audioPath;
        setState(() => _audioPath = path);
        if (previousPath != null) await _discardAudio(previousPath);
      }
    } catch (error) {
      debugPrint('Reel audio selection failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not select an audio file.')),
        );
      }
    } finally {
      if (mounted) setState(() => _choosingAudio = false);
    }
  }

  Future<void> _discardAudio(String path) async {
    try {
      await widget.discardAudio(path);
    } catch (error) {
      debugPrint('Temporary reel audio cleanup failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not remove the temporary audio selection.'),
          ),
        );
      }
    }
  }

  void _removePhoto(FolderScanPhoto photo) {
    setState(() => _photos.removeWhere((item) => item.uri == photo.uri));
  }

  void _movePhoto(FolderScanPhoto source, FolderScanPhoto target) {
    final sourceIndex = _photos.indexWhere((item) => item.uri == source.uri);
    final targetIndex = _photos.indexWhere((item) => item.uri == target.uri);
    if (sourceIndex < 0 || targetIndex < 0 || sourceIndex == targetIndex) {
      return;
    }
    setState(() {
      _photos[sourceIndex] = target;
      _photos[targetIndex] = source;
    });
  }

  Future<void> _createReel() async {
    if (_creating || _photos.isEmpty) return;
    final configuration = ReelConfiguration(
      photos: List.unmodifiable(_photos),
      audioPath: _audioPath,
      title: _titleController.text.trim(),
      titleStyle: _titleStyle,
    );
    setState(() {
      _creating = true;
      _progress = 0;
    });

    try {
      await widget.onCreate(configuration);
    } catch (error, stack) {
      if (error is ReelCreationCancelledException) return;
      debugPrint('Photo reel creation failed: $error\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Could not create the reel. Please try again.'),
            ),
          );
      }
    } finally {
      final audioPath = _audioPath;
      if (audioPath != null) {
        await _discardAudio(audioPath);
      }
      if (mounted) {
        setState(() {
          _audioPath = null;
          _creating = false;
          _cancelling = false;
          _progress = 0;
        });
      }
    }
  }

  Future<void> _cancelReel() async {
    if (!_creating || _cancelling) return;
    setState(() => _cancelling = true);
    try {
      await widget.onCancel();
    } catch (error, stack) {
      debugPrint('Reel cancellation request failed: $error\n$stack');
      if (mounted) {
        setState(() => _cancelling = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not cancel reel creation.')),
        );
      }
    }
  }

  @override
  void dispose() {
    unawaited(_progressSubscription?.cancel());
    _stopAutoScroll();
    _scrollController.dispose();
    _titleController.dispose();
    final audioPath = _audioPath;
    if (audioPath != null) {
      unawaited(_discardAudio(audioPath));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _titleController.text.trim();
    return PopScope(
      canPop: !_creating,
      child: Scaffold(
        appBar: AppBar(title: const Text('Create your reel')),
        body: AbsorbPointer(
          absorbing: _creating,
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: CustomScrollView(
              key: _scrollKey,
              controller: _scrollController,
              slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                sliver: SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF0E6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.drag_indicator, color: _green),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Press and hold a photo, then drag it onto another photo to change the order.',
                            style: TextStyle(
                              color: Color(0xFF43523E),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    '${_photos.length} of ${widget.maxPhotos} photos · '
                    '${widget.secondsPerPhoto} seconds each · '
                    '${widget.transitionMillis == 0 ? 'No transition' : '${widget.transitionMillis} ms crossfade'}',
                    style: const TextStyle(
                      color: Color(0xFF687064),
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _titleController,
                        maxLength: 60,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Text on the first photo (optional)',
                          hintText: 'Add a title to your reel',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.title),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Title style',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final style in ReelTitleStyle.values)
                            ChoiceChip(
                              label: Text(_styleLabel(style)),
                              selected: _titleStyle == style,
                              onSelected: (_) =>
                                  setState(() => _titleStyle = style),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: _choosingAudio ? null : _chooseAudio,
                        icon: _choosingAudio
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                _audioPath == null
                                    ? Icons.music_note_outlined
                                    : Icons.music_note,
                              ),
                        label: Text(
                          _audioPath == null
                              ? 'Add audio'
                              : 'Change audio · ${p.basename(_audioPath!)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_audioPath != null)
                        TextButton.icon(
                          onPressed: () {
                            final path = _audioPath!;
                            setState(() => _audioPath = null);
                            unawaited(_discardAudio(path));
                          },
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Remove audio'),
                        ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'Photo preview · drag to reorder',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: .86,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final photo = _photos[index];
                      return DragTarget<FolderScanPhoto>(
                        key: ValueKey('reel-photo-${photo.uri}'),
                        onAcceptWithDetails: (details) =>
                            _movePhoto(details.data, photo),
                        builder: (context, candidates, rejected) =>
                            LongPressDraggable<FolderScanPhoto>(
                              data: photo,
                              dragAnchorStrategy: pointerDragAnchorStrategy,
                              onDragUpdate: (details) =>
                                  _autoScroll(details.globalPosition.dy),
                              onDragEnd: (_) => _stopAutoScroll(),
                              onDraggableCanceled: (_, _) => _stopAutoScroll(),
                              feedback: Material(
                                color: Colors.transparent,
                                child: SizedBox(
                                  width: 150,
                                  height: 175,
                                  child: _photoPreview(photo, index, title),
                                ),
                              ),
                              childWhenDragging: Opacity(
                                opacity: .35,
                                child: _photoCard(photo, index, title),
                              ),
                              child: _photoCard(
                                photo,
                                index,
                                title,
                                isDropTarget: candidates.isNotEmpty,
                              ),
                            ),
                      );
                    },
                    childCount: _photos.length,
                  ),
                ),
              ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(14, 4, 14, 10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: _creating
                ? Semantics(
                    label: _progress == 0
                        ? 'Preparing your reel'
                        : 'Creating your reel, ${(_progress * 100).round()} percent',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(26),
                      child: SizedBox(
                        height: 52,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            LinearProgressIndicator(
                              value: _progress == 0 ? null : _progress,
                              minHeight: 52,
                              color: const Color(0xFFB9D4B3),
                              backgroundColor: const Color(0xFFE3EEDF),
                            ),
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  72,
                                  0,
                                ),
                                child: Text(
                                  _cancelling
                                      ? 'Cancelling reel…'
                                      : _progress == 0
                                      ? 'Preparing your reel…'
                                      : 'Creating your reel… ${(_progress * 100).floor()}%',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF2F3A2B),
                                  ),
                                ),
                              ),
                            ),
                            if (!_cancelling)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _cancelReel,
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF2F3A2B),
                                    minimumSize: const Size(68, 52),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                  ),
                                  child: const Text('Cancel'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  )
                : FilledButton.icon(
                    onPressed: _photos.isEmpty ? null : _createReel,
                    icon: const Icon(Icons.movie_creation_outlined, size: 20),
                    label: const Text('Create reel'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _photoCard(
    FolderScanPhoto photo,
    int index,
    String title, {
    bool isDropTarget = false,
  }) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        border: Border.all(
          color: isDropTarget ? _green : Colors.transparent,
          width: 3,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _photoPreview(photo, index, title),
          Positioned(
            left: 8,
            top: 8,
            child: CircleAvatar(
              radius: 14,
              backgroundColor: Colors.black.withValues(alpha: .55),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const Positioned(
            left: 6,
            bottom: 6,
            child: Icon(
              Icons.drag_indicator,
              color: Colors.white,
              shadows: [Shadow(color: Colors.black54, blurRadius: 5)],
              size: 24,
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton.filledTonal(
              tooltip: 'Remove photo',
              onPressed: () => _removePhoto(photo),
              icon: const Icon(Icons.close, size: 18),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: .9),
                minimumSize: const Size(36, 36),
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _photoPreview(FolderScanPhoto photo, int index, String title) =>
      Stack(
        fit: StackFit.expand,
        children: [
          if (photo.previewBytes case final bytes?)
            Image.memory(bytes, fit: BoxFit.cover)
          else
            const ColoredBox(
              color: Color(0xFFE8EAE4),
              child: Icon(Icons.image_not_supported_outlined),
            ),
          if (index == 0 && title.isNotEmpty)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: _previewTitleStyle(_titleStyle),
                ),
              ),
            ),
        ],
      );

  static String _styleLabel(ReelTitleStyle style) => switch (style) {
    ReelTitleStyle.clean => 'Clean',
    ReelTitleStyle.bold => 'Bold',
    ReelTitleStyle.elegant => 'Elegant',
  };

  static TextStyle _previewTitleStyle(ReelTitleStyle style) => switch (style) {
    ReelTitleStyle.clean => const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w600,
    ),
    ReelTitleStyle.bold => const TextStyle(
      color: Color(0xFFFFD479),
      fontWeight: FontWeight.w900,
    ),
    ReelTitleStyle.elegant => const TextStyle(
      color: Colors.white,
      fontFamily: 'serif',
      fontStyle: FontStyle.italic,
    ),
  };
}
