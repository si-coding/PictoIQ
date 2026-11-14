import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:pictoiq_mobile/shared/app_menu_button.dart';
import 'package:pictoiq_mobile/shared/app_background.dart';
import 'package:pictoiq_mobile/shared/app_back_button.dart';
import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart';
import 'package:pictoiq_mobile/core/config/app_colors.dart';

/// The photos of one album as a scrollable grid, so a person can look before
/// choosing it. Tap a photo to enlarge it; "Select this album" pops with the
/// album's [FolderSelection]. Back returns to the album list.
class AlbumContentsPage extends StatefulWidget {
  const AlbumContentsPage({
    super.key,
    required this.album,
    required this.loadThumbnails,
    required this.loadPhoto,
    this.pageSize = 60,
  });

  final MediaAlbum album;

  /// Small pictures for photos [start] up to [end] (newest first).
  final Future<List<Uint8List?>> Function(int start, int end) loadThumbnails;

  /// A larger picture of the photo at [index], for the enlarged view.
  final Future<Uint8List?> Function(int index) loadPhoto;

  final int pageSize;

  @override
  State<AlbumContentsPage> createState() => _AlbumContentsPageState();
}

class _AlbumContentsPageState extends State<AlbumContentsPage> {
  final List<Uint8List?> _thumbs = [];
  final ScrollController _scroll = ScrollController();
  bool _loading = false;
  bool _failed = false;

  bool get _hasMore => _thumbs.length < widget.album.count;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 800) _loadMore();
    });
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final start = _thumbs.length;
      final end = start + widget.pageSize > widget.album.count
          ? widget.album.count
          : start + widget.pageSize;
      final page = await widget.loadThumbnails(start, end);
      if (!mounted) return;
      setState(() {
        _thumbs.addAll(page);
        _loading = false;
        // An empty page would otherwise be asked for again and again.
        if (page.isEmpty) _failed = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _enlarge(int index) async {
    final future = widget.loadPhoto(index);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(dialogContext).height * .75,
                ),
                child: FutureBuilder<Uint8List?>(
                  future: future,
                  builder: (context, snapshot) {
                    final bytes = snapshot.data ?? _thumbs[index];
                    if (bytes == null) {
                      return const SizedBox(
                        height: 200,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return InteractiveViewer(
                      maxScale: 5,
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        cacheWidth: 1600,
                        gaplessPlayback: true,
                      ),
                    );
                  },
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      actions: const [AppHomeButton(), AppMenuButton()],
      title: Text(widget.album.name),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(22),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '${widget.album.count} photo${widget.album.count == 1 ? '' : 's'} · tap a photo to enlarge it',
            style: const TextStyle(fontSize: 12, color: AppColors.body),
          ),
        ),
      ),
    ),
    body: GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: _thumbs.length + (_hasMore && !_failed ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _thumbs.length) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final bytes = _thumbs[index];
        return InkWell(
          onTap: () => _enlarge(index),
          child: bytes == null
              ? const ColoredBox(
                  color: Color(0xFFE6E8E0),
                  child: Icon(Icons.photo_outlined),
                )
              : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
        );
      },
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(widget.album.selection),
          icon: const Icon(Icons.check),
          label: Text('Select this album (${widget.album.count})'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            backgroundColor: AppColors.primary,
          ),
        ),
      ),
    ),
  );
}
