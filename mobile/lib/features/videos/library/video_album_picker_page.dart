import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:pictoiq_mobile/features/videos/duplicates/video_duplicates.dart';
import 'package:pictoiq_mobile/features/videos/library/video_album_contents_page.dart';

/// What the person chose on [VideoAlbumPickerPage] besides an album.
enum VideoPickerChoice {
  /// "Other folder…": use Android's folder picker instead.
  otherFolder,
}

enum _Status { loading, denied, ready, failed }

/// A grid of the phone's video albums (Camera, Downloads, WhatsApp...) with a
/// cover picture and a video count. Pops with the chosen [VideoAlbum] or with
/// [VideoPickerChoice.otherFolder].
///
/// The data comes in through callbacks so the page does not depend on the
/// phone's media library and can be tested.
class VideoAlbumPickerPage extends StatefulWidget {
  const VideoAlbumPickerPage({
    super.key,
    required this.requestAccess,
    required this.loadAlbums,
    required this.loadCover,
    required this.openSettings,
    this.manageLimited,
    this.accessDetail,
    this.loadVideos,
    this.loadVideoUrl,
  });

  /// Pictures and lengths for the album contents screen. When null, choosing
  /// an album selects it straight away.
  final Future<List<VideoPreview>> Function(String albumId, int start, int end)?
  loadVideos;

  /// Where a video can be played from, for the contents screen.
  final Future<String?> Function(String albumId, int index)? loadVideoUrl;

  /// Asks for video access.
  final Future<VideoAccess> Function() requestAccess;
  final Future<List<VideoAlbum>> Function() loadAlbums;
  final Future<Uint8List?> Function(String albumId) loadCover;

  /// Opens the app's system settings so access can be granted there.
  final Future<void> Function() openSettings;

  /// Lets the person share more videos when access is partial. Optional.
  final Future<void> Function()? manageLimited;

  /// A short technical line about the access Android gave, shown in small
  /// type on the empty and partial-access screens. Optional.
  final String Function()? accessDetail;

  @override
  State<VideoAlbumPickerPage> createState() => _VideoAlbumPickerPageState();
}

class _VideoAlbumPickerPageState extends State<VideoAlbumPickerPage> {
  _Status _status = _Status.loading;
  VideoAccess _access = VideoAccess.granted;
  List<VideoAlbum> _albums = const [];

  /// What went wrong, shown under the failure message to help fix it.
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _status = _Status.loading);
    try {
      final access = await widget.requestAccess();
      if (access == VideoAccess.denied) {
        if (mounted) {
          setState(() {
            _access = access;
            _status = _Status.denied;
          });
        }
        return;
      }
      final albums = await widget.loadAlbums();
      if (!mounted) return;
      setState(() {
        _access = access;
        _albums = albums;
        _status = _Status.ready;
      });
    } catch (error, stack) {
      debugPrint('Video albums failed to load: $error\n$stack');
      if (mounted) {
        setState(() {
          _error = '${error.runtimeType}: $error';
          _status = _Status.failed;
        });
      }
    }
  }

  Future<void> _manageLimited() async {
    await widget.manageLimited?.call();
    if (mounted) await _load();
  }

  /// The small technical line, or nothing.
  Widget _detail() {
    final text = widget.accessDetail?.call() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, color: Color(0xFF9A9C92)),
      ),
    );
  }

  /// Shows what is in [album]; the person picks it from there.
  Future<void> _open(VideoAlbum album) async {
    final loadVideos = widget.loadVideos;
    if (loadVideos == null) {
      Navigator.of(context).pop(album);
      return;
    }
    final loadUrl = widget.loadVideoUrl;
    final chosen = await Navigator.of(context).push<VideoAlbum>(
      MaterialPageRoute<VideoAlbum>(
        builder: (_) => VideoAlbumContentsPage(
          album: album,
          loadVideos: (start, end) => loadVideos(album.id, start, end),
          loadUrl: loadUrl == null ? null : (index) => loadUrl(album.id, index),
        ),
      ),
    );
    if (chosen != null && mounted) Navigator.of(context).pop(chosen);
  }

  void _otherFolder() =>
      Navigator.of(context).pop(VideoPickerChoice.otherFolder);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Choose a video album'),
      actions: [
        TextButton(onPressed: _otherFolder, child: const Text('Other folder…')),
      ],
    ),
    body: switch (_status) {
      _Status.loading => const Center(child: CircularProgressIndicator()),
      _Status.denied => _message(
        icon: Icons.lock_outline,
        text:
            'PictoIQ needs permission to see your videos so it can list your albums. Videos are checked on this phone and are not uploaded.',
        actions: [
          FilledButton(onPressed: _load, child: const Text('Allow access')),
          TextButton(
            onPressed: widget.openSettings,
            child: const Text('Open settings'),
          ),
          TextButton(
            onPressed: _otherFolder,
            child: const Text('Choose a folder instead'),
          ),
        ],
      ),
      _Status.failed => _message(
        icon: Icons.error_outline,
        text:
            'Your video albums could not be loaded right now.${_error == null ? '' : '\n\n$_error'}',
        actions: [
          FilledButton(onPressed: _load, child: const Text('Try again')),
          TextButton(
            onPressed: _otherFolder,
            child: const Text('Choose a folder instead'),
          ),
        ],
      ),
      _Status.ready when _albums.isEmpty => _message(
        icon: Icons.video_library_outlined,
        text: _access == VideoAccess.limited
            ? 'PictoIQ can only see the videos you chose to share, and none were shared. Allow access to all photos and videos in Android settings, or choose a folder.'
            : 'No videos were found in your media library. If you expected some, check that PictoIQ may see all photos and videos in Android settings, or choose a folder.',
        actions: [
          if (_access == VideoAccess.limited && widget.manageLimited != null)
            FilledButton(
              onPressed: _manageLimited,
              child: const Text('Choose videos to share'),
            ),
          if (_access == VideoAccess.limited && widget.manageLimited != null)
            TextButton(
              onPressed: widget.openSettings,
              child: const Text('Open settings'),
            )
          else
            FilledButton(
              onPressed: widget.openSettings,
              child: const Text('Open settings'),
            ),
          TextButton(onPressed: _load, child: const Text('Check again')),
          TextButton(
            onPressed: _otherFolder,
            child: const Text('Choose a folder instead'),
          ),
          _detail(),
        ],
      ),
      _Status.ready => _grid(),
    },
  );

  Widget _message({
    required IconData icon,
    required String text,
    required List<Widget> actions,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: const Color(0xFF54744C)),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ...actions,
        ],
      ),
    ),
  );

  Widget _grid() => CustomScrollView(
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => _AlbumCard(
              album: _albums[index],
              loadCover: widget.loadCover,
              onTap: () => _open(_albums[index]),
            ),
            childCount: _albums.length,
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                _access == VideoAccess.limited
                    ? 'PictoIQ can only see the videos you chose to share. Allow access to all photos and videos in Android settings to see the rest.'
                    : 'Missing videos? Allow access to all photos and videos in Android settings, or choose a folder.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Color(0xFF77796F)),
              ),
              TextButton(
                onPressed: widget.openSettings,
                child: const Text('Open settings'),
              ),
              _detail(),
            ],
          ),
        ),
      ),
    ],
  );
}

class _AlbumCard extends StatefulWidget {
  const _AlbumCard({
    required this.album,
    required this.loadCover,
    required this.onTap,
  });

  final VideoAlbum album;
  final Future<Uint8List?> Function(String albumId) loadCover;
  final VoidCallback onTap;

  @override
  State<_AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<_AlbumCard> {
  late final Future<Uint8List?> _cover = widget.loadCover(widget.album.id);

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: widget.onTap,
    borderRadius: BorderRadius.circular(12),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List?>(
            future: _cover,
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              return bytes == null
                  ? const ColoredBox(
                      color: Color(0xFFE6E8E0),
                      child: Icon(Icons.videocam_outlined),
                    )
                  : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
            },
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0xB3000000)],
                stops: [0.55, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.album.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${widget.album.count} video${widget.album.count == 1 ? '' : 's'}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
