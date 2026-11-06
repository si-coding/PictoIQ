import 'dart:io' show File;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart'
    show
        AndroidPermission,
        AssetEntity,
        AssetPathEntity,
        DurationConstraint,
        FilterOption,
        FilterOptionGroup,
        OrderOption,
        OrderOptionType,
        PermissionRequestOption,
        PermissionState,
        PhotoManager,
        RequestType,
        SizeConstraint,
        ThumbnailSize;
import 'package:saf/saf.dart';

import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart'
    show FolderDateRange, ScanCancelled;

/// Which video of an identical set is kept unless the person picks another.
enum VideoKeep {
  oldest('Oldest', 'Keeps the video that was recorded or saved first.'),
  newest('Newest', 'Keeps the most recent copy.');

  const VideoKeep(this.label, this.description);

  final String label;
  final String description;
}

/// How much of the video library the person has let PictoIQ see.
enum VideoAccess {
  /// Every video.
  granted,

  /// Only the videos the person chose to share (Android 14+).
  limited,

  /// None.
  denied,
}

/// Where to look for videos: an album of the phone's media library, or a
/// folder picked with Android's folder picker ([folderUri] is then set).
class VideoAlbum {
  const VideoAlbum({
    required this.id,
    required this.name,
    required this.count,
    this.folderUri,
  });

  final String id;
  final String name;
  final int count;

  /// Set for a picked folder; null for a media-library album.
  final String? folderUri;

  bool get isFolder => folderUri != null;
}

/// A video as shown in an album grid before an album is chosen.
class VideoPreview {
  const VideoPreview({
    required this.thumbnail,
    required this.durationSeconds,
    required this.createdAt,
  });

  final Uint8List? thumbnail;
  final int durationSeconds;
  final DateTime createdAt;
}

/// A [VideoItem.id] that starts with this is a file in a picked folder, not
/// in the media library.
const folderVideoPrefix = 'saf:';

/// File extensions treated as video when a picked folder gives no type.
const _videoExtensions = {
  '.3gp',
  '.avi',
  '.m4v',
  '.mkv',
  '.mov',
  '.mp4',
  '.mpeg',
  '.mpg',
  '.webm',
};

bool _isVideoFile(String name, String? mimeType) {
  if (mimeType?.toLowerCase().startsWith('video/') ?? false) return true;
  return _videoExtensions.contains(p.extension(name).toLowerCase());
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

  /// The video kept by default under [rule].
  VideoItem suggestedKeep(VideoKeep rule) =>
      rule == VideoKeep.newest ? items.last : items.first;
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

/// Videos that could be identical. Copies of a file always match on file size
/// when it is known (a picked folder), else on length and picture size (the
/// media library), so only these need reading, which keeps the scan quick on a
/// large library.
List<List<VideoItem>> candidateSets(Iterable<VideoItem> videos) {
  final byKey = <String, List<VideoItem>>{};
  for (final video in videos) {
    final key = video.size > 0
        ? 'size:${video.size}'
        : '${video.durationSeconds}|${video.width}|${video.height}';
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
  VideoDuplicateScanner({Saf? saf}) : _saf = saf ?? Saf();

  final Saf _saf;

  /// What Android last said about video access and how many video albums it
  /// then listed. Shown on the album picker to help find permission problems.
  String accessDetail = '';

  /// Lets the person pick more videos to share when access is partial
  /// (Android 14+). Falls back to the app's settings.
  Future<void> manageLimitedAccess() async {
    try {
      await PhotoManager.presentLimited(type: RequestType.video);
    } catch (error) {
      debugPrint('presentLimited failed: $error');
      await PhotoManager.openSetting();
    }
  }

  /// Asks Android for access to photos and videos together, the same request
  /// the photo albums make, so one answer covers both. Photo access alone does
  /// not include videos on Android 13 and later.
  Future<VideoAccess> requestAccess() async {
    PermissionState state;
    try {
      state = await PhotoManager.requestPermissionExtend(
        requestOption: PermissionRequestOption(
          androidPermission: AndroidPermission(
            type: RequestType.common,
            mediaLocation: false,
          ),
        ),
      );
    } catch (error) {
      // Fall back to the plain request.
      debugPrint('Permission request failed: $error');
      state = await PhotoManager.requestPermissionExtend();
    }
    accessDetail = 'Android reports: ${state.name}.';
    if (state == PermissionState.authorized) return VideoAccess.granted;
    if (state == PermissionState.limited) return VideoAccess.limited;
    return VideoAccess.denied;
  }

  /// Opens Android's folder picker, for videos that are not in the media
  /// library. Null when the person cancels.
  Future<VideoAlbum?> pickFolder() async {
    final folder = await _saf.pickDirectory(
      writePermission: true,
      persistablePermission: true,
    );
    if (folder == null) return null;
    return VideoAlbum(
      id: 'folder:${folder.uri}',
      name: folder.name,
      count: 0,
      folderUri: folder.uri,
    );
  }

  /// Wide limits so no video is left out because of its length or size. The
  /// longest length stays under about 24 days, because Android stores it in
  /// milliseconds in a 32-bit number.
  FilterOptionGroup _filter() => FilterOptionGroup(
    videoOption: FilterOption(
      sizeConstraint: SizeConstraint(ignoreSize: true),
      durationConstraint: DurationConstraint(
        max: const Duration(days: 20),
        allowNullable: true,
      ),
    ),
    orders: [OrderOption(type: OrderOptionType.createDate, asc: false)],
  );

  Future<List<AssetPathEntity>>? _pathsCache;

  Future<List<AssetPathEntity>> _paths({bool refresh = false}) {
    if (refresh || _pathsCache == null) {
      _pathsCache = _loadPaths();
    }
    return _pathsCache!;
  }

  Future<List<AssetPathEntity>> _loadPaths() async {
    try {
      return await PhotoManager.getAssetPathList(
        type: RequestType.video,
        hasAll: true,
        filterOption: _filter(),
      );
    } catch (error) {
      // If the wider filter is refused, use the library's default one.
      debugPrint('Video albums with the wide filter failed: $error');
      return PhotoManager.getAssetPathList(
        type: RequestType.video,
        hasAll: true,
      );
    }
  }

  Future<List<AssetEntity>> _albumAssets(String id, int start, int end) async {
    final path = await _album(id);
    if (path == null) return const [];
    return path.getAssetListRange(start: start, end: end);
  }

  /// Pictures and lengths for videos [start] up to [end] (newest first) of
  /// album [id], for the album contents screen.
  Future<List<VideoPreview>> albumVideos(String id, int start, int end) async {
    final assets = await _albumAssets(id, start, end);
    return Future.wait([
      for (final asset in assets)
        asset
            .thumbnailDataWithSize(const ThumbnailSize.square(240))
            .then(
              (bytes) => VideoPreview(
                thumbnail: bytes,
                durationSeconds: asset.duration,
                createdAt: asset.createDateTime,
              ),
            ),
    ]);
  }

  /// Where the video at [index] of album [id] can be played from: a
  /// `content://` address or a file path. Null when there is none.
  Future<String?> videoUrl(String id, int index) async {
    final assets = await _albumAssets(id, index, index + 1);
    if (assets.isEmpty) return null;
    try {
      return await assets.first.getMediaUrl();
    } catch (error) {
      debugPrint('Video address unavailable: ${error.runtimeType}');
      return null;
    }
  }

  /// A small picture for an album: its newest video.
  Future<Uint8List?> albumCover(String id) async {
    final path = await _album(id);
    if (path == null) return null;
    final assets = await path.getAssetListRange(start: 0, end: 1);
    if (assets.isEmpty) return null;
    return assets.first.thumbnailDataWithSize(const ThumbnailSize.square(320));
  }

  /// Every album with at least one video: "All videos" first, then the
  /// biggest albums.
  Future<List<VideoAlbum>> listAlbums() async {
    final all = <VideoAlbum>[];
    final albums = <VideoAlbum>[];
    for (final path in await _paths(refresh: true)) {
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
    accessDetail =
        '$accessDetail Video albums found: ${all.length + albums.length}.';
    return [...all, ...albums];
  }

  Future<AssetPathEntity?> _album(String id) async {
    for (final path in await _paths()) {
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
    if (album.isFolder) {
      return _scanFolder(
        album,
        window: window,
        onListed: onListed,
        onTotal: onTotal,
        onProgress: onProgress,
        shouldCancel: shouldCancel,
      );
    }
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

  /// Videos in a folder picked with Android's folder picker. File sizes come
  /// with the listing, so only files of equal size are read.
  Future<VideoScanResult> _scanFolder(
    VideoAlbum album, {
    required ({DateTime? lower, DateTime? upper}) window,
    void Function(int found)? onListed,
    void Function(int total)? onTotal,
    void Function(int read)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final videos = <VideoItem>[];
    await for (final entry in _saf.walk(album.folderUri!)) {
      if (shouldCancel?.call() ?? false) throw const ScanCancelled();
      final file = entry.file;
      if (file.isDir || !_isVideoFile(file.name, file.mimeType)) continue;
      final modified = DateTime.fromMillisecondsSinceEpoch(file.lastModified);
      if (window.lower != null && modified.isBefore(window.lower!)) continue;
      if (window.upper != null && !modified.isBefore(window.upper!)) continue;
      videos.add(
        VideoItem(
          id: '$folderVideoPrefix${file.uri}',
          title: file.name,
          durationSeconds: 0,
          width: 0,
          height: 0,
          createdAt: modified,
          size: file.length,
        ),
      );
      if (videos.length % 20 == 0) onListed?.call(videos.length);
    }
    onListed?.call(videos.length);

    final candidates = candidateSets(videos);
    final toRead = candidates.fold<int>(0, (total, set) => total + set.length);
    onTotal?.call(toRead);
    var unreadable = 0;
    final groups = await groupIdenticalVideos(
      candidates,
      _folderFingerprint,
      shouldCancel: shouldCancel,
      onProgress: onProgress,
      onUnreadable: () => unreadable += 1,
    );
    return VideoScanResult(
      albumName: album.name,
      videosFound: videos.length,
      videosRead: toRead,
      videosUnreadable: unreadable,
      groups: groups,
    );
  }

  Future<({int size, String sha256})?> _folderFingerprint(
    VideoItem video,
  ) async {
    try {
      final uri = video.id.substring(folderVideoPrefix.length);
      final digest = await sha256.bind(await _saf.readFileStream(uri)).first;
      return (size: video.size, sha256: digest.toString());
    } catch (error) {
      debugPrint('Video could not be read: ${error.runtimeType}');
      return null;
    }
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
    final deleted = <String>{};
    final library = [
      for (final id in ids)
        if (!id.startsWith(folderVideoPrefix)) id,
    ];
    if (library.isNotEmpty) {
      try {
        deleted.addAll(await PhotoManager.editor.deleteWithIds(library));
      } catch (error) {
        debugPrint('Video delete failed: ${error.runtimeType}');
      }
    }
    for (final id in ids) {
      if (!id.startsWith(folderVideoPrefix)) continue;
      try {
        await _saf.delete(id.substring(folderVideoPrefix.length));
        deleted.add(id);
      } catch (_) {
        // Left out of the result; the caller reports it as not deleted.
      }
    }
    return deleted;
  }
}

/// Size and SHA-256 of [file], streamed.
Future<({int size, String sha256})> fingerprintFile(File file) async {
  final size = await file.length();
  final digest = await sha256.bind(file.openRead()).first;
  return (size: size, sha256: digest.toString());
}
