import 'dart:io' show File;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:photo_manager/photo_manager.dart'
    show
        AssetEntity,
        AssetPathEntity,
        FilterOptionGroup,
        OrderOption,
        OrderOptionType,
        PermissionState,
        PhotoManager,
        RequestType,
        ThumbnailSize;

import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart'
    show FolderDateRange, ScanCancelled;

/// A video album from the phone's media library.
class VideoAlbum {
  const VideoAlbum({required this.id, required this.name, required this.count});

  final String id;
  final String name;
  final int count;
}

/// One video found in an album.
class VideoItem {
  const VideoItem({
    required this.id,
    required this.title,
    required this.durationSeconds,
    required this.width,
    required this.height,
    required this.createdAt,
    this.size = 0,
    this.sha256,
    this.thumbnail,
  });

  /// The media-library id (used for deleting).
  final String id;
  final String title;
  final int durationSeconds;
  final int width;
  final int height;
  final DateTime createdAt;

  /// File size in bytes, known once the video has been read.
  final int size;

  /// Hash of the whole file, known once the video has been read.
  final String? sha256;
  final Uint8List? thumbnail;

  VideoItem withContent({required int size, required String sha256}) =>
      VideoItem(
        id: id,
        title: title,
        durationSeconds: durationSeconds,
        width: width,
        height: height,
        createdAt: createdAt,
        size: size,
        sha256: sha256,
        thumbnail: thumbnail,
      );

  VideoItem withThumbnail(Uint8List? bytes) => VideoItem(
    id: id,
    title: title,
    durationSeconds: durationSeconds,
    width: width,
    height: height,
    createdAt: createdAt,
    size: size,
    sha256: sha256,
    thumbnail: bytes,
  );
}

/// Videos with identical content (same bytes, so the same hash and size).
class VideoDuplicateGroup {
  VideoDuplicateGroup({required this.id, required List<VideoItem> items})
    : items = List.unmodifiable(_oldestFirst(items));

  final String id;

  /// Oldest first: the first one is the suggested original.
  final List<VideoItem> items;

  VideoItem get original => items.first;
  List<VideoItem> get copies => items.skip(1).toList();

  /// Space freed by deleting every video except [keep].
  int bytesFreedKeeping(VideoItem keep) => items
      .where((item) => item.id != keep.id)
      .fold<int>(0, (total, item) => total + item.size);

  /// This group without the videos in [removed]; null when fewer than two
  /// remain, so it is no longer a duplicate set.
  VideoDuplicateGroup? without(Set<String> removed) {
    final left = [
      for (final item in items)
        if (!removed.contains(item.id)) item,
    ];
    if (left.length < 2) return null;
    if (left.length == items.length) return this;
    return VideoDuplicateGroup(id: id, items: left);
  }

  static List<VideoItem> _oldestFirst(List<VideoItem> items) {
    final sorted = [...items];
    sorted.sort((a, b) {
      final byDate = a.createdAt.compareTo(b.createdAt);
      return byDate != 0 ? byDate : a.title.compareTo(b.title);
    });
    return sorted;
  }
}

class VideoScanResult {
  const VideoScanResult({
    required this.albumName,
    required this.videosFound,
    required this.videosRead,
    required this.groups,
    this.videosUnreadable = 0,
  });

  final String albumName;

  /// Videos in the album that fall in the chosen dates.
  final int videosFound;

  /// Videos that had to be read because another video looked the same.
  final int videosRead;

  /// Videos that could not be read, so were not compared.
  final int videosUnreadable;
  final List<VideoDuplicateGroup> groups;

  int get recoverableBytes => groups.fold<int>(
    0,
    (total, group) => total + group.bytesFreedKeeping(group.original),
  );
}

/// Videos that could be identical: the same length and picture size. Copies
/// of a file always match on these, so only these need reading, which keeps
/// the scan quick on a large library.
List<List<VideoItem>> candidateSets(Iterable<VideoItem> videos) {
  final byKey = <String, List<VideoItem>>{};
  for (final video in videos) {
    final key = '${video.durationSeconds}|${video.width}|${video.height}';
    byKey.putIfAbsent(key, () => []).add(video);
  }
  return [
    for (final set in byKey.values)
      if (set.length > 1) set,
  ];
}

/// Reads each candidate with [fingerprint] and returns the sets whose size
/// and hash are identical. A video [fingerprint] returns null for is left out
/// and counted in [onUnreadable].
Future<List<VideoDuplicateGroup>> groupIdenticalVideos(
  List<List<VideoItem>> candidates,
  Future<({int size, String sha256})?> Function(VideoItem video) fingerprint, {
  bool Function()? shouldCancel,
  void Function(int read)? onProgress,
  void Function()? onUnreadable,
}) async {
  final groups = <VideoDuplicateGroup>[];
  var read = 0;
  for (final set in candidates) {
    final byContent = <String, List<VideoItem>>{};
    for (final video in set) {
      if (shouldCancel?.call() ?? false) throw const ScanCancelled();
      final content = await fingerprint(video);
      read += 1;
      onProgress?.call(read);
      if (content == null || content.size <= 0) {
        onUnreadable?.call();
        continue;
      }
      byContent
          .putIfAbsent('${content.size}|${content.sha256}', () => [])
          .add(video.withContent(size: content.size, sha256: content.sha256));
    }
    for (final entry in byContent.entries) {
      if (entry.value.length > 1) {
        groups.add(VideoDuplicateGroup(id: entry.key, items: entry.value));
      }
    }
  }
  groups.sort((a, b) {
    final bySaving = b
        .bytesFreedKeeping(b.original)
        .compareTo(a.bytesFreedKeeping(a.original));
    return bySaving != 0 ? bySaving : a.id.compareTo(b.id);
  });
  return groups;
}

/// Finds identical videos in a media-library album, on the phone.
class VideoDuplicateScanner {
  Future<bool> requestAccess() async {
    final state = await PhotoManager.requestPermissionExtend();
    return state == PermissionState.authorized ||
        state == PermissionState.limited;
  }

  /// Every album with at least one video: "All videos" first, then the
  /// biggest albums.
  Future<List<VideoAlbum>> listAlbums() async {
    final all = <VideoAlbum>[];
    final albums = <VideoAlbum>[];
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.video,
      hasAll: true,
    );
    for (final path in paths) {
      final count = await path.assetCountAsync;
      if (count == 0) continue;
      final album = VideoAlbum(
        id: path.id,
        name: path.isAll ? 'All videos' : path.name,
        count: count,
      );
      (path.isAll ? all : albums).add(album);
    }
    albums.sort((a, b) => b.count.compareTo(a.count));
    return [...all, ...albums];
  }

  Future<AssetPathEntity?> _album(String id) async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.video,
      hasAll: true,
      filterOption: FilterOptionGroup(
        orders: [OrderOption(type: OrderOptionType.createDate, asc: false)],
      ),
    );
    for (final path in paths) {
      if (path.id == id) return path;
    }
    return null;
  }

  /// The date limits for [range]: videos from [lower] on and before [upper].
  static ({DateTime? lower, DateTime? upper}) dateWindow(
    FolderDateRange range, {
    DateTime? from,
    DateTime? to,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    switch (range) {
      case FolderDateRange.today:
        return (
          lower: DateTime(today.year, today.month, today.day),
          upper: null,
        );
      case FolderDateRange.week:
        return (lower: today.subtract(const Duration(days: 7)), upper: null);
      case FolderDateRange.month:
        return (lower: today.subtract(const Duration(days: 30)), upper: null);
      case FolderDateRange.custom:
        return (
          lower: from == null ? null : DateTime(from.year, from.month, from.day),
          upper: to == null ? null : DateTime(to.year, to.month, to.day + 1),
        );
      case FolderDateRange.currentFolder:
        return (lower: null, upper: null);
    }
  }

  Future<VideoScanResult> scan(
    VideoAlbum album, {
    FolderDateRange dateRange = FolderDateRange.currentFolder,
    DateTime? rangeFrom,
    DateTime? rangeTo,
    void Function(int found)? onListed,
    void Function(int total)? onTotal,
    void Function(int read)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final window = dateWindow(dateRange, from: rangeFrom, to: rangeTo);
    final path = await _album(album.id);
    if (path == null) {
      return VideoScanResult(
        albumName: album.name,
        videosFound: 0,
        videosRead: 0,
        groups: const [],
      );
    }
    final videos = <VideoItem>[];
    final entities = <String, AssetEntity>{};
    final count = await path.assetCountAsync;
    const page = 300;
    for (var start = 0; start < count; start += page) {
      if (shouldCancel?.call() ?? false) throw const ScanCancelled();
      final assets = await path.getAssetListRange(
        start: start,
        end: start + page > count ? count : start + page,
      );
      for (final asset in assets) {
        final created = asset.createDateTime;
        if (window.lower != null && created.isBefore(window.lower!)) continue;
        if (window.upper != null && !created.isBefore(window.upper!)) continue;
        final title = asset.title ?? await asset.titleAsync;
        videos.add(
          VideoItem(
            id: asset.id,
            title: title,
            durationSeconds: asset.duration,
            width: asset.width,
            height: asset.height,
            createdAt: created,
          ),
        );
        entities[asset.id] = asset;
      }
      onListed?.call(videos.length);
    }

    final candidates = candidateSets(videos);
    final toRead = candidates.fold<int>(0, (total, set) => total + set.length);
    onTotal?.call(toRead);
    var unreadable = 0;
    List<VideoDuplicateGroup> groups;
    try {
      groups = await groupIdenticalVideos(
        candidates,
        (video) => _fingerprint(entities[video.id]),
        shouldCancel: shouldCancel,
        onProgress: onProgress,
        onUnreadable: () => unreadable += 1,
      );
    } finally {
      // Reading a video may leave a temporary copy; do not leave them behind.
      try {
        await PhotoManager.clearFileCache();
      } catch (_) {}
    }

    final withThumbnails = <VideoDuplicateGroup>[];
    for (final group in groups) {
      withThumbnails.add(
        VideoDuplicateGroup(
          id: group.id,
          items: [
            for (final item in group.items)
              item.withThumbnail(
                await entities[item.id]?.thumbnailDataWithSize(
                  const ThumbnailSize.square(320),
                ),
              ),
          ],
        ),
      );
    }
    return VideoScanResult(
      albumName: album.name,
      videosFound: videos.length,
      videosRead: toRead,
      videosUnreadable: unreadable,
      groups: withThumbnails,
    );
  }

  /// Size and SHA-256 of the whole file, read in chunks so a large video is
  /// never held in memory. Null when the file cannot be read.
  Future<({int size, String sha256})?> _fingerprint(AssetEntity? asset) async {
    if (asset == null) return null;
    try {
      final file = await asset.originFile;
      if (file == null) return null;
      return await fingerprintFile(file);
    } catch (error) {
      debugPrint('Video could not be read: ${error.runtimeType}');
      return null;
    }
  }

  /// Deletes videos from the media library; returns the ids that were deleted.
  /// Android asks the person to confirm once for the whole batch.
  Future<Set<String>> deleteVideos(List<String> ids) async {
    if (ids.isEmpty) return {};
    try {
      return (await PhotoManager.editor.deleteWithIds(ids)).toSet();
    } catch (error) {
      debugPrint('Video delete failed: ${error.runtimeType}');
      return {};
    }
  }
}

/// Size and SHA-256 of [file], streamed.
Future<({int size, String sha256})> fingerprintFile(File file) async {
  final size = await file.length();
  final digest = await sha256.bind(file.openRead()).first;
  return (size: size, sha256: digest.toString());
}
