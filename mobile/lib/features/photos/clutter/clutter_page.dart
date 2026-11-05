import 'package:flutter/material.dart';

import 'package:pictoiq_mobile/features/photos/clutter/clutter_classifier.dart';

const _ink = Color(0xFF282B25);
const _green = Color(0xFF54744C);
const _canvas = Color(0xFFF7F8F4);
const _line = Color(0xFFE6E8E0);

/// Review screen for photos that look like clutter (screenshots, documents,
/// blank, blurry and tiny images). Nothing is chosen at the start and nothing
/// is deleted until the person confirms.
class ClutterPage extends StatefulWidget {
  const ClutterPage({
    super.key,
    required this.items,
    required this.folderName,
    required this.rangeDescription,
    required this.deleteFiles,
    this.imagesSkipped = 0,
  });

  final List<ClutterItem> items;
  final String folderName;
  final String rangeDescription;

  /// Deletes the files and returns the ones that were deleted.
  final Future<Set<String>> Function(List<String> uris) deleteFiles;

  /// Photos that could not be read, so were not checked.
  final int imagesSkipped;

  @override
  State<ClutterPage> createState() => _ClutterPageState();
}

class _ClutterPageState extends State<ClutterPage> {
  late List<ClutterItem> _items = List.of(widget.items);
  final Set<String> _selected = {};
  ClutterKind? _filter;
  bool _deleting = false;
  int _freedBytes = 0;
  int _freedPhotos = 0;

  List<ClutterItem> get _visible => [
    for (final item in _items)
      if (_filter == null || item.kind == _filter) item,
  ];

  int _count(ClutterKind? kind) => kind == null
      ? _items.length
      : _items.where((item) => item.kind == kind).length;

  List<ClutterItem> get _chosen => [
    for (final item in _items)
      if (_selected.contains(item.photo.uri)) item,
  ];

  int get _chosenBytes =>
      _chosen.fold<int>(0, (total, item) => total + item.photo.size);

  static String _bytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _toggle(ClutterItem item) {
    if (_deleting) return;
    setState(() {
      if (!_selected.remove(item.photo.uri)) _selected.add(item.photo.uri);
    });
  }

  void _selectVisible() => setState(() {
    for (final item in _visible) {
      _selected.add(item.photo.uri);
    }
  });

  void _clearSelection() => setState(_selected.clear);

  Future<void> _preview(ClutterItem item) {
    final bytes = item.photo.previewBytes;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (bytes != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.photo.relativePath,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.kind.title} · ${_bytes(item.photo.size)}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF596252),
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final chosen = _chosen;
    if (chosen.isEmpty || _deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Delete ${chosen.length} photo${chosen.length == 1 ? '' : 's'}?',
        ),
        content: Text(
          'This frees about ${_bytes(_chosenBytes)} from "${widget.folderName}". '
          'Android asks once more before the photos are removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    Set<String> deleted;
    try {
      deleted = await widget.deleteFiles([
        for (final item in chosen) item.photo.uri,
      ]);
    } catch (_) {
      deleted = {};
    }
    if (!mounted) return;
    final freed = chosen
        .where((item) => deleted.contains(item.photo.uri))
        .fold<int>(0, (total, item) => total + item.photo.size);
    final failed = chosen.length - deleted.length;
    setState(() {
      _deleting = false;
      _freedBytes += freed;
      _freedPhotos += deleted.length;
      _items = [
        for (final item in _items)
          if (!deleted.contains(item.photo.uri)) item,
      ];
      _selected.removeAll(deleted);
      if (_filter != null && _count(_filter) == 0) _filter = null;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text(
            failed == 0
                ? 'Freed about ${_bytes(freed)}.'
                : 'Freed about ${_bytes(freed)}. $failed could not be deleted.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        backgroundColor: _canvas,
        foregroundColor: _ink,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: _deleting ? null : () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Clutter',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _items.isEmpty
                    ? (_freedPhotos == 0
                          ? 'No clutter left.'
                          : 'All clear. Freed about ${_bytes(_freedBytes)} '
                                'from $_freedPhotos photo${_freedPhotos == 1 ? '' : 's'}.')
                    : '${_items.length} photo${_items.length == 1 ? '' : 's'} '
                          'in "${widget.folderName}" look like clutter '
                          '(${widget.rangeDescription}). Tick the ones to remove. '
                          'Nothing is deleted until you confirm.'
                          '${widget.imagesSkipped == 0 ? '' : ' ${widget.imagesSkipped} could not be read and were not checked.'}',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: Color(0xFF596252),
                ),
              ),
            ),
          ),
          if (_items.isNotEmpty) ...[
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _chip('All', _count(null), null),
                  for (final kind in ClutterKind.values)
                    if (_count(kind) > 0) _chip(kind.title, _count(kind), kind),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _filter?.description ??
                          'Each photo is listed once, under its first reason.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF77796F),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _deleting ? null : _selectVisible,
                    child: Text(_filter == null ? 'Select all' : 'Select these'),
                  ),
                  if (_selected.isNotEmpty)
                    TextButton(
                      onPressed: _deleting ? null : _clearSelection,
                      child: const Text('Clear'),
                    ),
                ],
              ),
            ),
          ],
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          size: 48,
                          color: _green,
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Back to PictoIQ'),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                        ),
                    itemCount: visible.length,
                    itemBuilder: (context, index) => _tile(visible[index]),
                  ),
          ),
          if (_selected.isNotEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _deleting ? null : _delete,
                  icon: _deleting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                  label: Text(
                    'Delete ${_selected.length} · about ${_bytes(_chosenBytes)}',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: const Color(0xFF9A5A50),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(String label, int count, ClutterKind? kind) {
    final selected = _filter == kind;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text('$label · $count'),
        selected: selected,
        showCheckmark: false,
        selectedColor: _green,
        labelStyle: TextStyle(
          fontSize: 13,
          color: selected ? Colors.white : _ink,
        ),
        onSelected: (_) => setState(() => _filter = kind),
      ),
    );
  }

  Widget _tile(ClutterItem item) {
    final picked = _selected.contains(item.photo.uri);
    final bytes = item.photo.previewBytes;
    return GestureDetector(
      onTap: () => _toggle(item),
      onLongPress: () => _preview(item),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: bytes == null
                ? Container(
                    color: _line,
                    child: const Icon(Icons.image_not_supported_outlined),
                  )
                : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
          ),
          if (picked)
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _green, width: 3),
                color: const Color(0x3354744C),
              ),
            ),
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: picked ? _green : Colors.white70,
                border: Border.all(color: picked ? _green : Colors.black26),
              ),
              child: picked
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ),
          Positioned(
            left: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _bytes(item.photo.size),
                style: const TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
