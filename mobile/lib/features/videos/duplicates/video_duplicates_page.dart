import 'package:flutter/material.dart';

import 'package:pictoiq_mobile/features/videos/duplicates/video_duplicates.dart';

const _ink = Color(0xFF282B25);
const _green = Color(0xFF54744C);
const _canvas = Color(0xFFF7F8F4);
const _line = Color(0xFFE6E8E0);

/// Review screen for identical videos. In each set the oldest video is kept
/// by default; tap another to keep that one instead. Nothing is deleted until
/// the person confirms.
class VideoDuplicatesPage extends StatefulWidget {
  const VideoDuplicatesPage({
    super.key,
    required this.result,
    required this.rangeDescription,
    required this.deleteVideos,
  });

  final VideoScanResult result;
  final String rangeDescription;

  /// Deletes the videos and returns the ids that were deleted.
  final Future<Set<String>> Function(List<String> ids) deleteVideos;

  @override
  State<VideoDuplicatesPage> createState() => _VideoDuplicatesPageState();
}

class _VideoDuplicatesPageState extends State<VideoDuplicatesPage> {
  late List<VideoDuplicateGroup> _groups = List.of(widget.result.groups);

  /// The video kept in each set, by set id (the oldest unless changed).
  final Map<String, String> _keep = {};
  bool _deleting = false;
  int _freedBytes = 0;
  int _freedVideos = 0;

  VideoItem _keeper(VideoDuplicateGroup group) {
    final id = _keep[group.id];
    for (final item in group.items) {
      if (item.id == id) return item;
    }
    return group.original;
  }

  List<VideoItem> _removals(VideoDuplicateGroup group) {
    final keeper = _keeper(group);
    return [
      for (final item in group.items)
        if (item.id != keeper.id) item,
    ];
  }

  int _bytesOf(Iterable<VideoItem> items) =>
      items.fold<int>(0, (total, item) => total + item.size);

  static String _bytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String _length(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$rest';
  }

  static String _date(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Future<void> _delete(List<VideoDuplicateGroup> groups) async {
    if (_deleting) return;
    final removals = [for (final group in groups) ..._removals(group)];
    if (removals.isEmpty) return;
    final bytes = _bytesOf(removals);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Delete ${removals.length} video${removals.length == 1 ? '' : 's'}?',
        ),
        content: Text(
          'These are exact copies. One video of each set is kept. '
          'This frees about ${_bytes(bytes)}. Android asks once more '
          'before the videos are removed.',
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
      deleted = await widget.deleteVideos([
        for (final item in removals) item.id,
      ]);
    } catch (_) {
      deleted = {};
    }
    if (!mounted) return;
    final freed = _bytesOf(removals.where((item) => deleted.contains(item.id)));
    final failed = removals.length - deleted.length;
    setState(() {
      _deleting = false;
      _freedBytes += freed;
      _freedVideos += deleted.length;
      _groups = [
        for (final group in _groups)
          ?group.without(deleted),
      ];
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
    final allRemovals = [for (final group in _groups) ..._removals(group)];
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
          'Exact duplicate videos',
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
                _groups.isEmpty
                    ? (_freedVideos == 0
                          ? 'No duplicate videos left.'
                          : 'All clear. Freed about ${_bytes(_freedBytes)} '
                                'from $_freedVideos video${_freedVideos == 1 ? '' : 's'}.')
                    : '${_groups.length} set${_groups.length == 1 ? '' : 's'} of '
                          'identical videos in "${widget.result.albumName}" '
                          '(${widget.rangeDescription}). The oldest of each set is '
                          'kept; tap another to keep that one instead. About '
                          '${_bytes(_bytesOf(allRemovals))} can be freed.'
                          '${widget.result.videosUnreadable == 0 ? '' : ' ${widget.result.videosUnreadable} could not be read.'}',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: Color(0xFF596252),
                ),
              ),
            ),
          ),
          Expanded(
            child: _groups.isEmpty
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
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    itemCount: _groups.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _card(_groups[index]),
                  ),
          ),
          if (_groups.isNotEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _deleting ? null : () => _delete(_groups),
                  icon: _deleting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                  label: Text(
                    'Delete ${allRemovals.length} cop${allRemovals.length == 1 ? 'y' : 'ies'} · about ${_bytes(_bytesOf(allRemovals))}',
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

  Widget _card(VideoDuplicateGroup group) {
    final keeper = _keeper(group);
    final removals = _removals(group);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${group.items.length} identical videos · ${_length(group.original.durationSeconds)} · ${_bytes(group.original.size)} each',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: group.items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) =>
                  _tile(group, group.items[index], keeper),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _deleting ? null : () => _delete([group]),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(
                'Delete ${removals.length} cop${removals.length == 1 ? 'y' : 'ies'} · ${_bytes(_bytesOf(removals))}',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(VideoDuplicateGroup group, VideoItem item, VideoItem keeper) {
    final kept = item.id == keeper.id;
    final bytes = item.thumbnail;
    return GestureDetector(
      onTap: _deleting ? null : () => setState(() => _keep[group.id] = item.id),
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: bytes == null
                        ? Container(
                            color: _line,
                            child: const Icon(Icons.videocam_outlined),
                          )
                        : Image.memory(
                            bytes,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: kept ? _green : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: kept ? _green : Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        kept ? 'Keep' : 'Copy',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const Center(
                    child: Icon(
                      Icons.play_circle_outline,
                      color: Colors.white70,
                      size: 30,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
            Text(
              _date(item.createdAt),
              style: const TextStyle(fontSize: 11, color: Color(0xFF77796F)),
            ),
          ],
        ),
      ),
    );
  }
}
