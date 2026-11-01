import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart' show PhotoManager;

import 'album_picker_page.dart';
import 'app_settings.dart';
import 'event_grouping.dart';
import 'folder_duplicate_scanner.dart';
import 'library_store.dart';
import 'photo_asset.dart';
import 'scanned_files_page.dart';
import 'selection_policy.dart';
import 'shot_ranking.dart' show RankedShot;
import 'similarity_grouping.dart';

const _ink = Color(0xFF282B25);
const _green = Color(0xFF54744C);
const _canvas = Color(0xFFF7F8F4);

enum _PhotoSort { recent, name, largest }

void main() => runApp(const PictoIqApp());

class PictoIqApp extends StatelessWidget {
  const PictoIqApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PictoIQ',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: _canvas,
      colorScheme: ColorScheme.fromSeed(seedColor: _green),
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: _ink,
        displayColor: _ink,
      ),
    ),
    home: const LibraryPage(),
  );
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _picker = ImagePicker();
  final _folderScanner = FolderDuplicateScanner();
  final _settingsStore = SettingsStore();
  final _searchController = TextEditingController();
  final _folderSelectionKey = GlobalKey();
  final Map<String, int> _photoRatings = {};

  /// Space and photos freed by deletions since the last scan started.
  int _freedBytes = 0;
  int _freedPhotos = 0;
  AppSettings _settings = const AppSettings();
  List<PhotoAsset> _photos = [];
  FolderSelection? _selectedFolder;
  FolderDateRange _folderDateRange = FolderDateRange.currentFolder;

  /// The from and to dates picked for [FolderDateRange.custom].
  DateTimeRange? _customRange;

  /// Photos the running scan will analyse (known once the folder is listed).
  int? _folderImagesTotal;

  /// Photos found, and files looked at, so far while the folder is listed.
  int _folderImagesFound = 0;
  int _folderFilesChecked = 0;

  /// How many files each folder had last time it was listed, so a rescan can
  /// show a real percentage for the listing step.
  final Map<String, int> _expectedFiles = {};

  /// How long listing each folder took last time (seconds), for an estimate.
  final Map<String, int> _listingSeconds = {};

  /// When the running scan started, and a timer that redraws the elapsed
  /// time while the folder is being read.
  DateTime? _scanStartedAt;
  Timer? _elapsedTimer;
  FolderScanResult? _folderScan;
  FolderScanResult? _bestShotsScan;
  bool _loading = true;
  bool _importing = false;
  bool _scanningFolder = false;
  bool _scanningBestShots = false;
  bool _duplicatesOnly = false;
  _PhotoSort _sort = _PhotoSort.recent;
  final int _tab = 0;
  bool _setupExpanded = true;
  bool _showBestResults = true;
  bool _scanActive = false;
  bool _cancelRequested = false;
  int _folderImagesScanned = 0;
  String? _error;
  String? _folderScanError;
  String? _bestShotsError;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsStore.load();
    if (mounted) setState(() => _settings = settings);
  }

  /// Applies [settings] at once and saves them in the background.
  Future<void> _updateSettings(AppSettings settings) async {
    setState(() => _settings = settings);
    try {
      await _settingsStore.save(settings);
    } catch (_) {
      if (mounted) _showMessage('PictoIQ could not save that setting.');
    }
  }

  Future<void> _loadPhotos() async {
    try {
      final photos = await LibraryStore.instance.getPhotos();
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'PictoIQ could not open its on-device library.';
      });
    }
  }

  Future<void> _choosePhotos() async {
    if (_importing) return;
    try {
      final selected = await _picker.pickMultiImage();
      if (selected.isEmpty || !mounted) return;
      setState(() => _importing = true);

      var added = 0;
      for (final file in selected) {
        final photo = await LibraryStore.instance.importPhoto(file, added);
        if (!mounted) return;
        setState(() {
          _photos = [photo, ..._photos];
          added += 1;
        });
      }
      if (mounted) {
        _showMessage(
          'Added $added photo${added == 1 ? '' : 's'} to your private library.',
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          'PictoIQ could not import those photos. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _scanFolder() async {
    await _runFolderScan(bestShots: false);
  }

  Future<void> _scanBestShotsFolder() async {
    await _runFolderScan(bestShots: true);
  }

  Future<void> _chooseFolder() async {
    if (_scanningFolder || _importing) return;
    try {
      // Albums first (fast, like a gallery picker); "Other folder…" falls
      // back to Android's folder picker.
      final choice = await Navigator.of(context).push<Object>(
        MaterialPageRoute<Object>(
          builder: (_) => AlbumPickerPage(
            requestAccess: _folderScanner.requestMediaAccess,
            loadAlbums: _folderScanner.listAlbums,
            loadCover: _folderScanner.albumCover,
            loadThumbnails: _folderScanner.albumThumbnails,
            loadPhoto: _folderScanner.albumPhoto,
            openSettings: PhotoManager.openSetting,
          ),
        ),
      );
      if (choice == null || !mounted) return;
      final FolderSelection? selected = choice is FolderSelection
          ? choice
          : await _folderScanner.pickFolder();
      if (selected == null || !mounted) return;
      setState(() {
        _selectedFolder = selected;
        _setupExpanded = true;
        _folderScan = null;
        _bestShotsScan = null;
        _folderScanError = null;
        _bestShotsError = null;
      });
    } catch (error) {
      debugPrint('Folder picker failed: $error');
      if (mounted) {
        _showMessage(
          'PictoIQ could not open the folder picker (${error.runtimeType}). Try again.',
        );
      }
    }
  }

  Future<void> _runFolderScan({required bool bestShots}) async {
    final selectedFolder = _selectedFolder;
    if (!Platform.isAndroid ||
        selectedFolder == null ||
        _scanningFolder ||
        _importing) {
      return;
    }
    setState(() {
      _scanningFolder = true;
      _scanningBestShots = bestShots;
      _scanActive = true;
      _cancelRequested = false;
      _showBestResults = bestShots;
      _folderImagesScanned = 0;
      _folderImagesTotal = null;
      _folderImagesFound = 0;
      _folderFilesChecked = 0;
      _scanStartedAt = DateTime.now();
      _freedBytes = 0;
      _freedPhotos = 0;
      if (bestShots) {
        _bestShotsError = null;
      } else {
        _folderScanError = null;
      }
    });
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_scanActive || _folderImagesTotal != null) {
        timer.cancel();
      } else {
        setState(() {});
      }
    });
    try {
      final result = await _folderScanner.scanUri(
        selectedFolder.uri,
        folderName: selectedFolder.name,
        bestShotsScan: bestShots,
        useFaceSignals: _settings.useFaceSignals,
        thresholds: SimilarityThresholds.forLevel(
          _settings.matchLevel,
          splitByPeople: _settings.splitByPeople,
          timeMode: _settings.timeMode,
        ),
        documentMode: _settings.documentMode,
        dateRange: _folderDateRange,
        rangeFrom: _customRange?.start,
        rangeTo: _customRange?.end,
        onListed: (found, checked) {
          if (mounted) {
            setState(() {
              _folderImagesFound = found;
              _folderFilesChecked = checked;
            });
          }
        },
        onTotal: (total) {
          _expectedFiles[selectedFolder.uri] = _folderFilesChecked;
          final started = _scanStartedAt;
          if (started != null) {
            _listingSeconds[selectedFolder.uri] = DateTime.now()
                .difference(started)
                .inSeconds;
          }
          if (mounted) setState(() => _folderImagesTotal = total);
        },
        onProgress: (count) {
          if (mounted) setState(() => _folderImagesScanned = count);
        },
        shouldCancel: () => _cancelRequested,
      );
      if (!mounted) return;
      setState(() {
        _setupExpanded = false;
        if (bestShots) {
          _bestShotsScan = result;
        } else {
          _folderScan = result;
        }
      });
      _scrollToFolderSelection();
      _showMessage(
        result.duplicateGroups.isEmpty
            ? _noGroupsText(result, bestShots: bestShots)
            : bestShots
            ? 'Found ${result.duplicateGroups.length} similar-photo groups in ${result.folderName}. They are similar, not identical, so review them before deleting.${_skippedNote(result.imagesSkipped)}${_documentNote(result)}'
            : 'Found ${result.duplicateGroups.length} exact duplicate groups in ${result.folderName}.${_skippedNote(result.imagesSkipped)}',
      );
    } on ScanCancelled {
      if (mounted) _showMessage('Scan cancelled. Nothing was changed.');
    } catch (error) {
      if (mounted) {
        setState(() {
          final message =
              'PictoIQ could not scan that folder. Choose another folder and try again.';
          if (bestShots) {
            _bestShotsError = message;
          } else {
            _folderScanError = message;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _scanningFolder = false;
          _scanningBestShots = false;
          _scanActive = false;
        });
      }
    }
  }

  void _cancelScan() {
    if (_scanActive) setState(() => _cancelRequested = true);
  }

  void _scrollToFolderSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _folderSelectionKey.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _setPhotoRating(String key, int rating) {
    setState(() {
      _photoRatings[key] = _photoRatings[key] == rating ? 0 : rating;
    });
  }

  int _photoRating(String key) => _photoRatings[key] ?? 0;

  Set<String> get _likedIds => {
    for (final entry in _photoRatings.entries)
      if (entry.value > 0) entry.key,
  };

  Set<String> get _dislikedIds => {
    for (final entry in _photoRatings.entries)
      if (entry.value < 0) entry.key,
  };

  /// Which photos of [group] to keep. See [decideKeepers] for the rules; in
  /// short, every thumbs-up photo is kept, otherwise the top-ranked photo that
  /// was not thumbed down, and nothing at all when the user prefers to choose.
  KeepDecision _decisionFor(
    FolderDuplicateGroup group, {
    required bool bestShots,
  }) {
    if (!bestShots) {
      // Exact copies are identical, so keeping the oldest is always safe.
      return decideKeepers(
        rankedIds: [for (final photo in group.oldestFirst) photo.uri],
        liked: _likedIds,
        disliked: _dislikedIds,
        manualOnly: false,
        confident: true,
      );
    }
    final confident =
        group.evidence?.confidence == SimilarityConfidence.high &&
        (group.ranking?.isClearWinner ?? false);
    return decideKeepers(
      rankedIds: [for (final photo in group.bestFirst) photo.uri],
      liked: _likedIds,
      disliked: _dislikedIds,
      manualOnly: _settings.manualSelectionOnly,
      confident: confident,
    );
  }

  List<FolderScanPhoto> _groupKeepers(
    FolderDuplicateGroup group, {
    required bool bestShots,
  }) {
    final keepIds = _decisionFor(group, bestShots: bestShots).keepIds;
    return group.photos.where((photo) => keepIds.contains(photo.uri)).toList();
  }

  List<FolderScanPhoto> _groupRemovals(
    FolderDuplicateGroup group, {
    required bool bestShots,
  }) {
    final decision = _decisionFor(group, bestShots: bestShots);
    final remove = decision
        .removals([for (final photo in group.photos) photo.uri])
        .toSet();
    return group.photos.where((photo) => remove.contains(photo.uri)).toList();
  }

  /// Whether a bulk action may act on [group] without a person looking at it:
  /// exact copies always, similar shots only when the user chose the keepers
  /// or the grouping and the ranking are both clear.
  bool _isBulkSafe(FolderDuplicateGroup group, {required bool bestShots}) {
    final decision = _decisionFor(group, bestShots: bestShots);
    return decision.hasDecision && !decision.needsReview;
  }

  List<FolderDuplicateGroup> _bulkGroups(
    FolderScanResult scan, {
    required bool bestShots,
  }) => scan.duplicateGroups
      .where((group) => _isBulkSafe(group, bestShots: bestShots))
      .toList(growable: false);

  /// Groups a bulk action will leave alone because a person should look first.
  int _groupsNeedingReview(FolderScanResult scan, {required bool bestShots}) =>
      scan.duplicateGroups.length -
      _bulkGroups(scan, bestShots: bestShots).length;

  /// Photos that would go if every group kept only one photo: the user's
  /// pick when there is one, otherwise the top pick (or oldest exact copy).
  /// Unlike [_scanRemovals] it includes groups that need review.
  List<FolderScanPhoto> _potentialRemovals(
    FolderScanResult scan, {
    required bool bestShots,
  }) => [
    for (final group in scan.duplicateGroups)
      ..._withoutKeeper(group, bestShots: bestShots),
  ];

  List<FolderScanPhoto> _withoutKeeper(
    FolderDuplicateGroup group, {
    required bool bestShots,
  }) {
    final decision = _decisionFor(group, bestShots: bestShots);
    final keep = decision.hasDecision
        ? decision.keepIds
        : {bestShots ? group.recommended.uri : group.oldestFirst.first.uri};
    return [
      for (final photo in group.photos)
        if (!keep.contains(photo.uri)) photo,
    ];
  }

  List<FolderScanPhoto> _scanRemovals(
    FolderScanResult scan, {
    required bool bestShots,
  }) => _bulkGroups(
    scan,
    bestShots: bestShots,
  ).expand((group) => _groupRemovals(group, bestShots: bestShots)).toList();

  int _groupRecoveryBytes(
    FolderDuplicateGroup group, {
    required bool bestShots,
  }) => _groupRemovals(
    group,
    bestShots: bestShots,
  ).fold(0, (total, photo) => total + photo.size);

  /// One round button per photo: filled for the photo that will be kept.
  /// Choosing another photo replaces the choice, so a group keeps one photo.
  Widget _keepSelector(
    FolderDuplicateGroup group,
    FolderScanPhoto photo,
    Set<String> keepIds,
  ) {
    final selected = keepIds.contains(photo.uri);
    return IconButton(
      tooltip: selected ? 'This photo will be kept' : 'Keep this photo',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      onPressed: selected ? null : () => _chooseKeeper(group, photo.uri),
      icon: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? _green : const Color(0xFF77796F),
      ),
    );
  }

  Widget _photoRatingButtons(String key) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: 'Thumbs up: prefer this photo',
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        onPressed: () => _setPhotoRating(key, 1),
        icon: Icon(
          _photoRating(key) > 0 ? Icons.thumb_up : Icons.thumb_up_outlined,
          size: 17,
          color: _photoRating(key) > 0 ? _green : const Color(0xFF77796F),
        ),
      ),
      IconButton(
        tooltip: 'Thumbs down: avoid this photo',
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        onPressed: () => _setPhotoRating(key, -1),
        icon: Icon(
          _photoRating(key) < 0 ? Icons.thumb_down : Icons.thumb_down_outlined,
          size: 17,
          color: _photoRating(key) < 0
              ? const Color(0xFFB05F4B)
              : const Color(0xFF77796F),
        ),
      ),
    ],
  );

  Future<void> _deleteNewerCopies(FolderDuplicateGroup group) async {
    final scan = _folderScan;
    if (scan == null) return;
    final keepers = _groupKeepers(group, bestShots: false);
    final newerCopies = _groupRemovals(group, bestShots: false);
    if (keepers.isEmpty || newerCopies.isEmpty) return;
    final recoverableBytes = _groupRecoveryBytes(group, bestShots: false);
    final keptNames = keepers.map((photo) => '"${photo.relativePath}"').join(', ');
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keep your preferred copy?'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'PictoIQ will keep $keptNames and delete the other identical copies listed below. Nothing is deleted until you confirm.',
                ),
                const SizedBox(height: 12),
                _recoveryEstimate(recoverableBytes),
                const SizedBox(height: 12),
                for (final photo in newerCopies)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      photo.relativePath,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 4),
                const Text(
                  'These files are exact matches. Deleting removes only the newer source copies from this folder. PictoIQ copies are not affected.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF77796F)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete ${newerCopies.length} copies'),
          ),
        ],
      ),
    );
    if (remove != true || !mounted) return;

    setState(() {
      _scanningFolder = true;
      _scanningBestShots = false;
    });
    final deleted = await _folderScanner.deleteFiles([
      for (final photo in newerCopies) photo.uri,
    ]);
    final freedBytes = newerCopies
        .where((photo) => deleted.contains(photo.uri))
        .fold<int>(0, (total, photo) => total + photo.size);
    final failedDeletes = newerCopies.length - deleted.length;
    if (mounted) {
      setState(() {
        _freedBytes += freedBytes;
        _freedPhotos += deleted.length;
        _folderScan = scan.withoutPhotos(deleted);
        _scanningFolder = false;
        _scanningBestShots = false;
      });
      _showMessage(
        failedDeletes == 0
            ? 'Freed about ${_formatBytes(freedBytes)}; kept ${_keptSummary(keepers)}.'
            : 'Freed about ${_formatBytes(freedBytes)}. $failedDeletes copies could not be deleted.',
      );
    }
  }

  Future<void> _deleteSimilarShots(FolderDuplicateGroup group) async {
    final scan = _bestShotsScan;
    if (scan == null) return;
    final decision = _decisionFor(group, bestShots: true);
    if (!decision.hasDecision) {
      _showMessage('Choose the photo you want to keep first.');
      return;
    }
    final keepers = _groupKeepers(group, bestShots: true);
    final remove = _groupRemovals(group, bestShots: true);
    if (remove.isEmpty) return;
    final recoverableBytes = _groupRecoveryBytes(group, bestShots: true);
    final warning = decision.needsReview ? _reviewReason(group) : null;
    var reviewed = warning == null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            decision.isUserChoice
                ? 'Keep your chosen photo?'
                : 'Keep the suggested photo?',
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'These are similar shots, not identical duplicates. Keeping:',
                ),
                const SizedBox(height: 4),
                for (final photo in keepers)
                  Text(
                    '✓ ${photo.relativePath}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                const SizedBox(height: 10),
                Text('Deleting from "${scan.folderName}":'),
                const SizedBox(height: 4),
                for (final photo in remove)
                  Text('• ${photo.relativePath} · ${_shotSummary(group, photo)}'),
                const SizedBox(height: 10),
                _recoveryEstimate(recoverableBytes),
                if (warning != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4E0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      warning,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF7A5200),
                      ),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    value: reviewed,
                    onChanged: (value) =>
                        setDialogState(() => reviewed = value ?? false),
                    title: const Text(
                      'I have looked at these photos',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                const Text(
                  'PictoIQ waits for your confirmation before deleting source files.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF77796F)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              onPressed: reviewed
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: Text(
                'Delete ${remove.length} photo${remove.length == 1 ? '' : 's'}',
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _scanningFolder = true;
      _scanningBestShots = true;
    });
    final deleted = await _folderScanner.deleteFiles([
      for (final photo in remove) photo.uri,
    ]);
    final freedBytes = remove
        .where((photo) => deleted.contains(photo.uri))
        .fold<int>(0, (total, photo) => total + photo.size);
    final failedDeletes = remove.length - deleted.length;
    if (mounted) {
      setState(() {
        _freedBytes += freedBytes;
        _freedPhotos += deleted.length;
        _bestShotsScan = scan.withoutPhotos(deleted);
        _scanningFolder = false;
        _scanningBestShots = false;
      });
      _showMessage(
        failedDeletes == 0
            ? 'Freed about ${_formatBytes(freedBytes)}; kept ${_keptSummary(keepers)}.'
            : 'Freed about ${_formatBytes(freedBytes)}. $failedDeletes photos could not be deleted.',
      );
    }
  }

  /// "Trust PictoIQ": choose how far automatic cleanup may go, then reuse the
  /// normal confirmation that lists the files before anything is deleted.
  Future<void> _showAutoClean(FolderScanResult scan) async {
    final confident = _scanRemovals(scan, bestShots: true);
    final everything = _potentialRemovals(scan, bestShots: true);
    final confidentBytes = confident.fold<int>(0, (t, p) => t + p.size);
    final everythingBytes = everything.fold<int>(0, (t, p) => t + p.size);
    final canDoAll = !_settings.manualSelectionOnly && everything.isNotEmpty;
    var scope = confident.isNotEmpty ? 0 : 1;
    var acknowledged = false;
    final choice = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final allSelected = scope == 1;
          final canContinue =
              (scope == 0 && confident.isNotEmpty) ||
              (allSelected && canDoAll && acknowledged);
          return AlertDialog(
            title: const Text('Let PictoIQ clean up'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'PictoIQ keeps your picks, or its top pick in each group, and deletes the rest. You will see the list before anything is deleted.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    enabled: confident.isNotEmpty,
                    leading: Icon(
                      scope == 0
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    onTap: confident.isEmpty
                        ? null
                        : () => setDialogState(() => scope = 0),
                    title: const Text('Confident groups only'),
                    subtitle: Text(
                      confident.isEmpty
                          ? 'No group is clear enough yet.'
                          : '${confident.length} photos · ${_formatBytes(confidentBytes)}. Safest; groups needing a look are left alone.',
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    enabled: canDoAll,
                    leading: Icon(
                      scope == 1
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    onTap: canDoAll
                        ? () => setDialogState(() => scope = 1)
                        : null,
                    title: const Text('Every group'),
                    subtitle: Text(
                      _settings.manualSelectionOnly
                          ? 'Unavailable while "choose myself" is on.'
                          : '${everything.length} photos · ${_formatBytes(everythingBytes)}. Includes groups PictoIQ is unsure about.',
                    ),
                  ),
                  if (allSelected && canDoAll)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: acknowledged,
                      onChanged: (value) =>
                          setDialogState(() => acknowledged = value ?? false),
                      title: const Text(
                        'I understand some top picks may be wrong.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: canContinue
                    ? () => Navigator.pop(dialogContext, scope)
                    : null,
                child: const Text('Continue'),
              ),
            ],
          );
        },
      ),
    );
    if (choice == null || !mounted) return;
    await _deleteAllScanRemovables(
      bestShots: true,
      includeUncertain: choice == 1,
    );
  }

  Future<void> _deleteAllScanRemovables({
    required bool bestShots,
    bool includeUncertain = false,
  }) async {
    final scan = bestShots ? _bestShotsScan : _folderScan;
    if (scan == null || _scanningFolder) return;
    final remove = includeUncertain
        ? _potentialRemovals(scan, bestShots: bestShots)
        : _scanRemovals(scan, bestShots: bestShots);
    if (remove.isEmpty) return;
    final bytes = remove.fold<int>(0, (total, photo) => total + photo.size);
    final category = bestShots
        ? 'lower-ranked similar shots'
        : 'exact duplicate copies';
    final keepDescription = bestShots
        ? (includeUncertain
              ? 'PictoIQ will keep your picks, or its top-ranked photo in every group, including groups it is unsure about.'
              : 'PictoIQ will keep your picks, or the top-ranked photo in each group where the match and the ranking are both clear.')
        : 'PictoIQ will keep your picks, or the oldest copy in each group.';
    final skippedGroups = includeUncertain
        ? 0
        : _groupsNeedingReview(scan, bestShots: bestShots);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete all $category?'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Delete ${remove.length} photos from "${scan.folderName}"? $keepDescription',
                ),
                if (skippedGroups > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '$skippedGroups group${skippedGroups == 1 ? '' : 's'} that need${skippedGroups == 1 ? 's' : ''} your review will be left alone.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7A5200),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _recoveryEstimate(bytes),
                const SizedBox(height: 12),
                for (final photo in remove.take(10))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      photo.relativePath,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                if (remove.length > 10)
                  Text(
                    'and ${remove.length - 10} more…',
                    style: const TextStyle(fontSize: 12),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'This deletes source files in the selected folder. Review the list before continuing.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF77796F)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Delete ${remove.length} photos'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _scanningFolder = true;
      _scanningBestShots = bestShots;
      _folderImagesScanned = 0;
    });
    final deleted = await _folderScanner.deleteFiles([
      for (final photo in remove) photo.uri,
    ]);
    final freedBytes = remove
        .where((photo) => deleted.contains(photo.uri))
        .fold<int>(0, (total, photo) => total + photo.size);
    final failedDeletes = remove.length - deleted.length;
    if (mounted) {
      setState(() {
        _freedBytes += freedBytes;
        _freedPhotos += deleted.length;
        if (bestShots) {
          _bestShotsScan = scan.withoutPhotos(deleted);
        } else {
          _folderScan = scan.withoutPhotos(deleted);
        }
        _scanningFolder = false;
        _scanningBestShots = false;
      });
      _showMessage(
        failedDeletes == 0
            ? 'Freed about ${_formatBytes(freedBytes)}.'
            : 'Freed ${_formatBytes(freedBytes)}. $failedDeletes photos could not be deleted.',
      );
    }
  }

  Future<void> _removePhoto(PhotoAsset photo) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from PictoIQ?'),
        content: Text(
          '“${photo.name}” and PictoIQ’s private copy will be removed. The original photo stays in your gallery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove != true) return;
    try {
      await LibraryStore.instance.removePhoto(photo);
      if (!mounted) return;
      setState(() => _photos.removeWhere((item) => item.id == photo.id));
      _showMessage('Removed from PictoIQ. Your original photo is unchanged.');
    } catch (error) {
      if (mounted) _showMessage('PictoIQ could not remove that library entry.');
    }
  }

  /// Chooses the photo date range; "Custom range" asks for the from and to
  /// dates first and is only selected once both are picked.
  Future<void> _selectDateRange(FolderDateRange range) async {
    var customRange = _customRange;
    if (range == FolderDateRange.custom) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: now,
        initialDateRange: customRange,
        helpText: 'Scan photos from … to …',
        saveText: 'Use range',
      );
      if (picked == null || !mounted) return;
      customRange = picked;
    }
    setState(() {
      _folderDateRange = range;
      _customRange = customRange;
      _folderScan = null;
      _bestShotsScan = null;
      _folderScanError = null;
      _bestShotsError = null;
    });
  }

  /// Two bars: step 1 finds the photos (slides until the folder is listed,
  /// then full), step 2 analyses them from 0 to 100 %.
  Widget _scanProgressBar() {
    final total = _folderImagesTotal;
    final listed = total != null;
    // Android hands over a big folder's file list in one piece, so there is
    // no true percentage for this step. With a previous listing of the same
    // folder we estimate from its file count or how long it took.
    final folderUri = _selectedFolder?.uri;
    final expectedFiles = folderUri == null ? null : _expectedFiles[folderUri];
    final expectedSeconds = folderUri == null
        ? null
        : _listingSeconds[folderUri];
    final started = _scanStartedAt;
    final elapsed = started == null
        ? Duration.zero
        : DateTime.now().difference(started);
    double? listingFraction;
    if (expectedFiles != null && expectedFiles > 0 && _folderFilesChecked > 0) {
      listingFraction = _folderFilesChecked / expectedFiles;
    } else if (expectedSeconds != null && expectedSeconds > 0) {
      listingFraction = elapsed.inSeconds / expectedSeconds;
    }
    listingFraction = listingFraction?.clamp(0.0, 0.95);
    final clock =
        '${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    final fraction = total == null || total == 0
        ? (listed ? 1.0 : 0.0)
        : (_folderImagesScanned / total).clamp(0.0, 1.0);
    Widget step(
      String title,
      String detail,
      double? value, {
      required bool active,
      required bool done,
    }) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              done ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 16,
              color: done || active ? _green : const Color(0xFFB4B7AC),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: active || done
                      ? const Color(0xFF3B4234)
                      : const Color(0xFF8A8D83),
                ),
              ),
            ),
            Text(
              detail,
              style: const TextStyle(fontSize: 12, color: Color(0xFF596252)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            color: _green,
            backgroundColor: const Color(0xFFDDE8DC),
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          step(
            '1. Finding photos',
            listed
                ? '$total found'
                : listingFraction == null
                ? (_folderImagesFound > 0
                      ? '$_folderImagesFound found · $clock'
                      : 'Reading folder · $clock')
                : '~${(listingFraction * 100).floor()}% · $clock',
            listed ? 1.0 : listingFraction,
            active: !listed,
            done: listed,
          ),
          if (!listed && listingFraction == null && elapsed.inSeconds >= 5)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Big folders are read in one go, so a percentage is not available on the first scan. The next scan of this folder will show one.',
                style: TextStyle(fontSize: 11, color: Color(0xFF77796F)),
              ),
            ),
          const SizedBox(height: 10),
          step(
            '2. Analyzing photos',
            listed
                ? '${(fraction * 100).floor()}% · $_folderImagesScanned of $total'
                : 'waiting',
            fraction,
            active: listed,
            done: listed && fraction >= 1.0,
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Map<String, List<PhotoAsset>> get _duplicateGroups {
    final groups = <String, List<PhotoAsset>>{};
    for (final photo in _photos) {
      groups.putIfAbsent(photo.sha256, () => []).add(photo);
    }
    return Map.fromEntries(
      groups.entries.where((entry) => entry.value.length > 1),
    );
  }

  List<PhotoAsset> _visiblePhotos(Map<String, List<PhotoAsset>> groups) {
    final query = _searchController.text.trim().toLowerCase();
    final photos = _photos.where((photo) {
      final matchesQuery =
          query.isEmpty || photo.name.toLowerCase().contains(query);
      final matchesFilter =
          !_duplicatesOnly || groups.containsKey(photo.sha256);
      return matchesQuery && matchesFilter;
    }).toList();

    switch (_sort) {
      case _PhotoSort.recent:
        photos.sort((left, right) => right.id.compareTo(left.id));
        break;
      case _PhotoSort.name:
        photos.sort(
          (left, right) =>
              left.name.toLowerCase().compareTo(right.name.toLowerCase()),
        );
        break;
      case _PhotoSort.largest:
        photos.sort((left, right) => right.size.compareTo(left.size));
        break;
    }
    return photos;
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _folderScanner.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    // The Library tab is hidden for now: no bottom bar, so `_tab` stays 0.
    // Restore a NavigationBar here to bring it back.
    body: SafeArea(child: _tab == 0 ? _scanTab() : _libraryTab()),
  );

  /// Which scan results are on screen: the running scan's, otherwise the last
  /// one the user ran (or switched to).
  bool get _resultsAreBestShots =>
      _scanActive ? _scanningBestShots : _showBestResults;

  bool _hasResultsFor(bool bestShots) => bestShots
      ? (_scanActive && _scanningBestShots) ||
            _bestShotsScan != null ||
            _bestShotsError != null
      : (_scanActive && !_scanningBestShots) ||
            _folderScan != null ||
            _folderScanError != null;

  Widget _scanTab() {
    final bestShots = _resultsAreBestShots;
    final bothScans = _folderScan != null && _bestShotsScan != null;
    final compactSetup =
        Platform.isAndroid &&
        !_setupExpanded &&
        !_scanActive &&
        (_folderScan != null || _bestShotsScan != null);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverToBoxAdapter(child: _header(compact: compactSetup)),
        ),
        if (Platform.isAndroid)
          SliverPadding(
            padding: compactSetup
                ? EdgeInsets.zero
                : const EdgeInsets.fromLTRB(20, 14, 20, 12),
            sliver: SliverToBoxAdapter(
              key: _folderSelectionKey,
              child: compactSetup
                  ? const SizedBox.shrink()
                  : _folderSelection(),
            ),
          ),
        if (bothScans && !_scanActive)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            sliver: SliverToBoxAdapter(
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.auto_awesome_outlined),
                    label: Text('Best shots'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.copy_all_outlined),
                    label: Text('Exact copies'),
                  ),
                ],
                selected: {_showBestResults},
                onSelectionChanged: (value) => setState(() {
                  _showBestResults = value.first;
                          }),
              ),
            ),
          ),
        if (_hasResultsFor(bestShots))
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            sliver: SliverToBoxAdapter(
              child: _folderScanSection(bestShots: bestShots),
            ),
          ),
        if (!Platform.isAndroid)
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 12),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Folder scanning is available on Android. Use the Library tab to review photos you have added.',
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          sliver: SliverToBoxAdapter(child: _footer()),
        ),
      ],
    );
  }

  Widget _libraryTab() {
    final duplicateGroups = _duplicateGroups;
    final visiblePhotos = _visiblePhotos(duplicateGroups);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          sliver: SliverToBoxAdapter(child: _libraryHeading()),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          sliver: SliverToBoxAdapter(child: _summary(duplicateGroups.length)),
        ),
        if (!_loading)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            sliver: SliverToBoxAdapter(child: _libraryControls(duplicateGroups)),
          ),
        if (_loading)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_photos.isEmpty &&
            _searchController.text.isEmpty &&
            !_duplicatesOnly)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            sliver: SliverToBoxAdapter(child: _emptyState()),
          )
        else if (visiblePhotos.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            sliver: SliverToBoxAdapter(child: _noMatches()),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            sliver: SliverGrid.builder(
              itemCount: visiblePhotos.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.sizeOf(context).width >= 700 ? 4 : 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: .74,
              ),
              itemBuilder: (context, index) => _photoCard(
                visiblePhotos[index],
                duplicateGroups.containsKey(visiblePhotos[index].sha256),
              ),
            ),
          ),
        if (_error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          ),
      ],
    );
  }

  Widget _header({bool compact = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/brand/pictoiq-icon.png',
              width: 38,
              height: 38,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'picto',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -.7,
            ),
          ),
          const Text(
            'iq',
            style: TextStyle(
              color: _green,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -.7,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Settings',
            onPressed: _showSettings,
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: 'Privacy details',
            onPressed: _showPrivacy,
            icon: const Icon(Icons.shield_outlined),
          ),
        ],
      ),
      if (!compact) ...[
      const SizedBox(height: 16),
      const Text(
        'YOUR PERSONAL PHOTO SPACE',
        style: TextStyle(
          color: _green,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        _photos.isEmpty
            ? 'Your memories,\nin focus.'
            : 'A calmer camera roll\nstarts here.',
        style: const TextStyle(
          fontSize: 26,
          height: 1.08,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.1,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Find the best photo in a folder of look-alikes, or clear out exact copies. Everything stays on this device.',
        style: TextStyle(color: _ink.withValues(alpha: .66), height: 1.45),
      ),
      ],
    ],
  );

  Widget _folderSelection() => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: const Color(0xFFEEF3E8),
      border: Border.all(color: const Color(0xFFDDE7D4)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Scan a folder',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          _selectedFolder == null
              ? '1. Choose an album   2. Scan it   3. Review and keep your favorites'
              : 'Pick a date range, then find the best shots or exact copies.',
          style: const TextStyle(fontSize: 12, color: Color(0xFF596252)),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _scanningFolder || _importing ? null : _chooseFolder,
          icon: const Icon(Icons.folder_open_outlined),
          label: Text(_selectedFolder?.name ?? 'Choose an album or folder'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            foregroundColor: _green,
            alignment: Alignment.centerLeft,
          ),
        ),
        if (_selectedFolder == null) ...[
          const SizedBox(height: 6),
          const Text(
            'Tip: pick an album such as Camera or Screenshots. Use "Other folder…" for anything not listed.',
            style: TextStyle(fontSize: 11, color: Color(0xFF77796F)),
          ),
        ],
        const SizedBox(height: 12),
        const Text(
          'Photo date',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 2,
          children: [
            for (final range in FolderDateRange.values)
              ChoiceChip(
                avatar: range == FolderDateRange.custom
                    ? const Icon(Icons.date_range_outlined, size: 16)
                    : null,
                label: Text(
                  range == FolderDateRange.custom && _customRange != null
                      ? '${_formatDate(_customRange!.start)} – ${_formatDate(_customRange!.end)}'
                      : range.label,
                ),
                selected: _folderDateRange == range,
                onSelected: _scanningFolder
                    ? null
                    : (_) => _selectDateRange(range),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_scanActive) ...[
          // The scan buttons turn into the progress while a scan runs.
          Text(
            _scanningBestShots ? 'Finding the best shots…' : 'Finding exact duplicates…',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          _scanProgressBar(),
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: TextButton.icon(
              onPressed: _cancelRequested ? null : _cancelScan,
              icon: const Icon(Icons.close, size: 18),
              label: Text(_cancelRequested ? 'Stopping…' : 'Cancel scan'),
            ),
          ),
        ] else ...[
          FilledButton.icon(
          onPressed:
              _selectedFolder == null ||
                  _loading ||
                  _importing ||
                  _scanningFolder
              ? null
              : _scanBestShotsFolder,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Find the best shots'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            backgroundColor: _green,
            foregroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 7),
        OutlinedButton.icon(
          onPressed:
              _selectedFolder == null ||
                  _loading ||
                  _importing ||
                  _scanningFolder
              ? null
              : _scanFolder,
          icon: const Icon(Icons.copy_all_outlined),
          label: const Text('Find exact duplicates'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            foregroundColor: _green,
          ),
        ),
        ],
      ],
    ),
  );

  Widget _summary(int duplicateCount) => Row(
    children: [
      Expanded(
        child: _statCard(
          'YOUR LIBRARY',
          '${_photos.length}',
          'photos saved in PictoIQ',
          Icons.photo_outlined,
          const Color(0xFFF0EEF7),
          const Color(0xFF777092),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _duplicatesOnly = !_duplicatesOnly),
          child: _statCard(
            'LIBRARY DUPLICATES',
            '$duplicateCount',
            'in saved photos · tap to review',
            Icons.copy_all_outlined,
            const Color(0xFFFBF0E9),
            const Color(0xFFB37957),
          ),
        ),
      ),
    ],
  );

  Widget _statCard(
    String title,
    String value,
    String caption,
    IconData icon,
    Color background,
    Color foreground,
  ) => Container(
    constraints: const BoxConstraints(minHeight: 110),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFE9EAE3)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF888A81),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .6,
                ),
              ),
            ),
            Container(
              width: 27,
              height: 27,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 15, color: foreground),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
          ),
        ),
        Text(
          caption,
          style: const TextStyle(color: Color(0xFF85877F), fontSize: 11),
        ),
      ],
    ),
  );

  Widget _libraryHeading() => Row(
    children: [
      Expanded(
        child: Text(
          _duplicatesOnly ? 'Duplicates in your library' : 'Your library',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -.3,
          ),
        ),
      ),
      if (!_duplicatesOnly) ...[
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _loading || _importing || _scanningFolder
              ? null
              : _choosePhotos,
          icon: _importing
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_photo_alternate_outlined, size: 17),
          label: Text(_importing ? 'Adding…' : 'Add photos'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _green,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
        ),
      ],
    ],
  );

  Widget _libraryControls(
    Map<String, List<PhotoAsset>> duplicateGroups,
  ) => Column(
    children: [
      TextField(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search by filename',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.close, size: 18),
                ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 11),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE6E8E0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE6E8E0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _green),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: false, label: Text('All photos')),
              ButtonSegment(value: true, label: Text('Duplicates')),
            ],
            selected: {_duplicatesOnly},
            onSelectionChanged: (selection) =>
                setState(() => _duplicatesOnly = selection.first),
          ),
          const Spacer(),
          PopupMenuButton<_PhotoSort>(
            tooltip: 'Sort photos',
            initialValue: _sort,
            onSelected: (value) => setState(() => _sort = value),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _PhotoSort.recent,
                child: Text('Recently added'),
              ),
              PopupMenuItem(value: _PhotoSort.name, child: Text('Name')),
              PopupMenuItem(
                value: _PhotoSort.largest,
                child: Text('Largest file'),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sort, size: 18, color: _green),
                  const SizedBox(width: 3),
                  Text(
                    _sortLabel(_sort),
                    style: const TextStyle(
                      color: _green,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '${_visiblePhotos(duplicateGroups).length} photos · ${duplicateGroups.length} duplicate groups',
            style: const TextStyle(color: Color(0xFF85877F), fontSize: 11),
          ),
        ),
      ),
    ],
  );

  Widget _noMatches() {
    final noDuplicates = _duplicatesOnly && _duplicateGroups.isEmpty;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .65),
        border: Border.all(color: const Color(0xFFE0E4D8)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            noDuplicates ? Icons.check_circle_outline : Icons.search_off,
            size: 34,
            color: _green,
          ),
          const SizedBox(height: 10),
          Text(
            noDuplicates
                ? 'No exact duplicates found.'
                : 'No photos match that search.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            noDuplicates
                ? 'New exact matches will appear here after you add photos.'
                : 'Try another filename or clear your filters.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF81847A), fontSize: 12),
          ),
          TextButton(
            onPressed: () {
              _searchController.clear();
              setState(() => _duplicatesOnly = false);
            },
            child: const Text('Show all photos'),
          ),
        ],
      ),
    );
  }

  Widget _folderScanSection({required bool bestShots}) {
    final scan = bestShots ? _bestShotsScan : _folderScan;
    final error = bestShots ? _bestShotsError : _folderScanError;
    final scanningThisMode = _scanningFolder && _scanningBestShots == bestShots;
    final groupLabel = bestShots
        ? 'similar-photo groups'
        : 'exact duplicate groups';
    if (error != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1ED),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(error, style: const TextStyle(color: Color(0xFF8A4437))),
      );
    }
    // Progress shows on the scan button, with Cancel scan under it.
    if (scanningThisMode && scan == null) return const SizedBox.shrink();
    if (scan == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _resultsHeader(scan, bestShots: bestShots, groupLabel: groupLabel),
        if (bestShots && scan.duplicateGroups.isNotEmpty) ...[
          _reviewEntryButton(scan),
        ],
        if (scan.duplicateGroups.isNotEmpty &&
            (bestShots ||
                _scanRemovals(scan, bestShots: false).isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton.tonalIcon(
              onPressed: _scanningFolder
                  ? null
                  : bestShots
                  ? () => _showAutoClean(scan)
                  : () => _deleteAllScanRemovables(bestShots: false),
              icon: Icon(
                bestShots
                    ? Icons.auto_fix_high_outlined
                    : Icons.delete_sweep_outlined,
              ),
              label: Text(
                bestShots
                    ? 'Keep all best shots · free up to ${_formatBytes(_potentialRemovals(scan, bestShots: true).fold<int>(0, (t, p) => t + p.size))}'
                    : 'Delete all duplicates',
              ),
              style: FilledButton.styleFrom(foregroundColor: _ink),
            ),
          ),
        if (scan.duplicateGroups.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE6E8E0)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _freedBytes > 0
                    ? 'Everything in this scan has been reviewed. Tap New scan to check another folder.'
                    : bestShots
                    ? 'No similar photo groups found. PictoIQ groups visually alike shots taken close together and ranks face quality when faces are detected.'
                    : 'No exact duplicate photos found. Exact duplicates have identical file contents.',
                style: TextStyle(color: Color(0xFF77796F)),
              ),
            ),
          )
        else
          ..._resultCards(scan, bestShots: bestShots),
      ],
    );
  }

  /// The group cards. For best shots they are organised as Event > Scene:
  /// each heading is a stretch of time (a day, an outing) and the cards below
  /// are the scenes in it where similar shots were found. Events are only for
  /// browsing; cleanup decisions are still made per scene.
  List<Widget> _resultCards(FolderScanResult scan, {required bool bestShots}) {
    final groups = [
      for (final group in scan.duplicateGroups)
        group,
    ];
    if (!bestShots) return groups.map(_exactDuplicateCard).toList();
    final photos = scan.scannedPhotos;
    // Grouping ignores time. Headings only use times that describe the
    // picture (camera time, or a date in the file name); a file's modified
    // time just says when it was copied, so those photos are undated.
    bool trusted(FolderScanPhoto photo) =>
        photo.captureSource == CaptureSource.exif ||
        photo.captureSource == CaptureSource.day;
    final events = clusterEvents([
      for (final photo in photos)
        EventInput(
          capturedAt: trusted(photo) ? photo.capturedAt : 0,
          captureSource: trusted(photo)
              ? photo.captureSource
              : CaptureSource.unknown,
          tieBreaker: photo.relativePath,
        ),
    ]);
    final headings =
        _settings.showEvents && events.any((event) => !event.isUndated);
    final eventOfUri = <String, int>{
      for (var e = 0; e < events.length; e++)
        for (final index in events[e].members) photos[index].uri: e,
    };
    int eventOf(FolderDuplicateGroup group) {
      var best = events.length;
      for (final photo in group.photos) {
        final e = eventOfUri[photo.uri];
        if (e != null && e < best) best = e;
      }
      return best;
    }

    final byEvent = <int, List<FolderDuplicateGroup>>{};
    for (final group in groups) {
      byEvent.putIfAbsent(eventOf(group), () => []).add(group);
    }
    final order = byEvent.keys.toList()..sort();
    final hint = Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          const Icon(Icons.touch_app_outlined, size: 16, color: Color(0xFF77796F)),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'Tap a photo to enlarge it · tap its circle to keep that one',
              style: TextStyle(fontSize: 12, color: Color(0xFF77796F)),
            ),
          ),
        ],
      ),
    );
    // Within an event, groups that are safest to clean come first.
    for (final list in byEvent.values) {
      list.sort((a, b) {
        final byConfidence = (a.evidence?.confidence.index ?? 3).compareTo(
          b.evidence?.confidence.index ?? 3,
        );
        return byConfidence != 0 ? byConfidence : a.id.compareTo(b.id);
      });
    }
    return [
      if (order.isNotEmpty) hint,
      for (final key in order) ...[
        if (headings && key < events.length)
          _eventHeader(events[key], scenes: byEvent[key]!.length),
        ...byEvent[key]!.map(_folderDuplicateCard),
      ],
    ];
  }

  String _documentNote(FolderScanResult scan) => scan.documentsLeftOut == 0
      ? ''
      : ' ${scan.documentsLeftOut} document-like image${scan.documentsLeftOut == 1 ? ' was' : 's were'} left out.';

  Widget _eventHeader(PhotoEvent event, {required int scenes}) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Row(
      children: [
        const Icon(Icons.event_outlined, size: 18, color: _green),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            eventLabel(event),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          '${event.members.length} photos · $scenes scene${scenes == 1 ? '' : 's'}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF596252)),
        ),
      ],
    ),
  );

  /// One compact card for the whole scan result: folder, the space that can
  /// be freed, and what is ready now. Scan details are one tap away.
  Widget _resultsHeader(
    FolderScanResult scan, {
    required bool bestShots,
    required String groupLabel,
  }) {
    // Space freed if the top pick (or the user's pick) is kept in every
    // group, whether or not the group is confident enough to clean in bulk.
    final potential = _potentialRemovals(scan, bestShots: bestShots);
    final potentialBytes = potential.fold<int>(
      0,
      (total, photo) => total + photo.size,
    );
    final ready = _scanRemovals(scan, bestShots: bestShots);
    final readyBytes = ready.fold<int>(0, (total, photo) => total + photo.size);
    final groups = scan.duplicateGroups.length;
    final status = groups == 0
        ? (_freedBytes > 0
              ? 'All done. Nothing left to review in this scan.'
              : _noGroupsText(scan, bestShots: bestShots))
        : !bestShots
        ? 'Exact copies. Review before deleting.'
        : ready.isEmpty
        ? 'Nothing is ready for bulk cleanup. Check each group below.'
        : 'Ready now: ${ready.length} photo${ready.length == 1 ? '' : 's'} (${_formatBytes(readyBytes)}) in confident groups.';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F3E8),
        border: Border.all(color: const Color(0xFFD2E5D1)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_open_outlined, color: _green, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  scan.folderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: _scanningFolder
                    ? null
                    : () {
                        setState(() => _setupExpanded = true);
                        _scrollToFolderSelection();
                      },
                child: const Text('New scan'),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (value) {
                  if (value == 'files') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ScannedFilesPage(
                          scan: scan,
                          loadPreview: _folderScanner.loadPreview,
                        ),
                      ),
                    );
                  } else {
                    _showScanDetails(scan, bestShots: bestShots, groupLabel: groupLabel);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'files',
                    child: Text(
                      'View scanned files (${scan.imagesScanned} of ${scan.imageFilesFound})',
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'details',
                    child: Text('About this scan'),
                  ),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 26, right: 10, bottom: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.date_range_outlined,
                  size: 14,
                  color: Color(0xFF596252),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    scan.rangeDescription,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF596252),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (groups > 0)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    _formatBytes(potentialBytes),
                    style: const TextStyle(
                      color: _green,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'can be freed',
                      style: TextStyle(fontSize: 13, color: Color(0xFF596252)),
                    ),
                  ),
                  Text(
                    '$groups $groupLabel',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF596252),
                    ),
                  ),
                ],
              ),
            ),
          if (_freedBytes > 0)
            Padding(
              padding: const EdgeInsets.only(right: 10, top: 2),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: _green, size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      groups == 0
                          ? '${_formatBytes(_freedBytes)} freed'
                          : 'Freed so far: ${_formatBytes(_freedBytes)}',
                      style: TextStyle(
                        color: _green,
                        fontWeight: FontWeight.w800,
                        fontSize: groups == 0 ? 22 : 13,
                      ),
                    ),
                  ),
                  Text(
                    '$_freedPhotos photo${_freedPhotos == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF596252),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 10, top: 2),
            child: Text(
              status,
              style: const TextStyle(fontSize: 12, color: Color(0xFF596252)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showScanDetails(
    FolderScanResult scan, {
    required bool bestShots,
    required String groupLabel,
  }) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('About this scan'),
      content: SingleChildScrollView(
        child: Text(
          [
            'Scanned ${scan.imagesScanned} images · ${scan.duplicateGroups.length} $groupLabel · ${scan.rangeDescription}${_skippedNote(scan.imagesSkipped)}${_documentNote(scan)}',
            if (bestShots && scan.duplicateGroups.isNotEmpty)
              _reviewNoteText(scan),
            'Space figures assume you keep only the top pick (or your pick) in each group.',
          ].join('\n\n'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Widget _recoveryEstimate(int bytes) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFE8F3E8),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      'Estimated space to recover: up to ${_formatBytes(bytes)}',
      style: const TextStyle(fontWeight: FontWeight.w700, color: _green),
    ),
  );

  Widget _exactDuplicateCard(FolderDuplicateGroup group) {
    final keepIds = {
      for (final kept in _groupKeepers(group, bestShots: false)) kept.uri,
    };
    final recoverableBytes = _groupRecoveryBytes(group, bestShots: false);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFE6E8E0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${group.photos.length} identical photos',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            const Text(
              'Tap a thumbnail to inspect it before deleting copies.',
              style: TextStyle(fontSize: 11, color: Color(0xFF77796F)),
            ),
            const SizedBox(height: 6),
            for (final photo in group.oldestFirst)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(
                      keepIds.contains(photo.uri)
                          ? Icons.check_circle_outline
                          : Icons.copy_outlined,
                      size: 18,
                      color: keepIds.contains(photo.uri)
                          ? _green
                          : const Color(0xFFB37957),
                    ),
                    const SizedBox(width: 8),
                    _exactDuplicateThumbnail(photo),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            photo.relativePath,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${keepIds.contains(photo.uri) ? 'Keep this copy' : 'Duplicate copy'} · ${_formatDate(photo.modifiedDate)} · ${_formatBytes(photo.size)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF85877F),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _keepSelector(group, photo, keepIds),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: _scanningFolder
                    ? null
                    : () => _deleteNewerCopies(group),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(
                  'Keep selected · recover up to ${_formatBytes(recoverableBytes)}',
                ),
                style: FilledButton.styleFrom(foregroundColor: _ink),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _exactDuplicateThumbnail(FolderScanPhoto photo) {
    final preview = photo.previewBytes;
    return Tooltip(
      message: preview == null ? 'Preview unavailable' : 'Tap to enlarge',
      child: InkWell(
        onTap: () => _showExactPhotoPreview(photo),
        borderRadius: BorderRadius.circular(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 68,
            height: 68,
            child: preview == null
                ? const ColoredBox(
                    color: Color(0xFFF0F1EC),
                    child: Icon(Icons.image_not_supported_outlined),
                  )
                : Image.memory(
                    preview,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: Color(0xFFF0F1EC),
                      child: Icon(Icons.broken_image_outlined),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  /// Shows a photo large. The small scan preview appears at once and is
  /// swapped for a sharper decode of the original as soon as that is ready.
  Future<void> _showExactPhotoPreview(FolderScanPhoto photo) async {
    // Opens even without a preview: the sharper photo loads inside.
    final preview = photo.previewBytes;
    Uint8List? shown = preview;
    var loading = true;
    var started = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (!started) {
            started = true;
            _folderScanner.loadLargePreview(photo.uri).then((bytes) {
              if (!dialogContext.mounted) return;
              setDialogState(() {
                shown = bytes ?? shown;
                loading = false;
              });
            });
          }
          return Dialog(
            insetPadding: const EdgeInsets.all(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    photo.relativePath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(dialogContext).height * .78,
                    ),
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        if (shown != null)
                          InteractiveViewer(
                            minScale: 1,
                            maxScale: 6,
                            child: Image.memory(
                              shown!,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                              filterQuality: FilterQuality.high,
                            ),
                          )
                        else if (!loading)
                          const SizedBox(
                            height: 160,
                            child: Center(
                              child: Text('This photo cannot be shown.'),
                            ),
                          )
                        else
                          const SizedBox(height: 160),
                        if (loading)
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Chip(
                              avatar: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              label: Text('Loading sharper photo…'),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _confidenceChip(SimilarityEvidence evidence) {
    final (color, background) = switch (evidence.confidence) {
      SimilarityConfidence.high => (_green, const Color(0xFFE8F3E8)),
      SimilarityConfidence.medium => (
        const Color(0xFF7A5200),
        const Color(0xFFFFF4E0),
      ),
      SimilarityConfidence.low => (
        const Color(0xFF7A5200),
        const Color(0xFFFFF4E0),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        evidence.isSession
            ? 'Same session'
            : switch (evidence.confidence) {
                SimilarityConfidence.high => 'Same shot',
                SimilarityConfidence.medium => 'Similar',
                SimilarityConfidence.low => 'Check',
              },
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  String _reviewNoteText(FolderScanResult scan) {
    final review = _groupsNeedingReview(scan, bestShots: true);
    return review == 0
        ? 'Similar photos are grouped by appearance. They are not guaranteed duplicates, so check each group before deleting.'
        : '$review of ${scan.duplicateGroups.length} groups are not matched confidently enough to clean up in bulk. Open them to choose what to keep.';
  }

  Widget _folderDuplicateCard(FolderDuplicateGroup group) {
    final decision = _decisionFor(group, bestShots: true);
    final keepIds = decision.keepIds;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFE6E8E0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final count = group.photos.length;
                final columns = count >= 9 ? 5 : 4;
                const gap = 8.0;
                final width = ((constraints.maxWidth - gap * (columns - 1)) /
                        columns)
                    .floorToDouble();
                return Wrap(
                  alignment: WrapAlignment.start,
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final photo in group.bestFirst)
                      _photoTile(group, photo, keepIds, decision, width),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            _cardActions(group, decision),
          ],
        ),
          ),
          // Skip this group: nothing is deleted and it leaves the list.
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              tooltip: 'Skip this group',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
              iconSize: 18,
              color: const Color(0xFF77796F),
              onPressed: _scanningFolder ? null : () => _skipGroup(group),
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    );
  }

  /// Sets a group aside without deleting anything (the person decided to keep
  /// every photo in it). The snackbar can bring it back.
  void _skipGroup(FolderDuplicateGroup group) {
    final scan = _bestShotsScan;
    if (scan == null) return;
    final updated = scan.withoutGroup(group.id);
    setState(() => _bestShotsScan = updated);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Group skipped. Nothing was deleted.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              if (mounted && identical(_bestShotsScan, updated)) {
                setState(() => _bestShotsScan = scan);
              }
            },
          ),
        ),
      );
  }

  /// The clean-up button. In a two-photo group it sits in the free third
  /// slot beside the photos; otherwise it spans the row below them.
  /// Compare and the keep button, in one row under the photos of every group.
  Widget _cardActions(
    FolderDuplicateGroup group,
    KeepDecision decision,
  ) {
    // The match tag (Same shot / Similar / Check) is hidden for now; bring it
    // back with _confidenceChip(group.evidence!).
    final compare = FilledButton.tonalIcon(
      onPressed: () => _showCompareShots(group),
      icon: const Icon(Icons.compare_outlined, size: 18),
      label: const Text('Compare'),
      style: FilledButton.styleFrom(
        foregroundColor: _ink,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
    final Widget keep;
    if (!decision.hasDecision) {
      keep = const Text(
        'Choose the photo to keep.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: Color(0xFF77796F)),
      );
    } else {
      final word = decision.isUserChoice ? 'Keep my pick' : 'Keep best';
      final size =
          'Save ${_formatBytes(_groupRecoveryBytes(group, bestShots: true))}';
      keep = FilledButton.tonal(
        onPressed: _scanningFolder ? null : () => _deleteSimilarShots(group),
        style: FilledButton.styleFrom(
          foregroundColor: _ink,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('$word · $size', maxLines: 1),
        ),
      );
    }
    return Row(
      children: [
        compare,
        const SizedBox(width: 8),
        Expanded(child: keep),
      ],
    );
  }

  /// Every group, safest first: the order review mode
  /// steps through.
  List<FolderDuplicateGroup> _reviewQueue(FolderScanResult scan) {
    final groups = [
      for (final group in scan.duplicateGroups)
        group,
    ];
    groups.sort((a, b) {
      final byConfidence = (a.evidence?.confidence.index ?? 3).compareTo(
        b.evidence?.confidence.index ?? 3,
      );
      return byConfidence != 0 ? byConfidence : a.id.compareTo(b.id);
    });
    return groups;
  }

  Widget _reviewEntryButton(FolderScanResult scan) {
    final count = _reviewQueue(scan).length;
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: OutlinedButton.icon(
        onPressed: _scanningFolder
            ? null
            : () => _showReviewMode(_reviewQueue(scan)),
        icon: const Icon(Icons.view_carousel_outlined, size: 18),
        label: Text('Review one by one ($count)'),
        style: OutlinedButton.styleFrom(foregroundColor: _ink),
      ),
    );
  }

  /// Full-screen, one group at a time: big photos, choose the one to keep,
  /// then "Keep this" or "Skip". Nothing is deleted while reviewing; at the
  /// end the chosen groups are listed once for a single confirmation.
  Future<void> _showReviewMode(List<FolderDuplicateGroup> queue) async {
    if (queue.isEmpty) return;
    var index = 0;
    var apply = false;
    final accepted = <String>[];
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (routeContext) => StatefulBuilder(
          builder: (context, setLocal) {
            final byId = {for (final group in queue) group.id: group};
            var pendingPhotos = 0;
            var pendingBytes = 0;
            for (final id in accepted) {
              final group = byId[id];
              if (group == null) continue;
              final removals = _groupRemovals(group, bestShots: true);
              pendingPhotos += removals.length;
              pendingBytes += removals.fold<int>(
                0,
                (total, photo) => total + photo.size,
              );
            }
            final summary = pendingPhotos == 0
                ? 'Nothing selected to delete yet'
                : 'To delete: $pendingPhotos photo${pendingPhotos == 1 ? '' : 's'} · ${_formatBytes(pendingBytes)}';

            if (index >= queue.length) {
              return Scaffold(
                appBar: AppBar(
                  title: const Text('Review finished'),
                  leading: CloseButton(
                    onPressed: () => Navigator.pop(routeContext),
                  ),
                ),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          size: 56,
                          color: _green,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          summary,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Nothing is deleted until you confirm on the next screen.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF77796F),
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: pendingPhotos == 0
                              ? null
                              : () {
                                  apply = true;
                                  Navigator.pop(routeContext);
                                },
                          icon: const Icon(Icons.delete_outline),
                          label: Text(
                            'Delete $pendingPhotos photo${pendingPhotos == 1 ? '' : 's'}',
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(routeContext),
                          child: const Text('Close without deleting'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final group = queue[index];
            final decision = _decisionFor(group, bestShots: true);
            final keepIds = decision.keepIds;
            final bytes = _groupRecoveryBytes(group, bestShots: true);
            final evidence = group.evidence;
            return Scaffold(
              appBar: AppBar(
                title: Text('Review ${index + 1} of ${queue.length}'),
                leading: CloseButton(
                  onPressed: () => Navigator.pop(routeContext),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(value: index / queue.length),
                ),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            group.ranking?.headline ??
                                '${group.photos.length} similar photos',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (evidence != null) _confidenceChip(evidence),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = (constraints.maxWidth - 8) / 2;
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final photo in group.bestFirst)
                              _photoTile(
                                group,
                                photo,
                                keepIds,
                                decision,
                                width,
                                onChanged: () => setLocal(() {}),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Tap the circle to choose the photo to keep. Tap a photo to enlarge it.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF77796F)),
                    ),
                  ],
                ),
              ),
              bottomNavigationBar: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        summary,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF596252),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (index > 0)
                            TextButton(
                              onPressed: () => setLocal(() {
                                index -= 1;
                                accepted.remove(queue[index].id);
                              }),
                              child: const Text('Back'),
                            ),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => setLocal(() => index += 1),
                              child: const Text('Skip'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: decision.hasDecision
                                  ? () {
                                      if (!decision.isUserChoice) {
                                        _chooseKeeper(
                                          group,
                                          decision.keepIds.first,
                                        );
                                      }
                                      if (!accepted.contains(group.id)) {
                                        accepted.add(group.id);
                                      }
                                      setLocal(() => index += 1);
                                    }
                                  : null,
                              icon: const Icon(Icons.check, size: 18),
                              label: Text(
                                decision.hasDecision
                                    ? 'Keep this · free ${_formatBytes(bytes)}'
                                    : 'Choose a photo',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    if (apply && accepted.isNotEmpty && mounted) {
      await _deleteReviewedGroups(accepted);
    }
  }

  /// Deletes the lower-ranked photos of the groups the user reviewed, after
  /// one confirmation that lists what will go.
  Future<void> _deleteReviewedGroups(List<String> groupIds) async {
    final scan = _bestShotsScan;
    if (scan == null || _scanningFolder) return;
    final groups = [
      for (final group in scan.duplicateGroups)
        if (groupIds.contains(group.id)) group,
    ];
    final remove = [
      for (final group in groups) ..._groupRemovals(group, bestShots: true),
    ];
    if (remove.isEmpty) return;
    final bytes = remove.fold<int>(0, (total, photo) => total + photo.size);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Delete ${remove.length} photo${remove.length == 1 ? '' : 's'}?',
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'You reviewed ${groups.length} group${groups.length == 1 ? '' : 's'}. PictoIQ keeps the photo you chose in each and deletes the others from "${scan.folderName}". This cannot be undone.',
              ),
              const SizedBox(height: 10),
              _recoveryEstimate(bytes),
              const SizedBox(height: 10),
              for (final photo in remove.take(8))
                Text(
                  photo.relativePath,
                  style: const TextStyle(fontSize: 12),
                ),
              if (remove.length > 8)
                Text(
                  'and ${remove.length - 8} more…',
                  style: const TextStyle(fontSize: 12),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Delete ${remove.length}'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _scanningFolder = true;
      _scanningBestShots = true;
    });
    final deleted = await _folderScanner.deleteFiles([
      for (final photo in remove) photo.uri,
    ]);
    final freedBytes = remove
        .where((photo) => deleted.contains(photo.uri))
        .fold<int>(0, (total, photo) => total + photo.size);
    final failedDeletes = remove.length - deleted.length;
    if (mounted) {
      setState(() {
        _freedBytes += freedBytes;
        _freedPhotos += deleted.length;
        _bestShotsScan = scan.withoutPhotos(deleted);
        _scanningFolder = false;
        _scanningBestShots = false;
      });
      _showMessage(
        failedDeletes == 0
            ? 'Freed about ${_formatBytes(freedBytes)} from ${groups.length} reviewed group${groups.length == 1 ? '' : 's'}.'
            : 'Freed about ${_formatBytes(freedBytes)}. $failedDeletes photos could not be deleted.',
      );
    }
  }

  /// A thumbnail with a short badge ("Best", "Softer", "Eyes closed") and a
  /// round button that makes it the photo to keep. Tapping the picture
  /// enlarges it.
  Widget _photoTile(
    FolderDuplicateGroup group,
    FolderScanPhoto photo,
    Set<String> keepIds,
    KeepDecision decision,
    double width, {
    VoidCallback? onChanged,
  }) {
    final small = width < 120;
    final selected = keepIds.contains(photo.uri);
    final preview = photo.previewBytes;
    final badge = selected
        ? (width < 90
              ? (decision.isUserChoice ? 'MINE' : 'BEST')
              : (decision.isUserChoice ? 'YOUR PICK' : 'BEST SHOT'))
        : _shortReason(group.ranking?.shotFor(photo.uri));
    return SizedBox(
      width: width,
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: () => _showExactPhotoPreview(photo),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? _green : const Color(0xFFE6E8E0),
                    width: selected ? 3 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(selected ? 9 : 11),
                  child: preview == null
                      ? const ColoredBox(
                          color: Color(0xFFF0F1EC),
                          child: Icon(Icons.image_not_supported_outlined),
                        )
                      : Image.memory(
                          preview,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const ColoredBox(
                            color: Color(0xFFF0F1EC),
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                ),
              ),
            ),
            if (badge != null)
              Positioned(
                left: 4,
                top: 4,
                child: Container(
                  constraints: BoxConstraints(maxWidth: width - 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? _green : const Color(0xCC3A3D35),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      badge,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: small ? 10 : 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 2,
              bottom: 2,
              child: Tooltip(
                message: selected ? 'This photo will be kept' : 'Keep this photo',
                child: InkResponse(
                  onTap: selected
                      ? null
                      : () {
                          _chooseKeeper(group, photo.uri);
                          onChanged?.call();
                        },
                  radius: 24,
                  child: Padding(
                    padding: EdgeInsets.all(small ? 4 : 6),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Color(0xE6FFFFFF),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: small ? 22 : 26,
                        color: selected ? _green : const Color(0xFF77796F),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One or two words on why a photo is not the pick, for its badge.
  String? _shortReason(RankedShot? shot) {
    if (shot == null) return null;
    final reasons = [...shot.disqualifiers, ...shot.concerns];
    for (final reason in reasons) {
      final text = reason.toLowerCase();
      if (text.contains('blurry')) return 'Blur detected';
      if (text.contains('softer')) return 'Softer';
      if (text.contains('eyes closed')) return 'Eyes closed';
      if (text.contains('cut off')) return 'Cut off';
      if (text.contains('looking away')) return 'Looking away';
      if (text.contains('washed out') || text.contains('overexposed')) {
        return 'Too bright';
      }
      if (text.contains('too dark') ||
          text.contains('underexposed') ||
          text.contains('dark areas')) {
        return 'Too dark';
      }
      if (text.contains('lower resolution')) return 'Lower quality';
      if (text.contains('no face')) return 'No face';
    }
    return null;
  }

  /// Marks [uri] as the only photo to keep in [group]: a thumbs-up for it and
  /// no marks on the others, so every other photo becomes a removal candidate
  /// only after the user confirms the delete dialog.
  void _chooseKeeper(FolderDuplicateGroup group, String uri) {
    setState(() {
      for (final photo in group.photos) {
        _photoRatings[photo.uri] = photo.uri == uri ? 1 : 0;
      }
    });
  }

  /// Takes [photo] out of [group] because it is not the same scene (for
  /// example a different person in the same spot). Nothing is deleted.
  void _ungroupPhoto(FolderDuplicateGroup group, FolderScanPhoto photo) {
    final scan = _bestShotsScan;
    if (scan == null) return;
    setState(() {
      _photoRatings.remove(photo.uri);
      _bestShotsScan = scan.withoutFromGroup(group.id, photo.uri);
    });
    _showMessage(
      '${photo.relativePath} is no longer in this group. Nothing was deleted.',
    );
  }

  String _percent(double value) => '${(value * 100).round()}%';

  /// Side-by-side view of every photo in a similar-photo group, with the
  /// measurements and reasons behind the ranking and a way to override it.
  Future<void> _showCompareShots(FolderDuplicateGroup group) {
    final ranking = group.ranking;
    final bestSharpness = ranking == null || ranking.shots.isEmpty
        ? 0.0
        : ranking.shots
              .map((shot) => shot.features.signals.sharpness)
              .reduce((a, b) => a > b ? a : b);
    var finalistsOnly = false;
    final canFilter =
        ranking != null &&
        ranking.finalists.isNotEmpty &&
        ranking.finalists.length < group.photos.length;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Compare ${group.photos.length} similar photos',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (group.evidence != null && group.evidence!.notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Why grouped: ${group.evidence!.notes.join(' · ')}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF77796F),
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  ranking == null
                      ? 'No ranking is available for this group.'
                      : '${ranking.headline}. Scores compare these photos with each other only; they are not a rating of the photo itself.',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF77796F)),
                ),
                if (canFilter)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilterChip(
                      label: Text(
                        'Finalists only (${ranking.finalists.length})',
                      ),
                      selected: finalistsOnly,
                      onSelected: (value) =>
                          setDialogState(() => finalistsOnly = value),
                    ),
                  ),
                const SizedBox(height: 10),
                Flexible(
                  child: SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final photo in group.bestFirst.where(
                          (candidate) =>
                              !finalistsOnly ||
                              (ranking?.shotFor(candidate.uri)?.isFinalist ??
                                  true),
                        ))
                          _compareColumn(
                            group,
                            photo,
                            bestSharpness,
                            dialogContext,
                            setDialogState,
                          ),
                      ],
                    ),
                    ),
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
      ),
    );
  }

  Widget _compareColumn(
    FolderDuplicateGroup group,
    FolderScanPhoto photo,
    double bestSharpness,
    BuildContext dialogContext,
    StateSetter setDialogState,
  ) {
    final shot = group.ranking?.shotFor(photo.uri);
    final features = shot?.features ?? photo.features;
    final signals = features?.signals;
    final faces = features?.faces;
    final chosen = _photoRating(photo.uri) > 0;
    // Space freed if this is the photo kept and the rest are deleted.
    final saves = group.photos
        .where((other) => other.uri != photo.uri)
        .fold<int>(0, (total, other) => total + other.size);
    Widget line(IconData icon, Color color, String text) => Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 11))),
        ],
      ),
    );
    return Container(
      width: 210,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(
          color: chosen ? _green : const Color(0xFFE6E8E0),
          width: chosen ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (photo.previewBytes != null)
            InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Image.memory(
                photo.previewBytes!,
                height: 170,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(
                  height: 170,
                  child: Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            )
          else
            const SizedBox(
              height: 170,
              child: Center(child: Icon(Icons.image_not_supported_outlined)),
            ),
          const SizedBox(height: 6),
          Text(
            shot == null
                ? photo.relativePath
                : '${_pickLabel(group, photo) == null ? '' : '${_pickLabel(group, photo)} · '}#${shot.rank} · ${shot.score}/100',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            photo.relativePath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Color(0xFF85877F)),
          ),
          if (shot != null) ...[
            for (final reason in shot.strengths)
              line(Icons.check_circle_outline, _green, reason),
            for (final reason in shot.concerns)
              line(
                Icons.error_outline,
                const Color(0xFFB37957),
                reason,
              ),
            if (shot.isDisqualified)
              line(
                Icons.block,
                const Color(0xFF9A3F2F),
                'Ruled out as a top pick: ${shot.disqualifiers.join(', ')}',
              ),
          ],
          const Divider(height: 14),
          if (signals != null && bestSharpness > 0)
            Text(
              'Sharpness ${_percent(signals.sharpness / bestSharpness)} of best',
              style: const TextStyle(fontSize: 11, color: Color(0xFF85877F)),
            ),
          if (features != null && features.megapixels > 0)
            Text(
              '${features.megapixels.toStringAsFixed(1)} MP · ${_formatBytes(photo.size)}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF85877F)),
            ),
          if (signals != null)
            Text(
              'Brightness ${_percent(signals.meanLuma / 255)}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF85877F)),
            ),
          if (faces != null)
            Text(
              faces.count == 0
                  ? 'No faces found'
                  : '${faces.count} face${faces.count == 1 ? '' : 's'}'
                        '${faces.eyesOpenMin == null ? '' : ' · eyes open ${_percent(faces.eyesOpenMin!)}'}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF85877F)),
            ),
          const SizedBox(height: 6),
          if (group.evidence != null)
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _ungroupPhoto(group, photo);
                },
                child: const Text(
                  'Not the same scene',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: chosen
                ? OutlinedButton.icon(
                    onPressed: () {
                      _setPhotoRating(photo.uri, 1);
                      setDialogState(() {});
                    },
                    icon: const Icon(Icons.check, size: 16),
                    label: Text('Your pick · save ${_formatBytes(saves)} · undo'),
                  )
                : FilledButton.tonal(
                    onPressed: () {
                      _chooseKeeper(group, photo.uri);
                      setDialogState(() {});
                    },
                    child: Text('Keep this · save ${_formatBytes(saves)}'),
                  ),
          ),
        ],
      ),
    );
  }

  /// "Top pick" for the best clean photo, "Finalist" for the other photos
  /// worth choosing between, "Has a fault" for ruled-out photos.
  String? _pickLabel(FolderDuplicateGroup group, FolderScanPhoto photo) {
    final ranking = group.ranking;
    final shot = ranking?.shotFor(photo.uri);
    if (ranking == null || shot == null) return null;
    if (shot.isFinalist) {
      return ranking.finalists.first.id == shot.id ? 'Top pick' : 'Finalist';
    }
    return shot.isDisqualified ? 'Has a fault' : null;
  }

  String _keptSummary(List<FolderScanPhoto> keepers) {
    if (keepers.isEmpty) return 'nothing';
    if (keepers.length == 1) return '"${keepers.first.relativePath}"';
    return '${keepers.length} photos';
  }

  String _shotSummary(FolderDuplicateGroup group, FolderScanPhoto photo) {
    final shot = group.ranking?.shotFor(photo.uri);
    if (shot == null) return 'Quality ${photo.qualityScore}/100';
    return '#${shot.rank} · ${shot.summary}';
  }

  /// Why [group] is not safe to clean up without a person looking at it.
  String _reviewReason(FolderDuplicateGroup group) {
    final evidence = group.evidence;
    if (_settings.manualSelectionOnly) {
      return 'You chose to pick photos yourself, so nothing is selected automatically.';
    }
    if (evidence != null && evidence.confidence != SimilarityConfidence.high) {
      return '${evidence.confidence.label} confidence: these may be different shots of the same place. Look at them before deleting.';
    }
    return 'No photo is clearly better than the others. Look at them before deleting.';
  }

  Widget _emptyState() => Container(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 26),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .65),
      border: Border.all(color: const Color(0xFFE0E4D8)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2E8),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Icon(
            Icons.photo_library_outlined,
            size: 38,
            color: _green,
          ),
        ),
        const SizedBox(height: 15),
        const Text(
          'Your next favorite is waiting.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 7),
        const Text(
          'Add photos you want to keep private and PictoIQ will spot exact copies on this device. To tidy a camera folder, use Scan a folder above.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF81847A), fontSize: 12, height: 1.5),
        ),
      ],
    ),
  );

  Widget _photoCard(PhotoAsset photo, bool isDuplicate) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFE6E8E0)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(photo.path),
                fit: BoxFit.cover,
                cacheWidth: 600,
                errorBuilder: (context, error, stack) => const ColoredBox(
                  color: Color(0xFFE9ECDF),
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: _green,
                    size: 32,
                  ),
                ),
              ),
              if (isDuplicate)
                Positioned(
                  left: 7,
                  top: 7,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .92),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Exact match',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF75523E),
                      ),
                    ),
                  ),
                ),
              Positioned(
                right: 3,
                top: 3,
                child: IconButton.filledTonal(
                  onPressed: () => _removePhoto(photo),
                  tooltip: 'Remove from library',
                  icon: const Icon(Icons.close, size: 17),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: .9),
                    minimumSize: const Size(34, 34),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                photo.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_formatDate(photo.modifiedAt)} · ${_formatBytes(photo.size)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF92948A), fontSize: 10),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: _photoRatingButtons('library:${photo.id}'),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _footer() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.lock_outline, color: _green, size: 15),
      const SizedBox(width: 6),
      Text(
        'No account. No uploads. Your choice.',
        style: TextStyle(color: _ink.withValues(alpha: .55), fontSize: 11),
      ),
    ],
  );

  /// Options as wrapping chips, so a label never breaks in the middle of a
  /// word the way it can in a narrow segmented button.
  Widget _choiceRow<T>({
    required List<T> values,
    required T selected,
    required String Function(T) label,
    required ValueChanged<T> onSelected,
  }) => Align(
    alignment: Alignment.centerLeft,
    child: Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final value in values)
          ChoiceChip(
            label: Text(label(value)),
            selected: value == selected,
            onSelected: (_) => onSelected(value),
          ),
      ],
    ),
  );

  Future<void> _showSettings() => showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        icon: const Icon(Icons.tune, color: _green),
        title: const Text('Similar-shot settings'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('I choose which photos to keep'),
                  subtitle: const Text(
                    'PictoIQ never picks a photo to keep in similar-shot groups. Nothing is selected for deletion until you choose a photo to keep.',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _settings.manualSelectionOnly,
                  onChanged: (value) {
                    _updateSettings(
                      _settings.copyWith(manualSelectionOnly: value),
                    );
                    setDialogState(() {});
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use faces and eyes when ranking'),
                  subtitle: const Text(
                    'Detects faces on this device to prefer open eyes and smiles. Turn off for faster scans that rank on sharpness, lighting and resolution only. Applies to the next scan.',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _settings.useFaceSignals,
                  onChanged: (value) {
                    _updateSettings(_settings.copyWith(useFaceSignals: value));
                    setDialogState(() {});
                  },
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'How closely photos must match',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 6),
                _choiceRow<MatchLevel>(
                  values: MatchLevel.values,
                  selected: _settings.matchLevel,
                  label: (level) => level.label,
                  onSelected: (level) {
                    _updateSettings(_settings.copyWith(matchLevel: level));
                    setDialogState(() {});
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${_settings.matchLevel.description} Applies to the next scan.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Also use time taken',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 6),
                _choiceRow<TimeMode>(
                  values: TimeMode.values,
                  selected: _settings.timeMode,
                  label: (mode) => mode.label,
                  onSelected: (mode) {
                    _updateSettings(_settings.copyWith(timeMode: mode));
                    setDialogState(() {});
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${_settings.timeMode.description}${_settings.timeMode == TimeMode.off || _settings.timeMode == TimeMode.hint ? '' : ' Uses camera time, else a date in the file name, else the file date; files that were copied or downloaded can carry misleading dates, and then fewer photos will group.'} Applies to the next scan.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Documents and screenshots of pages',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 6),
                _choiceRow<DocumentMode>(
                  values: DocumentMode.values,
                  selected: _settings.documentMode,
                  label: (mode) => mode.label,
                  onSelected: (mode) {
                    _updateSettings(_settings.copyWith(documentMode: mode));
                    setDialogState(() {});
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${_settings.documentMode.description} Applies to the next scan.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Keep different people apart'),
                  subtitle: const Text(
                    'Keeps photos with different numbers of people, or a main person dressed in clearly different colours, in separate groups. A rough check, not face recognition. Needs "Use faces and eyes" on. Applies to the next scan.',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _settings.splitByPeople,
                  onChanged: (value) {
                    _updateSettings(_settings.copyWith(splitByPeople: value));
                    setDialogState(() {});
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show event headings'),
                  subtitle: const Text(
                    'Lists groups under a date heading when the camera time or a date in the file name is known. Never affects what is grouped.',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _settings.showEvents,
                  onChanged: (value) {
                    _updateSettings(_settings.copyWith(showEvents: value));
                    setDialogState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    ),
  );

  Future<void> _showPrivacy() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.shield_outlined, color: _green),
      title: const Text('Your photos stay on this device.'),
      content: const Text(
        'PictoIQ uses the system photo picker. It copies only the photos you choose into private app storage, then calculates fingerprints on your device. There are no accounts or uploads. Removing a photo from PictoIQ deletes its private copy, not the original in your gallery.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

/// Explains an empty result, including the common cases where nothing was
/// scanned at all, so the user knows what to change.
String _noGroupsText(FolderScanResult scan, {required bool bestShots}) {
  if (scan.imagesScanned == 0 && scan.imageFilesFound == 0) {
    return 'No image files were found in "${scan.folderName}". Choose the folder that directly holds your photos, for example DCIM > Camera.${_skippedNote(scan.imagesSkipped)}';
  }
  if (scan.imagesScanned == 0 && scan.imagesOutsideDateRange > 0) {
    return 'Found ${scan.imagesOutsideDateRange} photos in "${scan.folderName}", but none from ${scan.rangeDescription}. Tap New scan and choose Last 30 days or Current folder.${_skippedNote(scan.imagesSkipped)}';
  }
  final what = bestShots ? 'No similar shots found.' : 'No exact duplicates found.';
  return 'Scanned ${scan.imagesScanned} images (${scan.rangeDescription}). $what${_skippedNote(scan.imagesSkipped)}';
}

String _skippedNote(int skipped) => skipped == 0
    ? ''
    : ' $skipped skipped (unreadable or unsupported format; never deleted).';

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
}

String _sortLabel(_PhotoSort sort) => switch (sort) {
  _PhotoSort.recent => 'Recent',
  _PhotoSort.name => 'Name',
  _PhotoSort.largest => 'Largest',
};

String _formatDate(DateTime? date) {
  if (date == null) return 'Date unknown';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
