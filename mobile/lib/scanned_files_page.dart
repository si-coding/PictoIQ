import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'folder_duplicate_scanner.dart';

enum _Show { all, grouped, single }

/// Shows every photo a scan looked at, as thumbnails, plus the counts behind
/// the result, so a person can check the scan found what they expected.
class ScannedFilesPage extends StatefulWidget {
  const ScannedFilesPage({
    super.key,
    required this.scan,
    required this.loadPreview,
  });

  final FolderScanResult scan;

  /// Loads a thumbnail for photos that were scanned without keeping one
  /// (exact-duplicate scans keep previews only for duplicates).
  final Future<Uint8List?> Function(String uri) loadPreview;

  @override
  State<ScannedFilesPage> createState() => _ScannedFilesPageState();
}

class _ScannedFilesPageState extends State<ScannedFilesPage> {
  _Show _show = _Show.all;
  final Map<String, Future<Uint8List?>> _previews = {};

  late final Map<String, int> _groupNumber = {
    for (var i = 0; i < widget.scan.duplicateGroups.length; i++)
      for (final photo in widget.scan.duplicateGroups[i].photos)
        photo.uri: i + 1,
  };

  late final List<FolderScanPhoto> _photos = [...widget.scan.scannedPhotos]
    ..sort((a, b) => a.relativePath.compareTo(b.relativePath));

  List<FolderScanPhoto> get _visible => [
    for (final photo in _photos)
      if (switch (_show) {
        _Show.all => true,
        _Show.grouped => _groupNumber.containsKey(photo.uri),
        _Show.single => !_groupNumber.containsKey(photo.uri),
      })
        photo,
  ];

  Future<Uint8List?> _preview(FolderScanPhoto photo) {
    final ready = photo.previewBytes;
    return _previews.putIfAbsent(
      photo.uri,
      () => ready != null ? Future.value(ready) : widget.loadPreview(photo.uri),
    );
  }

  String _date(int millis) {
    if (millis <= 0) return 'unknown date';
    final d = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _enlarge(FolderScanPhoto photo) async {
    final bytes = await _preview(photo);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                photo.relativePath,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                '${_date(photo.modifiedAt)} · ${(photo.size / 1024).round()} KB'
                '${_groupNumber[photo.uri] == null ? '' : ' · in group ${_groupNumber[photo.uri]}'}',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              if (bytes == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Icon(Icons.image_not_supported_outlined)),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(dialogContext).height * .6,
                  ),
                  child: InteractiveViewer(
                    maxScale: 4,
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(FolderScanPhoto photo) {
    final group = _groupNumber[photo.uri];
    return InkWell(
      onTap: () => _enlarge(photo),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: FutureBuilder<Uint8List?>(
                    future: _preview(photo),
                    builder: (context, snapshot) {
                      final bytes = snapshot.data;
                      if (bytes != null) {
                        return Image.memory(
                          bytes,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const ColoredBox(
                            color: Color(0xFFF0F1EC),
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        );
                      }
                      return ColoredBox(
                        color: const Color(0xFFF0F1EC),
                        child: Center(
                          child: snapshot.connectionState ==
                                  ConnectionState.done
                              ? const Icon(Icons.image_not_supported_outlined)
                              : const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
                ),
                if (group != null)
                  Positioned(
                    left: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF54744C),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Group $group',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            photo.relativePath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scan = widget.scan;
    final visible = _visible;
    final groupedCount = _photos
        .where((photo) => _groupNumber.containsKey(photo.uri))
        .length;
    final lines = [
      'Folder: ${scan.folderName} · ${scan.rangeDescription}',
      'Image files found: ${scan.imageFilesFound}',
      'Scanned: ${scan.imagesScanned}',
      'Left out by the date range: ${scan.imagesOutsideDateRange}',
      'Skipped (unreadable or unsupported): ${scan.imagesSkipped}',
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Scanned files')),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            sliver: SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF3E8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in lines)
                      Text(line, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Wrap(
                spacing: 6,
                children: [
                  ChoiceChip(
                    label: Text('All (${_photos.length})'),
                    selected: _show == _Show.all,
                    onSelected: (_) => setState(() => _show = _Show.all),
                  ),
                  ChoiceChip(
                    label: Text('In groups ($groupedCount)'),
                    selected: _show == _Show.grouped,
                    onSelected: (_) => setState(() => _show = _Show.grouped),
                  ),
                  ChoiceChip(
                    label: Text('Not grouped (${_photos.length - groupedCount})'),
                    selected: _show == _Show.single,
                    onSelected: (_) => setState(() => _show = _Show.single),
                  ),
                ],
              ),
            ),
          ),
          if (visible.isEmpty)
            const SliverPadding(
              padding: EdgeInsets.all(16),
              sliver: SliverToBoxAdapter(child: Text('No photos to show.')),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverGrid.builder(
                itemCount: visible.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: .8,
                ),
                itemBuilder: (context, index) => _tile(visible[index]),
              ),
            ),
          if (scan.skippedNames.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Skipped files (never grouped or deleted)',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    for (final name in scan.skippedNames)
                      Text(name, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
