import 'package:flutter/material.dart';

import 'package:pictoiq_mobile/features/videos/duplicates/video_duplicates.dart';
import 'package:pictoiq_mobile/features/videos/library/video_player_page.dart';

/// The videos of one album as a scrollable grid, so a person can look before
/// choosing it. Tap a video to play it; "Select this album" pops with the
/// [VideoAlbum]. Back returns to the album list.
class VideoAlbumContentsPage extends StatefulWidget {
  const VideoAlbumContentsPage({
    super.key,
    required this.album,
    required this.loadVideos,
    this.loadUrl,
    this.pageSize = 60,
  });

  final VideoAlbum album;

  /// Pictures and lengths for videos [start] up to [end] (newest first).
  final Future<List<VideoPreview>> Function(int start, int end) loadVideos;

  /// Where the video at an index can be played from. When null, tapping a
  /// video does nothing.
  final Future<String?> Function(int index)? loadUrl;

  final int pageSize;

  @override
  State<VideoAlbumContentsPage> createState() => _VideoAlbumContentsPageState();
}

class _VideoAlbumContentsPageState extends State<VideoAlbumContentsPage> {
  final List<VideoPreview> _items = [];
  final ScrollController _scroll = ScrollController();
  bool _loading = false;
  bool _failed = false;

  bool get _hasMore => _items.length < widget.album.count;

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
      final start = _items.length;
      final end = start + widget.pageSize > widget.album.count
          ? widget.album.count
          : start + widget.pageSize;
      final page = await widget.loadVideos(start, end);
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
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

  void _play(int index) {
    final loadUrl = widget.loadUrl;
    if (loadUrl == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlayerPage(
          loadUrl: () => loadUrl(index),
          poster: _items[index].thumbnail,
        ),
      ),
    );
  }

  static String _length(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$rest';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.album.name),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(22),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '${widget.album.count} video${widget.album.count == 1 ? '' : 's'} · tap a video to play it',
            style: const TextStyle(fontSize: 12, color: Color(0xFF77796F)),
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
      itemCount: _items.length + (_hasMore && !_failed ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final item = _items[index];
        final bytes = item.thumbnail;
        return InkWell(
          onTap: () => _play(index),
          child: Stack(
            fit: StackFit.expand,
            children: [
              bytes == null
                  ? const ColoredBox(
                      color: Color(0xFFE6E8E0),
                      child: Icon(Icons.videocam_outlined),
                    )
                  : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
              const Center(
                child: Icon(
                  Icons.play_circle_outline,
                  color: Colors.white70,
                  size: 30,
                ),
              ),
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _length(item.durationSeconds),
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(widget.album),
          icon: const Icon(Icons.check),
          label: Text('Select this album (${widget.album.count})'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            backgroundColor: const Color(0xFF54744C),
          ),
        ),
      ),
    ),
  );
}
