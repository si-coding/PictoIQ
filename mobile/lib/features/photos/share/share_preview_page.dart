import 'package:flutter/material.dart';

import 'package:pictoiq_mobile/shared/app_menu_button.dart';
import 'package:pictoiq_mobile/shared/app_background.dart';
import 'package:pictoiq_mobile/core/config/app_colors.dart';
import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart';
import 'package:pictoiq_mobile/shared/app_back_button.dart';

/// Shows every photo that is about to be shared, so the person can take out
/// any they do not want to send. Pops with the photos that remain, or with
/// null when they go back without sharing.
class SharePreviewPage extends StatefulWidget {
  const SharePreviewPage({
    super.key,
    required this.photos,
    this.title = 'Share photos',
    this.maxPhotos = 30,
  });

  /// "Share best moments" or "Share best shots".
  final String title;

  final List<FolderScanPhoto> photos;

  /// Most apps accept only a few dozen photos in one share.
  final int maxPhotos;

  @override
  State<SharePreviewPage> createState() => _SharePreviewPageState();
}

class _SharePreviewPageState extends State<SharePreviewPage> {
  late final List<FolderScanPhoto> _photos = [...widget.photos];

  void _remove(FolderScanPhoto photo) => setState(() => _photos.remove(photo));

  @override
  Widget build(BuildContext context) {
    final tooMany = _photos.length > widget.maxPhotos;
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
                    : '${_photos.length} photo${_photos.length == 1 ? '' : 's'} will be shared. Tap the ✕ on any photo you do not want to send.',
                style: const TextStyle(fontSize: 13, color: AppColors.body),
              ),
            ),
          ),
          if (tooMany)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Sharing sends the first ${widget.maxPhotos} photos at a time. Remove some to send them all.',
                style: const TextStyle(fontSize: 12, color: AppColors.hint),
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
              child: GridView.builder(
                padding: const EdgeInsets.all(10),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: _photos.length,
                itemBuilder: (context, index) {
                  final photo = _photos[index];
                  final preview = photo.previewBytes;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: preview == null
                            ? const ColoredBox(
                                color: AppColors.tint,
                                child: Icon(Icons.image_not_supported_outlined),
                              )
                            : Image.memory(
                                preview,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const ColoredBox(
                                  color: AppColors.tint,
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Tooltip(
                          message: 'Do not share this photo',
                          child: InkResponse(
                            onTap: () => _remove(photo),
                            radius: 22,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Color(0x33000000),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 18,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
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
                  : 'Share ${_photos.length > widget.maxPhotos ? widget.maxPhotos : _photos.length} photo${(_photos.length > widget.maxPhotos ? widget.maxPhotos : _photos.length) == 1 ? '' : 's'}',
            ),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ),
      ),
    );
  }
}
