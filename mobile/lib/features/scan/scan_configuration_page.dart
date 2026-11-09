import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart';
import 'package:pictoiq_mobile/features/videos/duplicates/video_duplicates.dart';

const _ink = Color(0xFF282B25);
const _green = Color(0xFF54744C);

class ScanConfigurationPage extends StatefulWidget {
  const ScanConfigurationPage({
    super.key,
    required this.title,
    required this.description,
    required this.isVideo,
    required this.initialDateRange,
    required this.initialCustomRange,
    required this.onDateRangeSelected,
    required this.initialPhotoFolder,
    required this.initialVideoAlbum,
    required this.browsePhotoFolder,
    required this.browseVideoAlbum,
    required this.loadPhotoGallery,
    required this.loadVideoGallery,
    required this.scanEnabled,
    required this.scanLabel,
    required this.onSettings,
    required this.onPrivacy,
    required this.onScan,
    required this.onCancelScan,
    required this.scanProgressRevision,
    required this.scanProgressBuilder,
  });

  final String title;
  final String description;
  final bool isVideo;
  final FolderDateRange initialDateRange;
  final DateTimeRange? initialCustomRange;
  final Future<DateTimeRange?> Function(FolderDateRange range)
  onDateRangeSelected;
  final FolderSelection? initialPhotoFolder;
  final VideoAlbum? initialVideoAlbum;
  final Future<FolderSelection?> Function() browsePhotoFolder;
  final Future<VideoAlbum?> Function() browseVideoAlbum;
  final Future<List<Uint8List?>> Function(FolderSelection folder)
  loadPhotoGallery;
  final Future<List<VideoPreview>> Function(VideoAlbum album) loadVideoGallery;
  final bool scanEnabled;
  final String scanLabel;
  final VoidCallback onSettings;
  final VoidCallback onPrivacy;
  final Future<bool> Function() onScan;
  final VoidCallback onCancelScan;
  final ValueListenable<int> scanProgressRevision;
  final Widget Function() scanProgressBuilder;

  @override
  State<ScanConfigurationPage> createState() => _ScanConfigurationPageState();
}

class _ScanConfigurationPageState extends State<ScanConfigurationPage> {
  late FolderDateRange _dateRange = widget.initialDateRange;
  late DateTimeRange? _customRange = widget.initialCustomRange;
  late FolderSelection? _photoFolder = widget.initialPhotoFolder;
  late VideoAlbum? _videoAlbum = widget.initialVideoAlbum;
  Future<List<Uint8List?>>? _photoGallery;
  Future<List<VideoPreview>>? _videoGallery;
  bool _choosingAlbum = false;
  bool _scanning = false;
  bool _cancelRequested = false;

  @override
  void initState() {
    super.initState();
    _refreshGallery();
  }

  void _refreshGallery() {
    if (widget.isVideo) {
      final album = _videoAlbum;
      _videoGallery = album == null || album.isFolder
          ? null
          : widget.loadVideoGallery(album);
      _photoGallery = null;
    } else {
      final folder = _photoFolder;
      _photoGallery = folder?.albumId == null
          ? null
          : widget.loadPhotoGallery(folder!);
      _videoGallery = null;
    }
  }

  Future<void> _selectDateRange(FolderDateRange range) async {
    final custom = await widget.onDateRangeSelected(range);
    if (!mounted || (range == FolderDateRange.custom && custom == null)) return;
    setState(() {
      _dateRange = range;
      if (range == FolderDateRange.custom) _customRange = custom;
    });
  }

  Future<void> _browse() async {
    if (_choosingAlbum) return;
    setState(() => _choosingAlbum = true);
    try {
      if (widget.isVideo) {
        final chosen = await widget.browseVideoAlbum();
        if (chosen != null && mounted) {
          setState(() {
            _videoAlbum = chosen;
            _refreshGallery();
          });
        }
      } else {
        final chosen = await widget.browsePhotoFolder();
        if (chosen != null && mounted) {
          setState(() {
            _photoFolder = chosen;
            _refreshGallery();
          });
        }
      }
    } finally {
      if (mounted) setState(() => _choosingAlbum = false);
    }
  }

  String get _selectionName => widget.isVideo
      ? _videoAlbum?.name ?? 'Choose a video album or folder'
      : _photoFolder?.name ?? 'Choose an album or folder';

  bool get _hasSelection =>
      widget.isVideo ? _videoAlbum != null : _photoFolder != null;

  Future<void> _startScan() async {
    if (_scanning || !widget.scanEnabled || !_hasSelection) return;
    setState(() {
      _scanning = true;
      _cancelRequested = false;
    });
    var completed = false;
    try {
      completed = await widget.onScan();
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
        if (completed) Navigator.of(context).pop(true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_scanning,
    child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !_scanning,
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: _scanning ? null : widget.onSettings,
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: 'Privacy',
            onPressed: _scanning ? null : widget.onPrivacy,
            icon: const Icon(Icons.shield_outlined),
          ),
        ],
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset(
                'assets/brand/pictoiq-icon.png',
                width: 36,
                height: 36,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'PictoIQ',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: IgnorePointer(
        ignoring: _scanning,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              sliver: SliverToBoxAdapter(
                child: Text(
                  widget.description,
                  style: const TextStyle(color: Color(0xFF687064), height: 1.4),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(child: _dateSection()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverToBoxAdapter(child: _albumSection()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              sliver: SliverToBoxAdapter(child: _gallery()),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(14, 4, 14, 10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: _scanning
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F3E8),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: ValueListenableBuilder<int>(
                          valueListenable: widget.scanProgressRevision,
                          builder: (context, _, _) =>
                              widget.scanProgressBuilder(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: _cancelRequested
                          ? null
                          : () {
                              setState(() => _cancelRequested = true);
                              widget.onCancelScan();
                            },
                      icon: const Icon(Icons.close, size: 18),
                      label: Text(
                        _cancelRequested ? 'Stopping…' : 'Cancel scan',
                      ),
                    ),
                  ],
                )
              : FilledButton.icon(
                  onPressed: widget.scanEnabled && _hasSelection
                      ? _startScan
                      : null,
                  icon: Icon(
                    widget.isVideo ? Icons.videocam_outlined : Icons.search,
                  ),
                  label: Text(widget.scanLabel),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
        ),
      ),
    ),
  );

  Widget _dateSection() {
    const labels = {
      FolderDateRange.today: 'Today',
      FolderDateRange.week: '7 days',
      FolderDateRange.month: '30 days',
      FolderDateRange.currentFolder: 'All',
      FolderDateRange.custom: 'Custom',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '1. Choose a date range',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final range in FolderDateRange.values)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: range == FolderDateRange.custom ? 0 : 6,
                  ),
                  child: _dateChip(range, labels[range]!),
                ),
              ),
          ],
        ),
        if (_dateRange == FolderDateRange.custom && _customRange != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_month_outlined,
                  size: 15,
                  color: Color(0xFF687064),
                ),
                const SizedBox(width: 5),
                Text(
                  '${_formatDate(_customRange!.start)} – ${_formatDate(_customRange!.end)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF687064),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _dateChip(FolderDateRange range, String label) {
    final selected = range == _dateRange;
    return Material(
      color: selected ? _green : const Color(0xFFF0F1EC),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _selectDateRange(range),
        child: SizedBox(
          height: 38,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: range == FolderDateRange.custom
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_month_outlined,
                          size: 15,
                          color: selected ? Colors.white : _ink,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          label,
                          style: TextStyle(
                            color: selected ? Colors.white : _ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      label,
                      style: TextStyle(
                        color: selected ? Colors.white : _ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _albumSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '2. Browse your album or folder',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _choosingAlbum ? null : _browse,
        icon: _choosingAlbum
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.photo_library_outlined),
        label: Text(
          _choosingAlbum ? 'Opening albums…' : _selectionName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          alignment: Alignment.centerLeft,
          foregroundColor: _ink,
        ),
      ),
    ],
  );

  Widget _gallery() {
    if (!_hasSelection) {
      return _galleryPlaceholder(
        icon: Icons.collections_outlined,
        message: 'Your album preview will appear here.',
      );
    }
    if (widget.isVideo) {
      if (_videoAlbum?.isFolder ?? true) {
        return _galleryPlaceholder(
          icon: Icons.folder_open_outlined,
          message: 'Folder selected. Videos will be checked when you scan.',
        );
      }
      return FutureBuilder<List<VideoPreview>>(
        future: _videoGallery,
        builder: (context, snapshot) => _galleryGrid(
          thumbnails: [
            for (final video in snapshot.data ?? const <VideoPreview>[])
              video.thumbnail,
          ],
          loading: snapshot.connectionState == ConnectionState.waiting,
          failed: snapshot.hasError,
          emptyMessage: 'No video previews are available for this album.',
        ),
      );
    }

    if (_photoFolder?.albumId == null) {
      return _galleryPlaceholder(
        icon: Icons.folder_open_outlined,
        message: 'Folder selected. Photos will be checked when you scan.',
      );
    }
    return FutureBuilder<List<Uint8List?>>(
      future: _photoGallery,
      builder: (context, snapshot) => _galleryGrid(
        thumbnails: snapshot.data ?? const <Uint8List?>[],
        loading: snapshot.connectionState == ConnectionState.waiting,
        failed: snapshot.hasError,
        emptyMessage: 'No photo previews are available for this album.',
      ),
    );
  }

  Widget _galleryGrid({
    required List<Uint8List?> thumbnails,
    required bool loading,
    required bool failed,
    required String emptyMessage,
  }) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (failed || thumbnails.isEmpty) {
      return _galleryPlaceholder(
        icon: Icons.photo_outlined,
        message: failed ? 'Album preview could not be loaded.' : emptyMessage,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '3. Album preview · ${thumbnails.length} recent item${thumbnails.length == 1 ? '' : 's'}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: thumbnails.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemBuilder: (context, index) {
            final image = thumbnails[index];
            return ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: image == null
                  ? const ColoredBox(
                      color: Color(0xFFE6E8E0),
                      child: Icon(Icons.image_not_supported_outlined),
                    )
                  : Image.memory(image, fit: BoxFit.cover),
            );
          },
        ),
      ],
    );
  }

  Widget _galleryPlaceholder({
    required IconData icon,
    required String message,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    decoration: BoxDecoration(
      color: const Color(0xFFE8F3E8),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        Icon(icon, size: 30, color: _green),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF687064)),
        ),
      ],
    ),
  );

  String _formatDate(DateTime date) => '${date.day}/${date.month}/${date.year}';
}
