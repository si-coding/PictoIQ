import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:pictoiq_mobile/features/photos/library/album_contents_page.dart';
import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart';

/// What the person chose on [AlbumPickerPage] besides an album.
enum AlbumPickerChoice {
  /// "Other folder…": use Android's folder picker instead.
  otherFolder,
}

/// A grid of the phone's photo albums (Camera, Screenshots, WhatsApp...) with
/// a cover picture and a photo count, like the gallery pickers in chat apps.
/// Pops with a [FolderSelection] for the chosen album or with
/// [AlbumPickerChoice.otherFolder].
///
/// The data comes in through callbacks so the page does not depend on the
/// phone's media library and can be tested.
class AlbumPickerPage extends StatefulWidget {
  const AlbumPickerPage({
    super.key,
    required this.requestAccess,
    required this.loadAlbums,
    required this.loadCover,
    required this.loadThumbnails,
    required this.loadPhoto,
    required this.openSettings,
  });

  /// Asks for photo access; true when granted.
  final Future<bool> Function() requestAccess;
  final Future<List<MediaAlbum>> Function() loadAlbums;
  final Future<Uint8List?> Function(String albumId) loadCover;

  /// Pictures for the album contents screen (see [AlbumContentsPage]).
  final Future<List<Uint8List?>> Function(String albumId, int start, int end)
  loadThumbnails;
  final Future<Uint8List?> Function(String albumId, int index) loadPhoto;

  /// Opens the app's system settings so access can be granted there.
  final Future<void> Function() openSettings;

  @override
  State<AlbumPickerPage> createState() => _AlbumPickerPageState();
}

enum _Status { loading, denied, ready, failed }

class _AlbumPickerPageState extends State<AlbumPickerPage> {
  _Status _status = _Status.loading;
  List<MediaAlbum> _albums = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _status = _Status.loading);
    try {
      if (!await widget.requestAccess()) {
        if (mounted) setState(() => _status = _Status.denied);
        return;
      }
      final albums = await widget.loadAlbums();
      if (!mounted) return;
      setState(() {
        _albums = albums;
        _status = _Status.ready;
      });
    } catch (_) {
      if (mounted) setState(() => _status = _Status.failed);
    }
  }

  /// Shows what is in [album]; the person picks it from there.
  Future<void> _open(MediaAlbum album) async {
    final chosen = await Navigator.of(context).push<FolderSelection>(
      MaterialPageRoute<FolderSelection>(
        builder: (_) => AlbumContentsPage(
          album: album,
          loadThumbnails: (start, end) =>
              widget.loadThumbnails(album.id, start, end),
          loadPhoto: (index) => widget.loadPhoto(album.id, index),
        ),
      ),
    );
    if (chosen != null && mounted) Navigator.of(context).pop(chosen);
  }

  void _otherFolder() => Navigator.of(context).pop(AlbumPickerChoice.otherFolder);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Choose an album'),
      actions: [
        TextButton(onPressed: _otherFolder, child: const Text('Other folder…')),
      ],
    ),
    body: switch (_status) {
      _Status.loading => const Center(child: CircularProgressIndicator()),
      _Status.denied => _message(
        icon: Icons.lock_outline,
        text:
            'PictoIQ needs permission to see your photos so it can list your albums. Photos are analysed on this phone and are not uploaded.',
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
        text: 'Your albums could not be loaded right now.',
        actions: [
          FilledButton(onPressed: _load, child: const Text('Try again')),
          TextButton(
            onPressed: _otherFolder,
            child: const Text('Choose a folder instead'),
          ),
        ],
      ),
      _Status.ready when _albums.isEmpty => _message(
        icon: Icons.photo_library_outlined,
        text: 'No photos were found on this phone.',
        actions: [
          TextButton(
            onPressed: _otherFolder,
            child: const Text('Choose a folder instead'),
          ),
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
              const Text(
                'Missing photos? Allow access to all photos in Android settings.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF77796F)),
              ),
              TextButton(
                onPressed: widget.openSettings,
                child: const Text('Open settings'),
              ),
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

  final MediaAlbum album;
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
                      child: Icon(Icons.photo_outlined),
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
                  '${widget.album.count} photo${widget.album.count == 1 ? '' : 's'}',
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
