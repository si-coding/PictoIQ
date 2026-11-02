import 'dart:io' show Directory, File;
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart'
    show getTemporaryDirectory;
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
import 'package:saf/saf.dart';

import 'scan_image_processing.dart';
import 'shot_ranking.dart';
import 'similarity_grouping.dart';

class _ShotAnalysis {
  const _ShotAnalysis({
    required this.visualHash,
    required this.captureTime,
    required this.signals,
    required this.megapixels,
    required this.preview,
    required this.faceBitmap,
    required this.faceWidth,
    required this.faceHeight,
    required this.colorHistogram,
    required this.colorLayout,
    required this.isDocument,
    required this.documentDetail,
  });

  final int visualHash;
  final (int, int) captureTime;
  final ImageSignals signals;
  final double megapixels;
  final Uint8List preview;

  /// Raw RGBA pixels (width x height x 4 bytes) handed to face detection;
  /// null when face signals are turned off or the pixels could not be built.
  final Uint8List? faceBitmap;
  final int faceWidth;
  final int faceHeight;

  /// Colour profile used to link quick shots whose framing differs.
  final List<double> colorHistogram;

  /// Where the colours are, used to tell scenes apart by their background.
  final List<double> colorLayout;

  /// Looks like a page of text or similar (see [looksLikeDocument]).
  final bool isDocument;
  final List<double>? documentDetail;
}

class FolderScanPhoto {
  const FolderScanPhoto({
    required this.uri,
    required this.name,
    required this.relativePath,
    required this.size,
    required this.modifiedAt,
    required this.sha256,
    required this.visualHash,
    required this.qualityScore,
    required this.qualityNotes,
    required this.previewBytes,
    this.capturedAt = 0,
    this.captureSource = captureSourceUnknown,
    this.features,
    this.colorHistogram,
    this.colorLayout,
    this.isDocument = false,
    this.documentDetail,
  });

  /// Where [capturedAt] came from. Times from different sources are never
  /// compared with each other, because EXIF stores local wall-clock time while
  /// the file's modified time is a real instant.
  static const captureSourceUnknown = CaptureSource.unknown;
  static const captureSourceExif = CaptureSource.exif;
  static const captureSourceModified = CaptureSource.modified;

  final String uri;
  final String name;
  final String relativePath;
  final int size;
  final int modifiedAt;
  final String? sha256;
  final int visualHash;
  final int qualityScore;
  final List<String> qualityNotes;
  final Uint8List? previewBytes;

  /// Capture time in milliseconds, or 0 when unknown.
  final int capturedAt;
  final int captureSource;

  /// Measurements the best-shot ranking works from. Null for exact-duplicate
  /// scans, which do not analyse pixels.
  final ShotFeatures? features;

  /// Colour profile for grouping quick shots; null for exact-duplicate scans.
  final List<double>? colorHistogram;

  /// Colour arrangement for grouping by content; null for exact scans.
  final List<double>? colorLayout;

  /// Document-like image; faces found later can override this.
  final bool isDocument;
  final List<double>? documentDetail;

  /// True for a document-like image with no faces in it.
  bool get isDocumentLike =>
      isDocument && (features?.faces?.count ?? 0) == 0;

  FolderScanPhoto withPreviewBytes(Uint8List? bytes) => FolderScanPhoto(
    uri: uri,
    name: name,
    relativePath: relativePath,
    size: size,
    modifiedAt: modifiedAt,
    sha256: sha256,
    visualHash: visualHash,
    qualityScore: qualityScore,
    qualityNotes: qualityNotes,
    previewBytes: bytes,
    capturedAt: capturedAt,
    captureSource: captureSource,
    features: features,
    colorHistogram: colorHistogram,
    colorLayout: colorLayout,
    isDocument: isDocument,
    documentDetail: documentDetail,
  );

  /// Copy carrying the group-relative score and reasons from [rankShots].
  FolderScanPhoto withQuality({
    required int score,
    required List<String> notes,
  }) => FolderScanPhoto(
    uri: uri,
    name: name,
    relativePath: relativePath,
    size: size,
    modifiedAt: modifiedAt,
    sha256: sha256,
    visualHash: visualHash,
    qualityScore: score,
    qualityNotes: notes,
    previewBytes: previewBytes,
    capturedAt: capturedAt,
    captureSource: captureSource,
    features: features,
    colorHistogram: colorHistogram,
    colorLayout: colorLayout,
    isDocument: isDocument,
    documentDetail: documentDetail,
  );

  DateTime? get modifiedDate =>
      modifiedAt <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(modifiedAt);
}

enum FolderDateRange {
  today('Today'),
  week('Last 7 days'),
  month('Last 30 days'),
  currentFolder('Current folder'),
  custom('Custom range');

  const FolderDateRange(this.label);

  final String label;
}

class FolderSelection {
  const FolderSelection({required this.uri, required this.name});

  final String uri;
  final String name;
}

class FolderDuplicateGroup {
  FolderDuplicateGroup({
    required this.id,
    required List<FolderScanPhoto> photos,
    this.evidence,
    this.ranking,
  }) : photos = List.unmodifiable(photos);

  final String id;
  final List<FolderScanPhoto> photos;

  /// How sure PictoIQ is that these are the same scene, and why. Null for
  /// exact-duplicate groups, which are byte-for-byte identical.
  final SimilarityEvidence? evidence;

  /// Why the photos are ordered as they are. Null for exact-duplicate groups.
  final GroupRanking? ranking;

  List<FolderScanPhoto> get oldestFirst {
    final sorted = [...photos];
    sorted.sort((left, right) {
      final leftDate = left.modifiedAt > 0
          ? left.modifiedAt
          : 0x7fffffffffffffff;
      final rightDate = right.modifiedAt > 0
          ? right.modifiedAt
          : 0x7fffffffffffffff;
      final byDate = leftDate.compareTo(rightDate);
      if (byDate != 0) return byDate;
      return left.relativePath.compareTo(right.relativePath);
    });
    return sorted;
  }

  /// This group without the photos in [removed], re-ranked from what is left.
  /// Null when fewer than two photos remain, so it is no longer a group.
  FolderDuplicateGroup? without(Set<String> removed) {
    final left = [
      for (final photo in photos)
        if (!removed.contains(photo.uri)) photo,
    ];
    if (left.length < 2) return null;
    if (left.length == photos.length) return this;
    final evidence = this.evidence;
    if (evidence == null) return FolderDuplicateGroup(id: id, photos: left);
    return rankedGroup(left, evidence, id: id);
  }

  FolderScanPhoto get original => oldestFirst.first;
  List<FolderScanPhoto> get newerCopies => oldestFirst.skip(1).toList();
  List<FolderScanPhoto> get bestFirst {
    final ranked = ranking;
    if (ranked != null) {
      final byId = {for (final photo in photos) photo.uri: photo};
      final ordered = [
        for (final shot in ranked.shots)
          if (byId[shot.id] != null) byId[shot.id]!,
      ];
      if (ordered.length == photos.length) return ordered;
    }
    final sorted = [...photos];
    sorted.sort((a, b) {
      final byQuality = b.qualityScore.compareTo(a.qualityScore);
      return byQuality != 0
          ? byQuality
          : a.relativePath.compareTo(b.relativePath);
    });
    return sorted;
  }

  FolderScanPhoto get recommended => bestFirst.first;
  List<FolderScanPhoto> get otherShots => bestFirst.skip(1).toList();
}

class FolderScanResult {
  const FolderScanResult({
    required this.folderUri,
    required this.folderName,
    required this.imagesScanned,
    required this.duplicateGroups,
    required this.bestShotsScan,
    required this.dateRange,
    this.rangeStart,
    this.rangeEnd,
    this.imagesSkipped = 0,
    this.imageFilesFound = 0,
    this.imagesOutsideDateRange = 0,
    this.scannedPhotos = const [],
    this.skippedNames = const [],
    this.documentsLeftOut = 0,
  });

  final String folderUri;
  final String folderName;
  final int imagesScanned;
  final List<FolderDuplicateGroup> duplicateGroups;
  final bool bestShotsScan;
  final FolderDateRange dateRange;

  /// The first and last day the scan covered (null for "Current folder").
  final DateTime? rangeStart;
  final DateTime? rangeEnd;

  /// The date range in words for result screens, for example
  /// "Last 7 days (25 Oct 2026 – 1 Nov 2026)" or "All dates".
  String get rangeDescription {
    if (dateRange == FolderDateRange.currentFolder) return 'All dates';
    String day(DateTime d) {
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${d.day} ${months[d.month - 1]} ${d.year}';
    }

    final from = rangeStart;
    final to = rangeEnd;
    final dates = from != null && to != null
        ? '${day(from)} – ${day(to)}'
        : from != null
        ? 'from ${day(from)}'
        : to != null
        ? 'up to ${day(to)}'
        : null;
    if (dateRange == FolderDateRange.custom) return dates ?? 'Custom range';
    return dates == null ? dateRange.label : '${dateRange.label} ($dates)';
  }

  /// Images that could not be read or decoded (for example HEIC files) and
  /// were left out of the scan, so they can never be offered for deletion.
  final int imagesSkipped;

  /// Image files seen in the folder before the date filter was applied.
  final int imageFilesFound;

  /// Image files left out because they are older than the chosen date range.
  final int imagesOutsideDateRange;

  /// Every photo that was read and analysed, grouped or not, so the user can
  /// check what the scan actually looked at.
  final List<FolderScanPhoto> scannedPhotos;

  /// Paths of files that could not be read or decoded.
  final List<String> skippedNames;

  /// Document-like images left out of grouping (see [DocumentMode]).
  final int documentsLeftOut;

  /// This result after the photos in [removed] were deleted: groups shrink
  /// or disappear and similar-photo groups are re-ranked, without scanning the
  /// folder again.
  FolderScanResult withoutPhotos(Set<String> removed) {
    if (removed.isEmpty) return this;
    final groups = <FolderDuplicateGroup>[];
    var removedCount = 0;
    for (final group in duplicateGroups) {
      removedCount += group.photos.where((p) => removed.contains(p.uri)).length;
      final updated = group.without(removed);
      if (updated != null) groups.add(updated);
    }
    return FolderScanResult(
      folderUri: folderUri,
      folderName: folderName,
      imagesScanned: math.max(0, imagesScanned - removedCount),
      duplicateGroups: List.unmodifiable(groups),
      bestShotsScan: bestShotsScan,
      dateRange: dateRange,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      imagesSkipped: imagesSkipped,
      imageFilesFound: imageFilesFound,
      imagesOutsideDateRange: imagesOutsideDateRange,
      scannedPhotos: List.unmodifiable([
        for (final photo in scannedPhotos)
          if (!removed.contains(photo.uri)) photo,
      ]),
      skippedNames: skippedNames,
      documentsLeftOut: documentsLeftOut,
    );
  }

  /// This result with [uri] taken out of the group [groupId] (the person said
  /// it is not the same scene). Nothing is deleted; the photo just stops being
  /// offered for removal with that group, and the group is re-ranked.
  FolderScanResult withoutFromGroup(String groupId, String uri) {
    final groups = <FolderDuplicateGroup>[];
    for (final group in duplicateGroups) {
      if (group.id != groupId) {
        groups.add(group);
        continue;
      }
      final updated = group.without({uri});
      if (updated != null) groups.add(updated);
    }
    return FolderScanResult(
      folderUri: folderUri,
      folderName: folderName,
      imagesScanned: imagesScanned,
      duplicateGroups: List.unmodifiable(groups),
      bestShotsScan: bestShotsScan,
      dateRange: dateRange,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      imagesSkipped: imagesSkipped,
      imageFilesFound: imageFilesFound,
      imagesOutsideDateRange: imagesOutsideDateRange,
      scannedPhotos: scannedPhotos,
      skippedNames: skippedNames,
      documentsLeftOut: documentsLeftOut,
    );
  }

  /// This result with the whole group [groupId] set aside (skipped). Nothing
  /// is deleted; the group just stops being offered.
  FolderScanResult withoutGroup(String groupId) => FolderScanResult(
    folderUri: folderUri,
    folderName: folderName,
    imagesScanned: imagesScanned,
    duplicateGroups: List.unmodifiable([
      for (final group in duplicateGroups)
        if (group.id != groupId) group,
    ]),
    bestShotsScan: bestShotsScan,
    dateRange: dateRange,
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
    imagesSkipped: imagesSkipped,
    imageFilesFound: imageFilesFound,
    imagesOutsideDateRange: imagesOutsideDateRange,
    scannedPhotos: scannedPhotos,
    skippedNames: skippedNames,
    documentsLeftOut: documentsLeftOut,
  );

  int get duplicateFileCount =>
      duplicateGroups.fold(0, (count, group) => count + group.photos.length);

  List<FolderScanPhoto> get removablePhotos => duplicateGroups
      .expand((group) => bestShotsScan ? group.otherShots : group.newerCopies)
      .toList(growable: false);

  int get reclaimableBytes =>
      removablePhotos.fold(0, (total, photo) => total + photo.size);
}

/// Thrown by [FolderDuplicateScanner.scanUri] when the caller asked to stop.
class ScanCancelled implements Exception {
  const ScanCancelled();

  @override
  String toString() => 'Scan cancelled';
}

Future<Uint8List?> _largePreviewInIsolate(Uint8List bytes) => Isolate.run(() {
  final decoded = decodeAnalysisImage(bytes, edge: 2048);
  return decoded == null
      ? null
      : encodePreview(decoded, edge: 2048, quality: 90);
});

/// A photo album from the phone's media library (Camera, Screenshots, ...).
class MediaAlbum {
  const MediaAlbum({required this.id, required this.name, required this.count});

  final String id;
  final String name;
  final int count;

  /// The [FolderSelection] that scans this album.
  FolderSelection get selection => FolderSelection(
    uri: '${FolderDuplicateScanner.albumPrefix}$id',
    name: name,
  );
}

/// One file found while listing a folder or album, before any filtering.
class _SourceFile {
  const _SourceFile({
    required this.uri,
    required this.name,
    required this.relativePath,
    required this.length,
    required this.lastModified,
    required this.dateMs,
    this.isCandidate = true,
  });

  final String uri;
  final String name;
  final String relativePath;
  final int length;
  final int lastModified;

  /// The date the date-range filter uses (date taken for the media library,
  /// modified time for folders).
  final int dateMs;

  /// False for directories, thumbnails and non-image files.
  final bool isCandidate;
}

/// The most recent modified time in [group], for newest-first ordering.
int _newestModified(FolderDuplicateGroup group) => group.photos.fold(
  0,
  (newest, photo) => photo.modifiedAt > newest ? photo.modifiedAt : newest,
);

/// Runs [_analyzeShot] in a background isolate. A top-level function keeps
/// the closure's captured state to just these arguments; a closure built
/// inside the scan loop would drag the scan's callbacks and results into the
/// message, which an isolate cannot receive.
Future<_ShotAnalysis?> _analyzeInIsolate(
  Uint8List bytes,
  int modifiedAt,
  String name,
  bool useFaceSignals,
) => Isolate.run(
  () => FolderDuplicateScanner._analyzeShot(
    bytes,
    modifiedAt,
    name,
    useFaceSignals,
  ),
);

class FolderDuplicateScanner {
  FolderDuplicateScanner({
    Saf? saf,
    this.thresholds = SimilarityThresholds.content,
  }) : _saf = saf ?? Saf();

  final Saf _saf;

  /// A [FolderSelection.uri] that starts with this is a media-library album.
  static const albumPrefix = 'album:';

  /// A photo uri that starts with this lives in the media library.
  static const mediaPrefix = 'media:';

  /// Asks for access to the phone's photos. True when granted (full or the
  /// photos the user chose to share).
  Future<bool> requestMediaAccess() async {
    final state = await PhotoManager.requestPermissionExtend();
    return state == PermissionState.authorized ||
        state == PermissionState.limited;
  }

  Future<List<AssetPathEntity>>? _albumPathsCache;

  /// Albums are looked up once per screen visit (see [listAlbums]), then
  /// reused for covers and scans.
  Future<List<AssetPathEntity>> _albumPaths({bool refresh = false}) {
    if (refresh || _albumPathsCache == null) {
      _albumPathsCache = PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: true,
        // Newest photos first, stated outright rather than left to the
        // device's default order.
        filterOption: FilterOptionGroup(
          orders: [OrderOption(type: OrderOptionType.createDate, asc: false)],
        ),
      );
    }
    return _albumPathsCache!;
  }

  /// Every album with at least one photo: "All photos" first, then the
  /// biggest albums.
  Future<List<MediaAlbum>> listAlbums() async {
    final albums = <MediaAlbum>[];
    final all = <MediaAlbum>[];
    for (final path in await _albumPaths(refresh: true)) {
      final count = await path.assetCountAsync;
      if (count == 0) continue;
      final album = MediaAlbum(
        id: path.id,
        name: path.isAll ? 'All photos' : path.name,
        count: count,
      );
      (path.isAll ? all : albums).add(album);
    }
    albums.sort((a, b) => b.count.compareTo(a.count));
    return [...all, ...albums];
  }

  Future<AssetPathEntity?> _albumPath(String id) async {
    for (final path in await _albumPaths()) {
      if (path.id == id) return path;
    }
    return null;
  }

  /// Photos [start] up to [end] (newest first) of the album [id].
  Future<List<AssetEntity>> albumAssets(String id, int start, int end) async {
    final path = await _albumPath(id);
    if (path == null) return const [];
    return path.getAssetListRange(start: start, end: end);
  }

  /// Small pictures for photos [start] up to [end] of album [id].
  Future<List<Uint8List?>> albumThumbnails(String id, int start, int end) async {
    final assets = await albumAssets(id, start, end);
    return Future.wait([
      for (final asset in assets)
        asset.thumbnailDataWithSize(const ThumbnailSize.square(240)),
    ]);
  }

  /// The photo at [index] of album [id], for the enlarged view.
  Future<Uint8List?> albumPhoto(String id, int index) async {
    final assets = await albumAssets(id, index, index + 1);
    if (assets.isEmpty) return null;
    final bytes = await assets.first.originBytes;
    if (bytes == null || bytes.length > maxEncodedImageBytes) return null;
    return bytes;
  }

  /// A small cover picture for an album: its newest photo.
  Future<Uint8List?> albumCover(String id) async {
    final assets = await albumAssets(id, 0, 1);
    if (assets.isEmpty) return null;
    return assets.first.thumbnailDataWithSize(const ThumbnailSize.square(320));
  }

  Stream<_SourceFile> _listSaf(String folderUri) async* {
    await for (final entry in _saf.walk(folderUri)) {
      final file = entry.file;
      yield _SourceFile(
        uri: file.uri,
        name: file.name,
        relativePath: entry.relativePath,
        length: file.length,
        lastModified: file.lastModified,
        dateMs: file.lastModified,
        isCandidate:
            !file.isDir &&
            !_isSystemThumbnail(entry.relativePath) &&
            _isImage(file.name, file.mimeType),
      );
    }
  }

  Stream<_SourceFile> _listAlbum(String albumUri) async* {
    final path = await _albumPath(albumUri.substring(albumPrefix.length));
    if (path == null) return;
    final count = await path.assetCountAsync;
    const page = 300;
    for (var start = 0; start < count; start += page) {
      final assets = await path.getAssetListRange(
        start: start,
        end: math.min(start + page, count),
      );
      for (final asset in assets) {
        final title = asset.title ?? await asset.titleAsync;
        yield _SourceFile(
          uri: '$mediaPrefix${asset.id}',
          name: title,
          relativePath: '${asset.relativePath ?? ''}$title',
          length: 0,
          lastModified: asset.modifiedDateTime.millisecondsSinceEpoch,
          dateMs: asset.createDateTime.millisecondsSinceEpoch,
        );
      }
    }
  }

  /// The whole encoded file, from the media library or a picked folder.
  Future<Uint8List> _readAll(String uri) async {
    if (uri.startsWith(mediaPrefix)) {
      final asset = await AssetEntity.fromId(uri.substring(mediaPrefix.length));
      final bytes = await asset?.originBytes;
      if (bytes == null) throw const FormatException('Photo is unavailable.');
      if (bytes.length > maxEncodedImageBytes) {
        throw const FormatException('Image exceeds the 64 MiB analysis limit.');
      }
      return bytes;
    }
    return collectImageBytes(await _saf.readFileStream(uri));
  }

  /// Limits for grouping similar photos and rating the confidence of a group.
  final SimilarityThresholds thresholds;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  static const _imageExtensions = {
    '.avif',
    '.bmp',
    '.dng',
    '.gif',
    '.heic',
    '.heif',
    '.jfif',
    '.jpe',
    '.jpeg',
    '.jpg',
    '.png',
    '.tif',
    '.tiff',
    '.webp',
  };

  Future<FolderSelection?> pickFolder() async {
    final folder = await _saf.pickDirectory(
      writePermission: true,
      persistablePermission: true,
    );
    if (folder == null) return null;
    return FolderSelection(uri: folder.uri, name: folder.name);
  }

  Future<FolderScanResult?> pickAndScan({
    FolderDateRange dateRange = FolderDateRange.currentFolder,
    void Function(int imagesScanned)? onProgress,
  }) async {
    final folder = await _saf.pickDirectory(
      writePermission: true,
      persistablePermission: true,
    );
    if (folder == null) return null;
    return scanUri(
      folder.uri,
      folderName: folder.name,
      dateRange: dateRange,
      onProgress: onProgress,
    );
  }

  Future<FolderScanResult?> pickAndScanBestShots({
    FolderDateRange dateRange = FolderDateRange.currentFolder,
    void Function(int imagesScanned)? onProgress,
  }) async {
    final folder = await _saf.pickDirectory(
      writePermission: true,
      persistablePermission: true,
    );
    if (folder == null) return null;
    return scanUri(
      folder.uri,
      folderName: folder.name,
      bestShotsScan: true,
      dateRange: dateRange,
      onProgress: onProgress,
    );
  }

  Future<FolderScanResult> scanUri(
    String folderUri, {
    required String folderName,
    bool bestShotsScan = false,
    bool useFaceSignals = true,
    bool groupSessions = false,
    SimilarityThresholds? thresholds,
    DocumentMode documentMode = DocumentMode.leaveOut,
    FolderDateRange dateRange = FolderDateRange.currentFolder,
    DateTime? rangeFrom,
    DateTime? rangeTo,
    int concurrency = 3,
    void Function(int found, int checked)? onListed,
    void Function(int total)? onTotal,
    void Function(int imagesScanned)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final images = <FolderScanPhoto>[];
    var imagesScanned = 0;
    var imagesSkipped = 0;
    var imageFilesFound = 0;
    var imagesOutsideDateRange = 0;
    final skippedNames = <String>[];
    Object? firstError;
    final now = DateTime.now();
    // Photos modified before [lower] or from [upper] on are left out.
    final DateTime? lower;
    final DateTime? upper;
    switch (dateRange) {
      case FolderDateRange.today:
        lower = DateTime(now.year, now.month, now.day);
        upper = null;
      case FolderDateRange.week:
        lower = now.subtract(const Duration(days: 7));
        upper = null;
      case FolderDateRange.month:
        lower = now.subtract(const Duration(days: 30));
        upper = null;
      case FolderDateRange.custom:
        lower = rangeFrom == null
            ? null
            : DateTime(rangeFrom.year, rangeFrom.month, rangeFrom.day);
        // The end day is included, so the limit is the start of the next day.
        upper = rangeTo == null
            ? null
            : DateTime(rangeTo.year, rangeTo.month, rangeTo.day + 1);
      case FolderDateRange.currentFolder:
        lower = null;
        upper = null;
    }
    // The last day shown with the results: today for the quick ranges.
    final DateTime? shownEnd = switch (dateRange) {
      FolderDateRange.currentFolder => null,
      FolderDateRange.custom =>
        rangeTo == null
            ? null
            : DateTime(rangeTo.year, rangeTo.month, rangeTo.day),
      _ => DateTime(now.year, now.month, now.day),
    };

    // List the folder first (cheap), so the total is known and the slow part,
    // reading and analysing each photo, can run several at a time.
    final pending =
        <({
          String uri,
          String name,
          String relativePath,
          int length,
          int lastModified,
        })>[];
    var checked = 0;
    final source = folderUri.startsWith(albumPrefix)
        ? _listAlbum(folderUri)
        : _listSaf(folderUri);
    await for (final file in source) {
      if (shouldCancel?.call() ?? false) throw const ScanCancelled();
      checked += 1;
      // Report every file looked at (not just photos), so a folder full of
      // other files or out-of-range photos still shows movement.
      if (checked % 40 == 0) onListed?.call(pending.length, checked);
      if (!file.isCandidate) continue;
      imageFilesFound += 1;
      if (lower != null || upper != null) {
        final modified = file.dateMs <= 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch(file.dateMs);
        if (modified == null ||
            (lower != null && modified.isBefore(lower)) ||
            (upper != null && !modified.isBefore(upper))) {
          imagesOutsideDateRange += 1;
          continue;
        }
      }
      pending.add((
        uri: file.uri,
        name: file.name,
        relativePath: file.relativePath,
        length: file.length,
        lastModified: file.lastModified,
      ));
    }
    onListed?.call(pending.length, checked);
    onTotal?.call(pending.length);

    Future<void> processOne(
      ({
        String uri,
        String name,
        String relativePath,
        int length,
        int lastModified,
      })
      file,
    ) async {
      final entry = file;
      try {
        String? digest;
        _ShotAnalysis? analysis;
        var size = file.length;
        if (bestShotsScan) {
          final bytes = await _readAll(file.uri);
          if (file.uri.startsWith(mediaPrefix)) size = bytes.length;
          analysis = await _analyzeInIsolate(
            bytes,
            file.lastModified,
            file.name,
            useFaceSignals,
          );
        } else if (file.uri.startsWith(mediaPrefix)) {
          final bytes = await _readAll(file.uri);
          size = bytes.length;
          digest = sha256.convert(bytes).toString();
        } else {
          digest = (await sha256.bind(await _saf.readFileStream(file.uri)).first)
              .toString();
        }
        if (bestShotsScan && analysis == null) {
          // Formats the decoder cannot read (HEIC, AVIF, RAW...) have no visual
          // fingerprint. Leave them out so they are never grouped together or
          // offered for deletion.
          imagesSkipped += 1;
          skippedNames.add(entry.relativePath);
          onProgress?.call(imagesScanned + imagesSkipped);
          return;
        }
        final visualHash = analysis?.visualHash ?? 0;
        final (capturedAt, captureSource) = analysis == null
            ? (0, FolderScanPhoto.captureSourceUnknown)
            : analysis.captureTime;
        ShotFeatures? features;
        if (analysis != null) {
          final faceBitmap = analysis.faceBitmap;
          features = ShotFeatures(
            signals: analysis.signals,
            megapixels: analysis.megapixels,
            faces: faceBitmap == null
                ? null
                : await _detectFaces(
                    faceBitmap,
                    analysis.faceWidth,
                    analysis.faceHeight,
                  ),
          );
        }
        // Scores are relative to the rest of a group, so they are filled in
        // after grouping (see _groupSimilarShots).
        final photo = FolderScanPhoto(
          uri: file.uri,
          name: file.name,
          relativePath: entry.relativePath,
          size: size,
          modifiedAt: file.lastModified,
          sha256: digest,
          visualHash: visualHash,
          qualityScore: 0,
          qualityNotes: const [],
          previewBytes: analysis?.preview,
          capturedAt: capturedAt,
          captureSource: captureSource,
          features: features,
          colorHistogram: analysis?.colorHistogram,
          colorLayout: analysis?.colorLayout,
          isDocument: analysis?.isDocument ?? false,
          documentDetail: analysis?.documentDetail,
        );
        images.add(photo);
        imagesScanned += 1;
        onProgress?.call(imagesScanned + imagesSkipped);
      } catch (error) {
        debugPrint('Folder image processing failed: ${error.runtimeType}');
        // One unreadable or corrupt file must not abort the whole scan.
        firstError ??= error;
        imagesSkipped += 1;
        skippedNames.add(entry.relativePath);
        onProgress?.call(imagesScanned + imagesSkipped);
      }
    }

    var nextIndex = 0;
    Future<void> worker() async {
      while (true) {
        if (shouldCancel?.call() ?? false) throw const ScanCancelled();
        final index = nextIndex++;
        if (index >= pending.length) return;
        await processOne(pending[index]);
      }
    }

    await Future.wait([
      for (var i = 0; i < math.max(1, concurrency); i++) worker(),
    ]);
    // Workers finish in any order; keep results stable.
    images.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    skippedNames.sort();

    // If nothing could be read because of errors (for example the folder
    // permission was revoked), surface the failure instead of an empty result.
    final scanError = firstError;
    if (imagesScanned == 0 && scanError != null) throw scanError;

    final duplicates = <FolderDuplicateGroup>[];
    if (bestShotsScan) {
      duplicates.addAll(
        _groupSimilarShots(
          images,
          thresholds ?? this.thresholds,
          documentMode,
        ),
      );
      duplicates.sort((a, b) {
        final byDate = _newestModified(b).compareTo(_newestModified(a));
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
    } else {
      final exactGroups = <String, List<FolderScanPhoto>>{};
      for (final photo in images) {
        exactGroups.putIfAbsent(photo.sha256!, () => []).add(photo);
      }
      duplicates.addAll(
        exactGroups.entries
            .where((entry) => entry.value.length > 1)
            .map(
              (entry) =>
                  FolderDuplicateGroup(id: entry.key, photos: entry.value),
            ),
      );
      // Newest photos first.
      duplicates.sort((a, b) {
        final byDate = _newestModified(b).compareTo(_newestModified(a));
        return byDate != 0
            ? byDate
            : a.original.relativePath.compareTo(b.original.relativePath);
      });

      final groupsWithPreviews = <FolderDuplicateGroup>[];
      for (final group in duplicates) {
        final photosWithPreviews = <FolderScanPhoto>[];
        for (final photo in group.photos) {
          photosWithPreviews.add(
            photo.withPreviewBytes(await _previewFor(photo.uri)),
          );
        }
        groupsWithPreviews.add(
          FolderDuplicateGroup(
            id: group.id,
            photos: photosWithPreviews,
          ),
        );
      }
      duplicates
        ..clear()
        ..addAll(groupsWithPreviews);
    }

    return FolderScanResult(
      folderUri: folderUri,
      folderName: folderName,
      imagesScanned: imagesScanned,
      duplicateGroups: List.unmodifiable(duplicates),
      bestShotsScan: bestShotsScan,
      dateRange: dateRange,
      rangeStart: lower,
      rangeEnd: shownEnd,
      imagesSkipped: imagesSkipped,
      imageFilesFound: imageFilesFound,
      imagesOutsideDateRange: imagesOutsideDateRange,
      scannedPhotos: List.unmodifiable(images),
      skippedNames: List.unmodifiable(skippedNames),
      documentsLeftOut: bestShotsScan && documentMode == DocumentMode.leaveOut
          ? images.where((photo) => photo.isDocumentLike).length
          : 0,
    );
  }

  /// A preview of one file, for screens that show photos the scan did not
  /// keep a preview for. Null when the file cannot be read or decoded.
  Future<Uint8List?> loadPreview(String uri) => _previewFor(uri);

  Future<void> deleteFile(String uri) async {
    if ((await deleteFiles([uri])).isEmpty) {
      throw const FormatException('The photo could not be deleted.');
    }
  }

  /// Deletes [uris] and returns the ones that were deleted. Media-library
  /// photos go in one request, so Android asks for a single confirmation.
  Future<Set<String>> deleteFiles(List<String> uris) async {
    final deleted = <String>{};
    final media = {
      for (final uri in uris)
        if (uri.startsWith(mediaPrefix)) uri,
    };
    if (media.isNotEmpty) {
      try {
        final done = await PhotoManager.editor.deleteWithIds([
          for (final uri in media) uri.substring(mediaPrefix.length),
        ]);
        deleted.addAll(done.map((id) => '$mediaPrefix$id'));
      } catch (error) {
        debugPrint('Media delete failed: ${error.runtimeType}');
      }
    }
    for (final uri in uris) {
      if (media.contains(uri)) continue;
      try {
        await _saf.delete(uri);
        deleted.add(uri);
      } catch (_) {
        // Left out of the result; the caller reports it as not deleted.
      }
    }
    return deleted;
  }

  Future<Uint8List?> _previewFor(String uri) async {
    try {
      final bytes = await _readAll(uri);
      final preview = await Isolate.run(() {
        final decoded = decodeAnalysisImage(bytes);
        return decoded == null
            ? null
            : encodePreview(decoded, edge: 480, quality: 82);
      });
      if (preview != null) return preview;
    } catch (error) {
      debugPrint('Folder preview decode failed: $error');
    }
    // The Dart decoder could not read it (or it was too big); Android's own
    // decoder usually can, for photos in the media library.
    return _libraryThumbnail(uri, 480);
  }

  /// A thumbnail made by Android for a media-library photo, or null.
  Future<Uint8List?> _libraryThumbnail(String uri, int edge) async {
    if (!uri.startsWith(mediaPrefix)) return null;
    try {
      final asset = await AssetEntity.fromId(uri.substring(mediaPrefix.length));
      return await asset?.thumbnailDataWithSize(ThumbnailSize(edge, edge));
    } catch (error) {
      debugPrint('Library thumbnail unavailable: $error');
      return null;
    }
  }

  /// A sharper picture for the full-screen viewer: the original decoded down
  /// to about 2048 px on its longest side. Null when it cannot be read.
  Future<Uint8List?> loadLargePreview(String uri) async {
    try {
      final bytes = await _readAll(uri);
      final large = await _largePreviewInIsolate(bytes);
      if (large != null) return large;
    } catch (error) {
      debugPrint('Large preview decode failed: $error');
    }
    return _libraryThumbnail(uri, 1600);
  }

  /// Copies the original files of [photos] into a temporary folder so they
  /// can be handed to Android's share sheet (WhatsApp status, Instagram,
  /// Facebook and so on). Photos that cannot be read are skipped. The photos
  /// themselves are never changed or deleted.
  Future<List<String>> prepareForSharing(List<FolderScanPhoto> photos) async {
    final root = await getTemporaryDirectory();
    final folder = Directory(p.join(root.path, 'pictoiq_share'));
    try {
      if (await folder.exists()) await folder.delete(recursive: true);
    } catch (error) {
      debugPrint('Could not clear the share folder: $error');
    }
    await folder.create(recursive: true);
    final paths = <String>[];
    for (var i = 0; i < photos.length; i++) {
      try {
        final bytes = await _readAll(photos[i].uri);
        final name = photos[i].name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final file = File(p.join(folder.path, '${i + 1}_$name'));
        await file.writeAsBytes(bytes, flush: true);
        paths.add(file.path);
      } catch (error) {
        debugPrint('Could not prepare ${photos[i].name} for sharing: $error');
      }
    }
    return paths;
  }

  Future<void> dispose() => _faceDetector.close();

  /// Runs face detection on one analysis image. Returns null when detection
  /// fails, so the ranking treats that photo's faces as unknown rather than
  /// absent and ignores face signals for its group.
  Future<FaceSignals?> _detectFaces(
    Uint8List rgba,
    int width,
    int height,
  ) async {
    try {
      // Pixels go straight to the detector. Passing a temporary image file
      // failed on a real phone with a null-pointer error inside Android.
      final faces = await _faceDetector.processImage(
        InputImage.fromBitmap(bitmap: rgba, width: width, height: height),
      );
      if (faces.isEmpty) return FaceSignals.none;
      double? eyesOpenMin;
      var smileTotal = 0.0;
      var smileCount = 0;
      var edgeCutoff = false;
      double? lookingAwayMax;
      final size = (width, height);
      for (final face in faces) {
        // A face this close to the border is probably cut off.
        final box = face.boundingBox;
        final marginX = size.$1 * 0.01;
        final marginY = size.$2 * 0.01;
        if (box.left < marginX ||
            box.top < marginY ||
            box.right > size.$1 - marginX ||
            box.bottom > size.$2 - marginY) {
          edgeCutoff = true;
        }
        final yaw = face.headEulerAngleY;
        if (yaw != null) {
          final turn = yaw.abs();
          lookingAwayMax = lookingAwayMax == null
              ? turn
              : math.max(lookingAwayMax, turn);
        }
        final eyes = [
          face.leftEyeOpenProbability,
          face.rightEyeOpenProbability,
        ].whereType<double>();
        for (final eye in eyes) {
          eyesOpenMin = eyesOpenMin == null ? eye : math.min(eyesOpenMin, eye);
        }
        final smile = face.smilingProbability;
        if (smile != null) {
          smileTotal += smile;
          smileCount++;
        }
      }
      // Colours below each of the four largest faces, a rough way to tell
      // differently dressed people apart. Starts under the chin to skip skin.
      // Colours that also fill the rest of the picture (rocks, grass, sky) are
      // subtracted, so the same place cannot make two outfits look alike.
      final bySize = [...faces]
        ..sort(
          (a, b) => (b.boundingBox.width * b.boundingBox.height).compareTo(
            a.boundingBox.width * a.boundingBox.height,
          ),
        );
      final whole = regionHistogram(rgba, width, height, 0, 0, width, height);
      final personColors = <List<double>>[];
      for (final face in bySize.take(4)) {
        final box = face.boundingBox;
        final colors = regionHistogram(
          rgba,
          width,
          height,
          (box.center.dx - box.width * 0.6).round(),
          box.bottom.round(),
          (box.center.dx + box.width * 0.6).round(),
          (box.bottom + box.height * 1.6).round(),
        );
        if (colors == null) continue;
        final outfit = whole == null
            ? colors
            : distinctiveColors(colors, whole);
        if (outfit != null) personColors.add(outfit);
      }
      return FaceSignals(
        count: faces.length,
        subjectColors: personColors.isEmpty ? null : personColors.first,
        personColors: personColors.isEmpty ? null : personColors,
        eyesOpenMin: eyesOpenMin,
        smileAverage: smileCount == 0 ? null : smileTotal / smileCount,
        edgeCutoff: edgeCutoff,
        lookingAwayMax: lookingAwayMax,
      );
    } on PlatformException catch (error) {
      // Keep the detail: the type alone cannot tell a missing model from a
      // bad input image.
      debugPrint(
        'Face signals unavailable: PlatformException '
        'code=${error.code} message=${error.message} details=${error.details}',
      );
      return null;
    } catch (error) {
      debugPrint('Face signals unavailable: ${error.runtimeType} $error');
      return null;
    }
  }

  static _ShotAnalysis? _analyzeShot(
    Uint8List bytes,
    int modifiedAt,
    String fileName,
    bool includeFaceImage,
  ) {
    final decoded = decodeAnalysisImage(bytes);
    if (decoded == null) return null;
    final (width, height) =
        readImageSize(bytes) ?? (decoded.width, decoded.height);
    Uint8List? faceBitmap;
    if (includeFaceImage) {
      final rgba = decoded
          .convert(format: img.Format.uint8, numChannels: 4)
          .getBytes(order: img.ChannelOrder.rgba);
      // The detector needs exactly width x height x 4 bytes.
      if (rgba.length == decoded.width * decoded.height * 4) faceBitmap = rgba;
    }
    final isDocument = looksLikeDocument(decoded);
    return _ShotAnalysis(
      visualHash: differenceHash(decoded),
      captureTime: captureTimeOf(decoded, modifiedAt, fileName: fileName),
      signals: measureImage(decoded),
      megapixels: width * height / 1000000,
      preview: encodePreview(decoded),
      faceBitmap: faceBitmap,
      faceWidth: decoded.width,
      faceHeight: decoded.height,
      colorHistogram: colorHistogram(decoded),
      colorLayout: colorLayout(decoded),
      isDocument: isDocument,
      documentDetail: isDocument ? documentDetail(decoded) : null,
    );
  }

  /// Groups visually similar photos, rates how sure each group is, and ranks
  /// the photos inside it.
  List<FolderDuplicateGroup> _groupSimilarShots(
    List<FolderScanPhoto> allImages,
    SimilarityThresholds thresholds,
    DocumentMode documentMode,
  ) {
    final images = [
      for (final photo in allImages)
        if (documentMode == DocumentMode.strict || !photo.isDocumentLike) photo,
    ];
    final clusters = clusterSimilar(
      [
        for (final photo in images)
          SimilarityCandidate(
            visualHash: photo.visualHash,
            capturedAt: photo.capturedAt,
            captureSource: photo.captureSource,
            tieBreaker: photo.relativePath,
            colorHistogram: photo.colorHistogram,
            colorLayout: photo.colorLayout,
            faceCount: photo.features?.faces?.count,
            subjectColors: photo.features?.faces?.subjectColors,
            personColors: photo.features?.faces?.personColors,
            isDocument: photo.isDocumentLike,
            documentDetail: photo.documentDetail,
          ),
      ],
      thresholds: thresholds,
    );
    return [
      for (final cluster in clusters)
        _rankedGroup([
          for (final index in cluster.members) images[index],
        ], cluster.evidence),
    ];
  }

  FolderDuplicateGroup _rankedGroup(
    List<FolderScanPhoto> members,
    SimilarityEvidence evidence,
  ) => rankedGroup(members, evidence);

  bool _isImage(String name, String? mimeType) {
    if (mimeType?.toLowerCase().startsWith('image/') ?? false) return true;
    return _imageExtensions.contains(p.extension(name).toLowerCase());
  }

  bool _isSystemThumbnail(String relativePath) => p
      .split(relativePath)
      .any((segment) => segment.toLowerCase() == '.thumbnails');
}

/// Ranks [members] against each other and builds the group, copying each
/// photo's group-relative score and reasons onto it.
FolderDuplicateGroup rankedGroup(
  List<FolderScanPhoto> members,
  SimilarityEvidence evidence, {
  String? id,
}) {
  final ranking = rankShots([
    for (final photo in members)
      ShotInput(
        id: photo.uri,
        features: photo.features ?? ShotFeatures.unknown,
        tieBreaker: photo.relativePath,
      ),
  ]);
  final ranked = <FolderScanPhoto>[];
  for (final photo in members) {
    final shot = ranking.shotFor(photo.uri)!;
    ranked.add(
      photo.withQuality(
        score: shot.score,
        notes: [...shot.strengths, ...shot.concerns],
      ),
    );
  }
  return FolderDuplicateGroup(
    id: id ?? members.first.uri,
    photos: ranked,
    evidence: evidence,
    ranking: ranking,
  );
}
