import 'dart:async';

import 'package:flutter/material.dart';

import 'package:pictoiq_mobile/shared/app_background.dart';
import 'package:pictoiq_mobile/core/config/app_colors.dart';
import 'package:pictoiq_mobile/core/config/app_limits.dart';
import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart';
import 'package:pictoiq_mobile/shared/app_back_button.dart';
import 'package:pictoiq_mobile/shared/scroll_with_top_button.dart';

/// Shows every best shot or best moment that could be shared, with the first
/// [maxPhotos] marked as the ones that will be sent. The person can remove
/// photos and drag them into the order they want, so the top ones are shared.
/// The photos are shown in a grid of large previews, like the Create reel
/// screen. Pops with the photos that remain (in order), or with null when they
/// go back without sharing.
class SharePreviewPage extends StatefulWidget {
  const SharePreviewPage({
    super.key,
    required this.photos,
    this.title = 'Share photos',
    this.noun = 'best shots',
    this.maxPhotos = AppLimits.shareMaxPhotos,
  });

  /// "Share best moments" or "Share best shots".
  final String title;

  /// "best moments" or "best shots", used in the warning.
  final String noun;

  final List<FolderScanPhoto> photos;

  /// Most photos sent in one share.
  final int maxPhotos;

  @override
  State<SharePreviewPage> createState() => _SharePreviewPageState();
}

class _SharePreviewPageState extends State<SharePreviewPage> {
  late final List<FolderScanPhoto> _photos = [...widget.photos];
  final _scrollController = ScrollController();
  final _scrollKey = GlobalKey();
  Timer? _autoScrollTimer;
  double _autoScrollStep = 0;

  void _remove(FolderScanPhoto photo) =>
      setState(() => _photos.removeWhere((item) => item.uri == photo.uri));

  void _move(FolderScanPhoto source, FolderScanPhoto target) {
    final from = _photos.indexWhere((item) => item.uri == source.uri);
    final to = _photos.indexWhere((item) => item.uri == target.uri);
    if (from < 0 || to < 0 || from == to) return;
    setState(() {
      _photos[from] = target;
      _photos[to] = source;
    });
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

  @override
  void dispose() {
    _stopAutoScroll();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final max = widget.maxPhotos;
    final tooMany = _photos.length > max;
    final count = _photos.length > max ? max : _photos.length;
    return AppScaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        leadingWidth: appBackButtonWidth,
        actions: const [AppHomeButton()],
        centerTitle: true,
        title: Text(widget.title),
      ),
      body: ScrollWithTopButton(
        controller: _scrollController,
        child: CustomScrollView(
          key: _scrollKey,
          controller: _scrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              sliver: SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.tintBorder),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.drag_indicator,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _photos.isEmpty
                              ? 'No photos left to share.'
                              : '$count photo${count == 1 ? '' : 's'} will be shared. Tap ✕ to remove a photo. Press and hold a photo, then drag it onto another photo to change the order.',
                          style: const TextStyle(
                            color: AppColors.body,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (tooMany)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                sliver: SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4D6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'PictoIQ allows only $max ${widget.noun} to be '
                            'shared at a time. The top $max below are used. '
                            'Remove ${widget.noun} you do not want, or drag '
                            'the ones you want to the top.',
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
              sliver: const SliverToBoxAdapter(
                child: Text(
                  'Photo preview · drag to reorder',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: DecoratedSliver(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.tintBorder),
                  borderRadius: BorderRadius.circular(20),
                ),
                sliver: SliverPadding(
                  padding: const EdgeInsets.all(10),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: .86,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final photo = _photos[index];
                      return DragTarget<FolderScanPhoto>(
                        key: ValueKey('share-photo-${photo.uri}'),
                        onAcceptWithDetails: (details) =>
                            _move(details.data, photo),
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
                                  child: _preview(photo),
                                ),
                              ),
                              childWhenDragging: Opacity(
                                opacity: .35,
                                child: _card(photo, index),
                              ),
                              child: _card(
                                photo,
                                index,
                                isDropTarget: candidates.isNotEmpty,
                              ),
                            ),
                      );
                    }, childCount: _photos.length),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _photos.isEmpty
                ? null
                : () => Navigator.of(context).pop(_photos),
            icon: const Icon(Icons.ios_share_outlined),
            label: Text(
              _photos.isEmpty
                  ? 'Share'
                  : 'Share $count photo${count == 1 ? '' : 's'}',
            ),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ),
      ),
    );
  }

  Widget _preview(FolderScanPhoto photo) {
    final bytes = photo.previewBytes;
    return bytes == null
        ? const ColoredBox(
            color: Color(0xFFE8EAE4),
            child: Icon(Icons.image_not_supported_outlined),
          )
        : Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const ColoredBox(
              color: Color(0xFFE8EAE4),
              child: Icon(Icons.broken_image_outlined),
            ),
          );
  }

  Widget _card(
    FolderScanPhoto photo,
    int index, {
    bool isDropTarget = false,
  }) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        border: Border.all(
          color: isDropTarget ? AppColors.primary : Colors.transparent,
          width: 3,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _preview(photo),
          if (index >= widget.maxPhotos)
            Container(
              color: Colors.white.withValues(alpha: .6),
              alignment: Alignment.center,
              child: const Text(
                'Not included',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
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
              tooltip: 'Do not share this photo',
              onPressed: () => _remove(photo),
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
}
