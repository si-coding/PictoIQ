import 'package:flutter/material.dart';

import 'package:pictoiq_mobile/shared/app_menu_button.dart';
import 'package:pictoiq_mobile/shared/app_background.dart';
import 'package:pictoiq_mobile/core/config/app_colors.dart';
import 'package:pictoiq_mobile/core/config/app_limits.dart';
import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart';
import 'package:pictoiq_mobile/shared/app_back_button.dart';

/// Shows every best shot or best moment that could be shared, with the first
/// [maxPhotos] marked as the ones that will be sent. The person can remove
/// photos and drag them into the order they want, so the top ones are shared.
/// Pops with the photos that remain (in order), or with null when they go back
/// without sharing.
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

  void _remove(FolderScanPhoto photo) => setState(() => _photos.remove(photo));

  void _reorder(int oldIndex, int newIndex) {
    // onReorderItem already adjusts newIndex for the removed item.
    setState(() => _photos.insert(newIndex, _photos.removeAt(oldIndex)));
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
        actions: const [AppMenuButton()],
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _photos.isEmpty
                    ? 'No photos left to share.'
                    : '$count photo${count == 1 ? '' : 's'} will be shared. Tap ✕ to remove a photo, and drag ⠿ to change the order.',
                style: const TextStyle(fontSize: 13, color: AppColors.body),
              ),
            ),
          ),
          if (tooMany)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                      'PictoIQ allows only $max ${widget.noun} to be shared or '
                      'made into a reel at a time. The top $max below are used. '
                      'Remove ${widget.noun} you do not want, or drag the ones '
                      'you want to the top.',
                      style: const TextStyle(fontSize: 12.5, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppColors.tintBorder),
                borderRadius: BorderRadius.circular(20),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.all(8),
                  itemCount: _photos.length,
                  onReorderItem: _reorder,
                  itemBuilder: (context, index) {
                    final photo = _photos[index];
                    final preview = photo.previewBytes;
                    final included = index < max;
                    return Opacity(
                      key: ValueKey(photo.uri),
                      opacity: included ? 1 : .45,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                width: 72,
                                height: 72,
                                child: preview == null
                                    ? const ColoredBox(
                                        color: AppColors.tint,
                                        child: Icon(
                                          Icons.image_not_supported_outlined,
                                        ),
                                      )
                                    : Image.memory(
                                        preview,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) =>
                                            const ColoredBox(
                                              color: AppColors.tint,
                                              child: Icon(
                                                Icons.broken_image_outlined,
                                              ),
                                            ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                  Text(
                                    included ? 'Will be shared' : 'Not included',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.hint,
                                      fontWeight: included
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Do not share this photo',
                              onPressed: () => _remove(photo),
                              icon: const Icon(Icons.close),
                            ),
                            ReorderableDragStartListener(
                              index: index,
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(Icons.drag_indicator),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
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
}
