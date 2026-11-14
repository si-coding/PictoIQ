import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart' show PhotoManager;
import 'package:share_plus/share_plus.dart';

import 'package:pictoiq_mobile/shared/app_menu_button.dart';
import 'package:pictoiq_mobile/core/config/app_colors.dart';
import 'package:pictoiq_mobile/core/config/feature_flags.dart';
import 'package:pictoiq_mobile/features/photos/clutter/clutter_classifier.dart';
import 'package:pictoiq_mobile/features/photos/clutter/clutter_page.dart';
import 'package:pictoiq_mobile/features/photos/library/album_picker_page.dart';
import 'package:pictoiq_mobile/features/photos/share/share_preview_page.dart';
import 'package:pictoiq_mobile/shared/app_back_button.dart';
import 'package:pictoiq_mobile/shared/app_background.dart';
import 'package:pictoiq_mobile/shared/app_bar_title.dart';
import 'package:pictoiq_mobile/features/splash/splash_page.dart';
import 'package:pictoiq_mobile/features/settings/app_settings.dart';
import 'package:pictoiq_mobile/features/settings/category_settings.dart';
import 'package:pictoiq_mobile/shared/event_grouping.dart';
import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart';
import 'package:pictoiq_mobile/core/database/database_service.dart';
import 'package:pictoiq_mobile/features/photos/best_moments/moment_selection.dart';
import 'package:pictoiq_mobile/core/media/media_asset.dart';
import 'package:pictoiq_mobile/core/video/video_reel_service.dart';
import 'package:pictoiq_mobile/features/photos/library/photo_viewer_page.dart';
import 'package:pictoiq_mobile/features/photos/library/scanned_files_page.dart';
import 'package:pictoiq_mobile/features/scan/scan_configuration_page.dart';
import 'package:pictoiq_mobile/features/photos/best_shot/selection_policy.dart';
import 'package:pictoiq_mobile/features/settings/settings_page.dart';
import 'package:pictoiq_mobile/features/videos/duplicates/video_duplicates.dart';
import 'package:pictoiq_mobile/features/videos/duplicates/video_duplicates_page.dart';
import 'package:pictoiq_mobile/features/videos/export/reel_configuration_page.dart';
import 'package:pictoiq_mobile/features/videos/library/video_album_picker_page.dart';
import 'package:pictoiq_mobile/shared/shot_ranking.dart' show RankedShot;
import 'package:pictoiq_mobile/shared/similarity_grouping.dart';

/// What the main scan button on the home screen does.
enum ScanMode { bestShot, bestMoments, duplicates, clutter }

/// The tools offered on the Videos tab (not available yet).
enum VideoTool { exactDuplicates, similarVideos, bestMoments, enhance }

const _ink = AppColors.ink;
const _green = AppColors.primary;
const _canvas = AppColors.canvas;

enum _PhotoSort { recent, name, largest }

class _FeatureArtwork extends StatelessWidget {
  const _FeatureArtwork({
    required this.icon,
    required this.background,
    required this.accent,
  });

  final IconData icon;
  final Color background;
  final Color accent;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(
      height: 88,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [background, Color.lerp(background, accent, .22)!],
              ),
            ),
          ),
          CustomPaint(painter: _FeatureArtworkPainter(accent)),
          Positioned(
            left: 16,
            top: 13,
            child: Container(
              width: 54,
              height: 62,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .8),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: .16),
                    blurRadius: 10,
                    offset: const Offset(2, 4),
                  ),
                ],
              ),
              child: Icon(icon, size: 28, color: accent),
            ),
          ),
          Positioned(
            left: 56,
            top: 20,
            child: Transform.rotate(
              angle: .13,
              child: Container(
                width: 48,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .68),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  size: 22,
                  color: accent.withValues(alpha: .72),
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 11,
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .72),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: accent),
            ),
          ),
        ],
      ),
    ),
  );
}

class _FeatureArtworkPainter extends CustomPainter {
  const _FeatureArtworkPainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final sunPaint = Paint()..color = Colors.white.withValues(alpha: .52);
    canvas.drawCircle(
      Offset(size.width * .78, size.height * .28),
      19,
      sunPaint,
    );

    final backHill = Path()
      ..moveTo(size.width * .42, size.height)
      ..quadraticBezierTo(
        size.width * .73,
        size.height * .36,
        size.width,
        size.height * .78,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(backHill, Paint()..color = accent.withValues(alpha: .16));

    final frontHill = Path()
      ..moveTo(size.width * .35, size.height)
      ..quadraticBezierTo(
        size.width * .66,
        size.height * .55,
        size.width,
        size.height * .92,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(frontHill, Paint()..color = accent.withValues(alpha: .24));
  }

  @override
  bool shouldRepaint(_FeatureArtworkPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

void main() => runApp(const PictoIqApp());

class PictoIqApp extends StatelessWidget {
  const PictoIqApp({super.key, this.showSplash = true});

  /// Shows the animated PictoIQ opening screen before the library.
  final bool showSplash;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PictoIQ',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: _canvas,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.pageTop,
        foregroundColor: _ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: _ink,
        ),
      ),
      colorScheme: AppColors.modern
          ? ColorScheme.fromSeed(
              seedColor: _green,
            ).copyWith(primary: _green, onPrimary: Colors.white)
          : ColorScheme.fromSeed(seedColor: _green),
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: _ink,
        displayColor: _ink,
      ),
      navigationBarTheme: AppColors.modern
          ? NavigationBarThemeData(
              backgroundColor: Colors.white,
              indicatorColor: AppColors.navIndicator,
              iconTheme: WidgetStateProperty.resolveWith(
                (states) => IconThemeData(
                  color: states.contains(WidgetState.selected)
                      ? const Color(0xFF0B3B2C)
                      : AppColors.body,
                ),
              ),
              labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: states.contains(WidgetState.selected)
                      ? const Color(0xFF0B3B2C)
                      : AppColors.body,
                ),
              ),
            )
          : null,
    ),
    home: showSplash
        ? SplashPage(next: (_) => const LibraryPage())
        : const LibraryPage(),
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
  final _videoReelService = VideoReelService();
  final _videoScanner = VideoDuplicateScanner();

  /// The video album chosen on the Videos tab.
  VideoAlbum? _selectedVideoAlbum;

  /// True while the exact-duplicate video scan runs (changes the wording of
  /// the progress).
  bool _scanningVideos = false;
  final _settingsStore = SettingsStore();
  final _searchController = TextEditingController();
  final Map<String, int> _photoRatings = {};

  /// Space and photos freed by deletions since the last scan started.
  int _freedBytes = 0;
  int _freedPhotos = 0;
  AppSettings _settings = const AppSettings();
  List<PhotoAsset> _photos = [];
  FolderSelection? _selectedFolder;
  FolderDateRange _folderDateRange = FolderDateRange.week;

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
  bool _creatingReel = false;
  bool _cancelReelRequested = false;
  bool _reelNativeStarted = false;
  bool _scanningBestShots = false;
  bool _duplicatesOnly = false;
  _PhotoSort _sort = _PhotoSort.recent;
  final int _tab = 0;
  bool _showResultsPage = false;

  /// The settings the results on screen were found with, to tell when the
  /// filters have been changed since.
  AppSettings? _resultsScanSettings;
  ScanMode _scanMode = ScanMode.bestShot;

  /// Whether the home screen shows the Videos tab instead of Photos.
  /// Videos can be switched off for a build (see [FeatureFlags]).
  bool get _videoEnabled => FeatureFlags.current.videoEnabled;

  /// True while the Videos side of the switch is showing. Only ever true when
  /// [_videoEnabled], because the switch is not shown otherwise.
  bool _videoMode = false;
  VideoTool _videoTool = VideoTool.exactDuplicates;

  /// Lets the home screen scroll to the main scan button.
  final _mainScanKey = GlobalKey();
  final _scanCancelKey = GlobalKey();
  final _scanProgressRevision = ValueNotifier<int>(0);
  final _scrollController = ScrollController();

  /// Whether the home screen is scrolled far enough for a back-to-top button.
  final ValueNotifier<bool> _showTopButton = ValueNotifier(false);
  bool _showBestResults = true;
  bool _scanActive = false;
  bool _cancelRequested = false;

  /// True when the results on screen come from "Find best moments", which
  /// keeps the top few photos of each group instead of one.
  bool _momentsMode = false;

  /// True while best-moments results are on screen. Those only show the top
  /// two photos of each group and nothing is ever deleted from them.
  bool get _moments => _momentsMode && _resultsAreBestShots;

  /// The (up to) two photos shown for a best-moments group, best first.
  final Map<String, List<FolderScanPhoto>> _momentCache = {};

  List<FolderScanPhoto> _momentPair(FolderDuplicateGroup group) {
    final key =
        '${group.id}|${group.photos.length}|${_settings.momentCount}|${_settings.momentVariety.name}|${_settings.momentExpression.name}|${_settings.momentPeople.name}';
    return _momentCache.putIfAbsent(key, () => _chooseMoments(group));
  }

  /// The photos shown for a moment: the best one first, then others chosen
  /// to look different from it (see [chooseMomentPhotos]).
  List<FolderScanPhoto> _chooseMoments(FolderDuplicateGroup group) {
    final ranked = group.bestFirst;
    if (ranked.isEmpty) return const [];
    final candidates = [
      for (final photo in ranked)
        MomentPhoto(
          id: photo.uri,
          baseScore:
              (group.ranking?.shotFor(photo.uri)?.score ?? photo.qualityScore) /
              100,
          disqualified:
              group.ranking?.shotFor(photo.uri)?.isDisqualified ?? false,
          faceCount: photo.features?.faces?.count,
          smile: photo.features?.faces?.smileAverage,
          eyesOpen: photo.features?.faces?.eyesOpenMin,
          edgeCutoff: photo.features?.faces?.edgeCutoff ?? false,
          visualHash: photo.visualHash,
          colorLayout: photo.colorLayout,
          people: photo.features?.faces?.personColors,
        ),
    ];
    final ids = chooseMomentPhotos(
      candidates,
      count: _settings.momentCount,
      variety: _settings.momentVariety,
      expression: _settings.momentExpression,
      clothingLimit: switch (_settings.momentPeople) {
        MatchLevel.strict => 0.2,
        MatchLevel.balanced => 0.3,
        MatchLevel.loose => 0.4,
      },
    );
    final byUri = {for (final photo in ranked) photo.uri: photo};
    return [
      for (final id in ids)
        if (byUri[id] != null) byUri[id]!,
    ];
  }

  /// What a moment shows: a portrait, a pair, a group of people or a scene.
  String _momentKind(FolderDuplicateGroup group) {
    final top = group.bestFirst.isEmpty ? null : group.bestFirst.first;
    return switch (compositionOf(top?.features?.faces?.count)) {
      Composition.unknown => 'Moment',
      Composition.noFaces => 'Scene',
      Composition.single => 'Portrait',
      Composition.couple => 'Pair',
      Composition.group => 'Group photo',
    };
  }

  /// "13:51" when the group's photos carry a camera time, else null.
  String? _groupClock(FolderDuplicateGroup group) {
    var newest = 0;
    for (final photo in group.photos) {
      if (photo.captureSource == CaptureSource.exif &&
          photo.capturedAt > newest) {
        newest = photo.capturedAt;
      }
    }
    if (newest == 0) return null;
    final time = DateTime.fromMillisecondsSinceEpoch(newest);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}';
  }

  /// The heading of a result card, for example "Group 2 · 4 similar shots ·
  /// 13:51" or "Moment 1 · Portrait · 13:51".
  String _groupName(FolderDuplicateGroup group, int number) {
    final clock = _groupClock(group);
    final parts = _moments
        ? ['Moment $number', _momentKind(group)]
        : [
            'Group $number',
            '${group.photos.length} similar shot${group.photos.length == 1 ? '' : 's'}',
          ];
    return [...parts, ?clock].join(' · ');
  }

  /// Which of the pair is selected for sharing: the person's choice, or the
  /// top moment by default.
  Set<String> _momentSelected(FolderDuplicateGroup group) {
    final pair = _momentPair(group);
    final chosen = {
      for (final photo in pair)
        if (_photoRatings[photo.uri] == 1) photo.uri,
    };
    return chosen.isEmpty ? {pair.first.uri} : chosen;
  }

  int _folderImagesScanned = 0;
  String? _error;
  String? _folderScanError;
  String? _bestShotsError;

  @override
  void initState() {
    super.initState();
    AppMenuActions.openSettings = _openSettings;
    AppMenuActions.showPrivacy = _showPrivacy;
    AppMenuActions.goHome = _goHome;
    _loadPhotos();
    _loadSettings();
    unawaited(_loadLibrarySnapshot());
    _scrollController.addListener(() {
      final far =
          _scrollController.hasClients && _scrollController.offset > 700;
      if (far != _showTopButton.value) _showTopButton.value = far;
    });
  }

  /// The Home button on every other screen: closes whatever is open above
  /// the home screen and hides the results page, so Home is always what shows.
  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (_showResultsPage) setState(() => _showResultsPage = false);
  }

  /// Photo, video and album totals for the home header; null until access to
  /// the library has been given.
  ({int photos, int videos, int albums})? _librarySnapshot;

  Future<void> _loadLibrarySnapshot() async {
    final snapshot = await _folderScanner.librarySnapshot();
    if (mounted && snapshot != null) {
      setState(() => _librarySnapshot = snapshot);
    }
  }

  static String _thousands(int value) => value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );

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

  Future<bool> _scanFolder() async {
    return _runFolderScan(bestShots: false);
  }

  Future<bool> _scanBestShotsFolder() async {
    return _runFolderScan(bestShots: true);
  }

  /// The photos kept in each group (one per best shot, two per best moment),
  /// newest group first, ready to share.
  List<FolderScanPhoto> _picksToShare(Iterable<FolderDuplicateGroup> groups) {
    final picks = <FolderScanPhoto>[];
    for (final group in groups) {
      final decision = _decisionFor(group, bestShots: true);
      if (!decision.hasDecision) continue;
      for (final photo in group.photos) {
        if (decision.keepIds.contains(photo.uri)) picks.add(photo);
      }
    }
    return picks;
  }

  /// Opens Android's share sheet with [photos]; WhatsApp (status or chat),
  /// Instagram and Facebook appear there when they are installed.
  Future<void> _sharePhotos(List<FolderScanPhoto> chosen) async {
    if (chosen.isEmpty) return;
    // Let the person look at (and drop) photos before anything is sent.
    final photos = await Navigator.of(context).push<List<FolderScanPhoto>>(
      MaterialPageRoute(
        builder: (_) => SharePreviewPage(
          photos: chosen,
          title: _moments ? 'Share best moments' : 'Share best shots',
        ),
      ),
    );
    if (photos == null || photos.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // Most apps handle a few dozen photos at a time at best.
    final batch = photos.take(30).toList();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Preparing photos to share…')),
      );
    try {
      final paths = await _folderScanner.prepareForSharing(batch);
      messenger.hideCurrentSnackBar();
      if (paths.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Those photos could not be read.')),
        );
        return;
      }
      await SharePlus.instance.share(
        ShareParams(files: [for (final path in paths) XFile(path)]),
      );
      if (photos.length > batch.length && mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Shared the first ${batch.length} of ${photos.length} photos.',
            ),
          ),
        );
      }
    } catch (error) {
      debugPrint('Share failed: $error');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not open sharing.')),
        );
    }
  }

  Future<void> _createPhotoReel(FolderScanResult scan) async {
    if (_creatingReel) return;
    final photos = _picksToShare(scan.duplicateGroups)
        .take(_settings.reelMaxPhotos)
        .toList();
    if (photos.isEmpty) {
      _showMessage('No selected photos are available to add to a reel.');
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ReelConfigurationPage(
          photos: photos,
          maxPhotos: _settings.reelMaxPhotos,
          secondsPerPhoto: _settings.reelSecondsPerPhoto,
          transitionMillis: _settings.reelTransitionMillis,
          titleStyle: _settings.reelTitleStyle,
          pickAudio: _videoReelService.pickAudio,
          discardAudio: _videoReelService.discardAudio,
          reelProgress: _videoReelService.progress,
          onCreate: _exportConfiguredReel,
          onCancel: _cancelPhotoReel,
        ),
      ),
    );
  }

  Future<void> _exportConfiguredReel(ReelConfiguration configuration) async {
    if (_creatingReel) return;
    _cancelReelRequested = false;
    _reelNativeStarted = false;
    setState(() => _creatingReel = true);
    try {
      final paths = await _folderScanner.prepareForSharing(
        configuration.photos,
      );
      if (paths.length != configuration.photos.length) {
        throw StateError('Not all selected photos could be read.');
      }
      if (!mounted) return;
      if (_cancelReelRequested) {
        throw const ReelCreationCancelledException();
      }
      final String reelPath;
      try {
        reelPath = await _videoReelService.createReel(
          paths,
          audioPath: configuration.audioPath,
          secondsPerPhoto: _settings.reelSecondsPerPhoto,
          transitionMillis: _settings.reelTransitionMillis,
          title: configuration.title,
          titleStyle: configuration.titleStyle.name,
          isCancellationRequested: () => _cancelReelRequested,
          onNativeCreationStarted: () {
            _reelNativeStarted = true;
          },
        );
      } finally {
        _reelNativeStarted = false;
      }
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(reelPath)],
          text: 'Photo reel created with PictoIQ',
        ),
      );
    } catch (error, stack) {
      if (error is ReelCreationCancelledException) return;
      debugPrint('Photo reel failed: $error\n$stack');
      rethrow;
    } finally {
      _reelNativeStarted = false;
      _cancelReelRequested = false;
      if (mounted) setState(() => _creatingReel = false);
    }
  }

  Future<void> _cancelPhotoReel() async {
    _cancelReelRequested = true;
    if (_reelNativeStarted) {
      await _videoReelService.cancelReelCreation();
    }
  }

  /// Looser grouping (same people and place, different poses) that keeps the
  /// top few photos of each group.
  Future<bool> _scanBestMoments() async {
    return _runFolderScan(bestShots: true, moments: true);
  }

  /// Looks for screenshots, documents, blank, blurry and tiny photos and
  /// opens a review screen. Nothing is deleted without confirmation.
  Future<bool> _scanClutter() async {
    if (_settings.clutterOff.length == ClutterKind.values.length) {
      _showMessage('Every clutter type is turned off in Settings.');
      return false;
    }
    return _runFolderScan(bestShots: true, clutter: true);
  }

  Future<void> _showClutter(FolderScanResult scan) async {
    final items = findClutter(
      scan.scannedPhotos,
      thresholds: ClutterThresholds(
        blurrySharpness: _settings.clutterBlur.sharpness,
      ),
      leaveOut: _settings.clutterOff,
    );
    if (items.isEmpty) {
      _showMessage(
        'No clutter found in ${scan.folderName}. '
        '${scan.imagesScanned} photo${scan.imagesScanned == 1 ? '' : 's'} checked.'
        '${_skippedNote(scan.imagesSkipped)}',
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ClutterPage(
          items: items,
          folderName: scan.folderName,
          rangeDescription: scan.rangeDescription,
          imagesSkipped: scan.imagesSkipped,
          deleteFiles: _folderScanner.deleteFiles,
          settingsPanel: _resultsSettingsPanel(
            SettingsCategory.clutter,
            scan.folderName,
            scan.rangeDescription,
            '${scan.imagesScanned} photos checked · ${items.length} look like clutter',
            () => _findAgain(ScanMode.clutter),
          ),
          onFind: () => _findAgain(ScanMode.clutter),
        ),
      ),
    );
  }

  void _findVideosAgain() {
    Navigator.of(context).pop();
    unawaited(_openVideoConfiguration(VideoTool.exactDuplicates));
  }

  /// Closes the results on top and opens the tool's Find screen.
  void _findAgain(ScanMode mode) {
    Navigator.of(context).pop();
    unawaited(_openPhotoConfiguration(mode));
  }

  /// The scope card for results pages that are their own screen (clutter,
  /// videos).
  Widget _resultsSettingsPanel(
    SettingsCategory category,
    String folder,
    String range,
    String counts,
    VoidCallback onFindAgain,
  ) => ScanScopeCard(
    folder: folder,
    range: range,
    counts: counts,
    category: category,
    settings: _settings,
    scannedWith: _settings,
    onChanged: _updateSettings,
    onFindAgain: onFindAgain,
  );

  /// Opens the video album picker (covers and counts, like the photo albums)
  /// and remembers the choice. "Other folder…" uses Android's folder picker.
  Future<VideoAlbum?> _chooseVideoAlbum() async {
    if (_scanningFolder || _importing) return null;
    try {
      final choice = await Navigator.of(context).push<Object>(
        MaterialPageRoute<Object>(
          builder: (_) => VideoAlbumPickerPage(
            requestAccess: _videoScanner.requestAccess,
            loadAlbums: _videoScanner.listAlbums,
            loadCover: _videoScanner.albumCover,
            openSettings: PhotoManager.openSetting,
            manageLimited: _videoScanner.manageLimitedAccess,
            accessDetail: () => _videoScanner.accessDetail,
            loadVideos: _videoScanner.albumVideos,
            loadVideoUrl: _videoScanner.videoUrl,
          ),
        ),
      );
      if (!mounted) return null;
      VideoAlbum? chosen;
      if (choice is VideoAlbum) {
        chosen = choice;
      } else if (choice == VideoPickerChoice.otherFolder) {
        chosen = await _videoScanner.pickFolder();
      }
      if (chosen != null && mounted) {
        setState(() => _selectedVideoAlbum = chosen);
      }
      return chosen;
    } catch (error) {
      debugPrint('Video albums unavailable: ${error.runtimeType}');
      if (mounted) _showMessage('Could not open your video albums.');
      return null;
    }
  }

  /// Finds videos with identical content in the chosen album and opens a
  /// review screen. Nothing is deleted without confirmation.
  Future<bool> _scanVideoDuplicates() async {
    final album = _selectedVideoAlbum;
    if (album == null || _scanningFolder || _importing) return false;
    setState(() {
      _scanningFolder = true;
      _scanningVideos = true;
      _scanActive = true;
      _cancelRequested = false;
      _folderImagesScanned = 0;
      _folderImagesTotal = null;
      _folderImagesFound = 0;
      _folderFilesChecked = 0;
      _scanStartedAt = DateTime.now();
    });
    _scanProgressRevision.value++;
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_scanActive || _folderImagesTotal != null) {
        timer.cancel();
      } else {
        setState(() {});
        _scanProgressRevision.value++;
      }
    });
    VideoScanResult? result;
    try {
      result = await _videoScanner.scan(
        album,
        dateRange: _folderDateRange,
        rangeFrom: _customRange?.start,
        rangeTo: _customRange?.end,
        onListed: (found) {
          if (mounted) {
            setState(() => _folderImagesFound = found);
            _scanProgressRevision.value++;
          }
        },
        onTotal: (total) {
          if (mounted) {
            setState(() => _folderImagesTotal = total);
            _scanProgressRevision.value++;
          }
        },
        onProgress: (count) {
          if (mounted) {
            setState(() => _folderImagesScanned = count);
            _scanProgressRevision.value++;
          }
        },
        shouldCancel: () => _cancelRequested,
      );
    } on ScanCancelled {
      if (mounted) _showMessage('Scan cancelled. Nothing was changed.');
    } catch (error) {
      debugPrint('Video scan failed: ${error.runtimeType}');
      if (mounted) {
        _showMessage(
          'PictoIQ could not scan those videos. Try again or choose another album.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _scanningFolder = false;
          _scanningVideos = false;
          _scanActive = false;
        });
        _scanProgressRevision.value++;
      }
    }
    final done = result;
    if (done == null || !mounted) return false;
    await _showVideoDuplicates(done);
    return true;
  }

  Future<void> _showVideoDuplicates(VideoScanResult scan) async {
    if (scan.groups.isEmpty) {
      _showResultPopup(
        'No exact duplicate videos found in ${scan.albumName}. '
        '${scan.videosFound} video${scan.videosFound == 1 ? '' : 's'} checked.'
        '${scan.videosUnreadable == 0 ? '' : ' ${scan.videosUnreadable} could not be read.'}',
        found: false,
      );
      return;
    }
    final range =
        _folderDateRange == FolderDateRange.custom && _customRange != null
        ? '${_formatDate(_customRange!.start)} – ${_formatDate(_customRange!.end)}'
        : _folderDateRange.label;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => VideoDuplicatesPage(
          result: scan,
          rangeDescription: range,
          keep: _settings.videoKeep,
          deleteVideos: _videoScanner.deleteVideos,
          settingsPanel: _resultsSettingsPanel(
            SettingsCategory.video,
            scan.albumName,
            range,
            '${scan.videosFound} videos checked · ${scan.groups.length} sets',
            _findVideosAgain,
          ),
          onFind: _findVideosAgain,
        ),
      ),
    );
  }

  Future<void> _openPhotoConfiguration(ScanMode mode) async {
    setState(() {
      _videoMode = false;
      _scanMode = mode;
    });
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ScanConfigurationPage(
          title: _photoFeatureTitle(mode),
          icon: switch (mode) {
            ScanMode.bestMoments => Icons.collections_outlined,
            ScanMode.duplicates => Icons.copy_all_outlined,
            ScanMode.bestShot => Icons.photo_camera_outlined,
            ScanMode.clutter => Icons.cleaning_services_outlined,
          },
          description: _photoFeatureDescription(mode),
          isVideo: false,
          initialDateRange: _folderDateRange,
          initialCustomRange: _customRange,
          onDateRangeSelected: _selectDateRange,
          initialPhotoFolder: _selectedFolder,
          initialVideoAlbum: null,
          browsePhotoFolder: _chooseFolder,
          browseVideoAlbum: () async => null,
          loadPhotoGallery: (folder) async {
            final id = folder.albumId;
            if (id == null) return const <Uint8List?>[];
            final end = (folder.count ?? 12).clamp(0, 12);
            return _folderScanner.albumThumbnails(id, 0, end);
          },
          loadVideoGallery: (_) async => const [],
          scanEnabled: Platform.isAndroid && !_scanningFolder && !_importing,
          scanLabel: 'Find ${_photoFeatureTitle(mode)}',
          settingsPanel: _settingsPanel(_categoryFor(mode)),
          onSettings: _openSettings,
          onPrivacy: _showPrivacy,
          onScan: () => switch (mode) {
            ScanMode.bestShot => _scanBestShotsFolder(),
            ScanMode.bestMoments => _scanBestMoments(),
            ScanMode.duplicates => _scanFolder(),
            ScanMode.clutter => _scanClutter(),
          },
          onCancelScan: _cancelScan,
          scanProgressRevision: _scanProgressRevision,
          scanProgressBuilder: () => _scanProgressButton(inConfiguration: true),
        ),
      ),
    );
    unawaited(_loadLibrarySnapshot());
    _flushPopup();
  }

  SettingsCategory _categoryFor(ScanMode mode) => switch (mode) {
    ScanMode.bestMoments => SettingsCategory.bestMoments,
    ScanMode.bestShot => SettingsCategory.bestShot,
    ScanMode.duplicates => SettingsCategory.duplicates,
    ScanMode.clutter => SettingsCategory.clutter,
  };

  /// Collapsible, editable settings for one tool.
  Widget _settingsPanel(SettingsCategory category) => CategorySettingsPanel(
    category: category,
    settings: _settings,
    onChanged: _updateSettings,
  );

  /// The tool whose results are on screen, for the Find button.
  ScanMode get _resultsMode => _moments && _resultsAreBestShots
      ? ScanMode.bestMoments
      : _resultsAreBestShots
      ? ScanMode.bestShot
      : ScanMode.duplicates;

  Future<void> _openVideoConfiguration(VideoTool tool) async {
    setState(() {
      _videoMode = true;
      _videoTool = tool;
    });
    final isAvailable = tool == VideoTool.exactDuplicates;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ScanConfigurationPage(
          title: _videoFeatureTitle(tool),
          icon: tool == VideoTool.exactDuplicates
              ? Icons.copy_all_outlined
              : Icons.videocam_outlined,
          description: _videoFeatureDescription(tool),
          isVideo: true,
          initialDateRange: _folderDateRange,
          initialCustomRange: _customRange,
          onDateRangeSelected: _selectDateRange,
          initialPhotoFolder: null,
          initialVideoAlbum: _selectedVideoAlbum,
          browsePhotoFolder: () async => null,
          browseVideoAlbum: _chooseVideoAlbum,
          loadPhotoGallery: (_) async => const <Uint8List?>[],
          loadVideoGallery: (album) => _videoScanner.albumVideos(
            album.id,
            0,
            (album.count == 0 ? 12 : album.count).clamp(0, 12),
          ),
          scanEnabled:
              Platform.isAndroid &&
              isAvailable &&
              !_scanningFolder &&
              !_importing,
          scanLabel: isAvailable
              ? 'Find exact duplicate videos'
              : 'Coming soon',
          onSettings: _openSettings,
          onPrivacy: _showPrivacy,
          onScan: () async {
            if (!isAvailable) {
              _showMessage('${_videoFeatureTitle(tool)} is coming soon.');
              return false;
            }
            return _scanVideoDuplicates();
          },
          onCancelScan: _cancelScan,
          scanProgressRevision: _scanProgressRevision,
          scanProgressBuilder: () => _scanProgressButton(inConfiguration: true),
          settingsPanel: isAvailable
              ? _settingsPanel(SettingsCategory.video)
              : null,
        ),
      ),
    );
    unawaited(_loadLibrarySnapshot());
    _flushPopup();
  }

  String _photoFeatureTitle(ScanMode mode) => switch (mode) {
    ScanMode.bestMoments => 'Best Moments',
    ScanMode.duplicates => 'Exact Duplicates',
    ScanMode.bestShot => 'Best Shots',
    ScanMode.clutter => 'Clutter',
  };

  String _photoFeatureDescription(ScanMode mode) => switch (mode) {
    ScanMode.bestMoments =>
      'Find meaningful moments and choose the photos you want to share.',
    ScanMode.duplicates =>
      'Find byte-for-byte copies of the same photo and review them safely.',
    ScanMode.bestShot => 'Compare similar photos and keep your strongest shot.',
    ScanMode.clutter =>
      'Find blurry, blank, tiny and other clutter photos to review.',
  };

  String _videoFeatureTitle(VideoTool tool) => switch (tool) {
    VideoTool.exactDuplicates => 'Exact Video Duplicates',
    VideoTool.similarVideos => 'Similar Videos',
    VideoTool.bestMoments => 'Video Best Moments',
    VideoTool.enhance => 'Video Enhance',
  };

  String _videoFeatureDescription(VideoTool tool) => switch (tool) {
    VideoTool.exactDuplicates =>
      'Find identical video copies and review them before deleting.',
    VideoTool.similarVideos =>
      'Find repeated recordings of the same scene. Coming soon.',
    VideoTool.bestMoments =>
      'Discover meaningful moments inside your videos. Coming soon.',
    VideoTool.enhance =>
      'Improve brightness, clarity and stability. Coming soon.',
  };

  Future<FolderSelection?> _chooseFolder() async {
    if (_scanningFolder || _importing) return null;
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
            accessDetail: () => _folderScanner.accessDetail,
          ),
        ),
      );
      if (choice == null || !mounted) return null;
      final FolderSelection? selected = choice is FolderSelection
          ? choice
          : await _folderScanner.pickFolder();
      if (selected == null || !mounted) return null;
      setState(() {
        _selectedFolder = selected;
        _folderScan = null;
        _bestShotsScan = null;
        _folderScanError = null;
        _bestShotsError = null;
      });
      return selected;
    } catch (error) {
      debugPrint('Folder picker failed: $error');
      if (mounted) {
        _showMessage(
          'PictoIQ could not open the folder picker (${error.runtimeType}). Try again.',
        );
      }
      return null;
    }
  }

  Future<bool> _runFolderScan({
    required bool bestShots,
    bool moments = false,
    bool clutter = false,
  }) async {
    FolderScanResult? clutterResult;
    final selectedFolder = _selectedFolder;
    if (!Platform.isAndroid ||
        selectedFolder == null ||
        _scanningFolder ||
        _importing) {
      return false;
    }
    setState(() {
      _scanningFolder = true;
      _scanningBestShots = bestShots;
      _momentsMode = bestShots && moments;
      _scanActive = true;
      _cancelRequested = false;
      _showBestResults = bestShots;
      _showResultsPage = false;
      _folderImagesScanned = 0;
      _folderImagesTotal = null;
      _folderImagesFound = 0;
      _folderFilesChecked = 0;
      _scanStartedAt = DateTime.now();
      _freedBytes = 0;
      _freedPhotos = 0;
      // A new scan starts from a clean slate: no results or choices left
      // over from the previous one.
      _folderScan = null;
      _bestShotsScan = null;
      _folderScanError = null;
      _bestShotsError = null;
      _photoRatings.clear();
      _momentCache.clear();
    });
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_scanActive || _folderImagesTotal != null) {
        timer.cancel();
      } else {
        setState(() {});
        _scanProgressRevision.value++;
      }
    });
    var completed = false;
    try {
      final scanned = await _folderScanner.scanUri(
        selectedFolder.uri,
        folderName: selectedFolder.name,
        bestShotsScan: bestShots,
        groupShots: !clutter,
        useFaceSignals: _settings.useFaceSignals,
        thresholds: moments
            ? SimilarityThresholds.moments(
                splitByPeople: _settings.splitByPeople,
                windowMs: _settings.momentWindow.capMs,
                trustedGapMs: _settings.momentWindow.trustedMs,
                people: _settings.momentPeople,
                splitComposition: _settings.momentSeparateTypes,
                placeMeters: _settings.momentPlace.meters,
              )
            : SimilarityThresholds.forLevel(
                _settings.matchLevel,
                splitByPeople: _settings.splitByPeople,
                timeMode: _settings.timeMode,
              ),
        documentMode: _settings.documentMode,
        // Clutter looks for screens and objects with the labeller, unless that
        // clutter type is turned off.
        contentFilter: clutter
            ? (_settings.clutterOff.contains(ClutterKind.screenOrObject)
                  ? ContentFilter.everything
                  : ContentFilter.peopleAndScenery)
            : _settings.contentFilter,
        dateRange: _folderDateRange,
        rangeFrom: _customRange?.start,
        rangeTo: _customRange?.end,
        onListed: (found, checked) {
          if (mounted) {
            setState(() {
              _folderImagesFound = found;
              _folderFilesChecked = checked;
            });
            _scanProgressRevision.value++;
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
          if (mounted) {
            setState(() => _folderImagesTotal = total);
            _scanProgressRevision.value++;
          }
        },
        onProgress: (count) {
          if (mounted) {
            setState(() => _folderImagesScanned = count);
            _scanProgressRevision.value++;
          }
        },
        shouldCancel: () => _cancelRequested,
      );
      if (clutter) {
        clutterResult = scanned;
      } else {
        // Best moments leaves out groups with no people in them unless the
        // user asked to see them. Face detection must have run on every photo.
        var result = scanned;
        if (bestShots) {
          result = result.withoutFromGroups({
            for (final group in result.duplicateGroups)
              for (final photo in group.photos)
                if (photo.features?.signals.isBlank ?? false) photo.uri,
          });
        }
        if (moments && !_settings.momentShowScenes) {
          result = result.withoutGroups({
            for (final group in result.duplicateGroups)
              if (group.photos.every((p) => p.features?.faces?.count == 0))
                group.id,
          });
        }
        if (!mounted) return false;
        setState(() {
          _showResultsPage = true;
          _resultsScanSettings = _settings;
          if (bestShots) {
            _bestShotsScan = result;
          } else {
            _folderScan = result;
          }
        });
        _showResultPopup(
          result.duplicateGroups.isEmpty
              ? _noGroupsText(result, bestShots: bestShots)
              : bestShots
              ? 'Found ${result.duplicateGroups.length} similar-photo groups in ${result.folderName}. They are similar, not identical, so review them before deleting.${_skippedNote(result.imagesSkipped)}${_documentNote(result)}'
              : 'Found ${result.duplicateGroups.length} exact duplicate groups in ${result.folderName}.${_skippedNote(result.imagesSkipped)}',
          found: result.duplicateGroups.isNotEmpty,
        );
      }
      completed = true;
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
          _showResultsPage = true;
        });
        completed = true;
      }
    } finally {
      if (mounted) {
        setState(() {
          _scanningFolder = false;
          _scanningBestShots = false;
          _scanActive = false;
        });
        _scanProgressRevision.value++;
      }
      // Opened after the scan state is reset, so the home screen is usable
      // again as soon as the review screen is closed.
      final found = clutterResult;
      if (found != null && mounted) await _showClutter(found);
    }
    return completed;
  }

  void _cancelScan() {
    if (_scanActive) setState(() => _cancelRequested = true);
  }

  void _setPhotoRating(String key, int rating) {
    setState(() {
      _photoRatings[key] = _photoRatings[key] == rating ? 0 : rating;
    });
  }

  int _photoRating(String key) => _photoRatings[key] ?? 0;

  /// Best shot with "multiple photos" chosen in Settings. Exact duplicates
  /// and Best Moments always keep one photo (or their own fixed number).
  bool get _multiKeep =>
      _settings.bestShotSelection == BestShotSelection.multiple &&
      _resultsAreBestShots &&
      !_moments;

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
    if (bestShots && _moments) {
      return KeepDecision(
        keepIds: _momentSelected(group),
        isUserChoice: _momentPair(group)
            .any((photo) => _photoRatings[photo.uri] != null),
        needsReview: false,
      );
    }
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
    final remove = decision.removals([
      for (final photo in group.photos) photo.uri,
    ]).toSet();
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
      onPressed: selected && keepIds.length <= 1
          ? null
          : () => _chooseKeeper(group, photo.uri),
      icon: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? _green : AppColors.hint,
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
          color: _photoRating(key) > 0 ? _green : AppColors.hint,
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
              : AppColors.hint,
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
    final keptNames = keepers
        .map((photo) => '"${photo.relativePath}"')
        .join(', ');
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
                  style: TextStyle(fontSize: 12, color: AppColors.hint),
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
                  Text(
                    '• ${photo.relativePath} · ${_shotSummary(group, photo)}',
                  ),
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
                  style: TextStyle(fontSize: 12, color: AppColors.hint),
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
                  style: TextStyle(fontSize: 12, color: AppColors.hint),
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
  Future<DateTimeRange?> _selectDateRange(FolderDateRange range) async {
    var customRange = _customRange;
    if (range == FolderDateRange.custom) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: now,
        initialDateRange: customRange,
        helpText: 'Scan photos from … to …',
        saveText: 'Apply range',
        builder: (context, child) => Theme(
          data: Theme.of(context).copyWith(
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: _green,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: AppColors.tintBorder),
                ),
              ),
            ),
          ),
          child: child!,
        ),
      );
      if (picked == null || !mounted) return null;
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
    return customRange;
  }

  /// Two bars: step 1 finds the photos (slides until the folder is listed,
  /// then full), step 2 analyses them from 0 to 100 %.
  /// The scan button while a scan runs: it fills from left to right and says
  /// what is happening. Finding photos has a percentage only when the same
  /// folder was listed before; otherwise it shows a count and a clock.
  Widget _scanProgressButton({bool inConfiguration = false}) {
    final total = _folderImagesTotal;
    final listed = total != null;
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

    final noun = _scanningVideos ? 'videos' : 'photos';
    final String label;
    final double? value;
    if (!listed) {
      value = listingFraction;
      label = listingFraction != null
          ? 'Finding $noun… ~${(listingFraction * 100).floor()}%'
          : _folderImagesFound > 0
          ? 'Finding $noun… $_folderImagesFound found · $clock'
          : 'Finding $noun… $clock';
    } else {
      final fraction = total == 0
          ? 1.0
          : (_folderImagesScanned / total).clamp(0.0, 1.0);
      value = fraction;
      label = _scanningVideos
          ? 'Comparing videos… ${(fraction * 100).floor()}% · $_folderImagesScanned of $total'
          : 'Analyzing photos… ${(fraction * 100).floor()}% · $_folderImagesScanned of $total';
    }
    return Semantics(
      label: label,
      child: ClipRRect(
        key: inConfiguration ? null : _mainScanKey,
        borderRadius: BorderRadius.circular(26),
        child: SizedBox(
          height: 52,
          child: Stack(
            fit: StackFit.expand,
            children: [
              LinearProgressIndicator(
                value: value,
                minHeight: 52,
                color: AppColors.tintBorder,
                backgroundColor: AppColors.tintStrong,
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2F3A2B),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A short "nothing found" notice in the middle of the screen. It closes
  /// by itself after a few seconds, or when the person taps OK.
  ///
  /// The scan runs from a configuration screen that closes itself when the
  /// scan finishes, so the popup is queued and opened once the home screen is
  /// showing again (a dialog opened earlier would be closed by that pop).
  void _showResultPopup(String message, {required bool found}) {
    // Results that were found open on their own screen, so no pop-up is
    // needed; only "nothing found" needs a word, and it closes by itself.
    if (found) return;
    _pendingPopup = (message: message, found: found);
    WidgetsBinding.instance.addPostFrameCallback((_) => _flushPopup());
  }

  ({String message, bool found})? _pendingPopup;

  void _flushPopup() {
    final pending = _pendingPopup;
    if (pending == null || !mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    _pendingPopup = null;
    unawaited(_openResultPopup(pending.message, found: pending.found));
  }

  Future<void> _openResultPopup(String message, {required bool found}) async {
    var open = true;
    final timer = Timer(const Duration(seconds: 4), () {
      if (open && mounted) Navigator.of(context, rootNavigator: true).maybePop();
    });
    try {
      await _resultPopupDialog(message, found: found);
    } finally {
      open = false;
      timer.cancel();
    }
  }

  Future<void> _resultPopupDialog(String message, {required bool found}) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: AppColors.tintStrong,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      found ? Icons.auto_awesome : Icons.search_off_outlined,
                      size: 32,
                      color: _green,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    found ? 'Scan complete' : 'Nothing found',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: AppColors.body,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(found ? 'View results' : 'OK'),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close, color: AppColors.body),
              ),
            ),
          ],
        ),
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
    AppMenuActions.openSettings = null;
    AppMenuActions.showPrivacy = null;
    AppMenuActions.goHome = null;
    _elapsedTimer?.cancel();
    _folderScanner.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _scanProgressRevision.dispose();
    _showTopButton.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    // The Library tab remains hidden for now; bottom destinations control the
    // media mode, Settings, and Privacy.
    body: _tab == 0 && !_scanActive && _showResultsPage
        ? AppBackground(
            child: Column(
              children: [
                _resultsTopBar(),
                Expanded(child: SafeArea(top: false, child: _resultsPage())),
              ],
            ),
          )
        : SafeArea(child: _tab == 0 ? _scanTab() : _libraryTab()),
    bottomNavigationBar: _bottomNavigationBar(),
  );

  Widget _bottomNavigationBar() => NavigationBar(
    height: 68,
    selectedIndex: _videoMode ? 1 : 0,
    onDestinationSelected: (index) {
      if (_scanActive || _importing) return;
      final settingsIndex = _videoEnabled ? 2 : 1;
      final privacyIndex = settingsIndex + 1;
      if (index == 0 || (_videoEnabled && index == 1)) {
        setState(() {
          _videoMode = index == 1;
          _showResultsPage = false;
        });
      } else if (index == settingsIndex) {
        _openSettings();
      } else if (index == privacyIndex) {
        _showPrivacy();
      }
    },
    destinations: [
      const NavigationDestination(
        icon: Icon(Icons.photo_outlined),
        selectedIcon: Icon(Icons.photo),
        label: 'Photos',
      ),
      if (_videoEnabled)
        const NavigationDestination(
          icon: Icon(Icons.videocam_outlined),
          selectedIcon: Icon(Icons.videocam),
          label: 'Videos',
        ),
      const NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: 'Settings',
      ),
      const NavigationDestination(
        icon: Icon(Icons.shield_outlined),
        label: 'Privacy',
      ),
    ],
  );

  /// Which scan results are on screen: the running scan's, otherwise the last
  /// one the user ran (or switched to).
  bool get _resultsAreBestShots =>
      _scanActive ? _scanningBestShots : _showBestResults;

  Widget _scanTab() {
    if (!_scanActive && _showResultsPage) return _resultsPage();

    final scroll = CustomScrollView(
      controller: _scrollController,
      // While a scan runs the screen is frozen; only Cancel works.
      physics: _scanActive ? const NeverScrollableScrollPhysics() : null,
      slivers: [
        if (AppColors.modern)
          SliverToBoxAdapter(
            child: IgnorePointer(ignoring: _scanActive, child: _hero()),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            sliver: SliverToBoxAdapter(
              child: IgnorePointer(ignoring: _scanActive, child: _header()),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          sliver: SliverToBoxAdapter(
            child: _scanActive
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _scanProgressButton(),
                      Padding(
                        key: _scanCancelKey,
                        padding: const EdgeInsets.only(top: 4),
                        child: TextButton.icon(
                          onPressed: _cancelRequested ? null : _cancelScan,
                          icon: const Icon(Icons.close, size: 18),
                          label: Text(
                            _cancelRequested ? 'Stopping…' : 'Cancel scan',
                          ),
                        ),
                      ),
                    ],
                  )
                : _homeFeatureSelector(),
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
          sliver: SliverToBoxAdapter(
            child: IgnorePointer(ignoring: _scanActive, child: _footer()),
          ),
        ),
      ],
    );
    return Stack(
      children: [
        // A draggable scroll bar for fast scrolling through long results.
        Scrollbar(
          controller: _scrollController,
          interactive: true,
          thickness: 6,
          child: scroll,
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: ValueListenableBuilder<bool>(
            valueListenable: _showTopButton,
            builder: (context, show, _) => AnimatedSlide(
              duration: const Duration(milliseconds: 200),
              offset: show && !_scanActive ? Offset.zero : const Offset(0, 2),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: show && !_scanActive ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !show || _scanActive,
                  child: FloatingActionButton.small(
                    heroTag: 'back-to-top',
                    tooltip: 'Back to top',
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    onPressed: () => _scrollController.animateTo(
                      0,
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOutCubic,
                    ),
                    child: const Icon(Icons.keyboard_arrow_up),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The green header of the results screen: back button, the tool's icon
  /// and its name. It also covers the status bar.
  Widget _resultsTopBar() {
    final bestShots = _resultsAreBestShots;
    final (icon, title) = _moments && bestShots
        ? (Icons.collections_outlined, 'Best Moments')
        : bestShots
        ? (Icons.photo_camera_outlined, 'Best Shots')
        : (Icons.copy_all_outlined, 'Exact Duplicates');
    return ColoredBox(
      color: AppColors.pageTop,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Expanded(
                child: DefaultTextStyle(
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                  child: AppBarTitle(icon: icon, title: title),
                ),
              ),
              IconButton(
                tooltip: 'Find in another folder or range',
                onPressed: _scanningFolder
                    ? null
                    : () => _openPhotoConfiguration(_resultsMode),
                icon: const Icon(Icons.manage_search),
              ),
              AppHomeButton(enabled: !_scanningFolder),
              const AppMenuButton(),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultsPage() {
    final bestShots = _resultsAreBestShots;
    final bothScans = _folderScan != null && _bestShotsScan != null;
    return Column(
      children: [
        if (bothScans)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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
        Expanded(
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverToBoxAdapter(
                  child: _folderScanSection(bestShots: bestShots),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _homeFeatureSelector() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!AppColors.modern) ...[
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.tint,
          border: Border.all(color: AppColors.tintBorder),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.auto_awesome_outlined,
                color: _green,
                size: 21,
              ),
            ),
            const SizedBox(width: 11),
            const Expanded(
              child: Text(
                'Discover your best memories & share with your family and friends.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: AppColors.body,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      ],
      Text(
        _videoMode ? 'Ready to free up space?' : 'Ready to tidy your memories?',
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -.4,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        _videoMode
            ? 'Explore tools for your video library.'
            : 'Choose a photo tool to start exploring your library.',
        style: const TextStyle(
          color: AppColors.hint,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 14),
      _videoMode ? _videoToolsGrid() : _toolsGrid(),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE6E8E0)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.lightbulb_outline,
                  size: 16,
                  color: Color(0xFFB78313),
                ),
                const SizedBox(width: 6),
                Text(
                  'A little inspiration',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '“Keep the best, let the rest go.”',
              style: TextStyle(
                fontSize: 16,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w700,
                color: _green,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'The PictoIQ philosophy',
              style: TextStyle(fontSize: 11, color: Color(0xFF85877F)),
            ),
          ],
        ),
      ),
      if (!Platform.isAndroid) ...[
        const SizedBox(height: 12),
        const Text(
          'Scanning albums and folders is currently available on Android.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.hint, fontSize: 12),
        ),
      ],
    ],
  );

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
            sliver: SliverToBoxAdapter(
              child: _libraryControls(duplicateGroups),
            ),
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

  Widget _header() => Column(
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
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'picto',
                    style: TextStyle(
                      color: AppColors.modern ? AppColors.heroTitle : _ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.7,
                    ),
                  ),
                  Text(
                    'iq',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.7,
                    ),
                  ),
                ],
              ),
              Text(
                'Your memories, made smarter',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.05,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const Spacer(),
        ],
      ),
    ],
  );

  /// The home header of the modern themes: logo, headline, and the library
  /// totals when access has been given.
  Widget _hero() {
    final snapshot = _librarySnapshot;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.heroTop, AppColors.heroBottom],
        ),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(AppColors.heroRadius),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
            _videoMode
                ? 'Free up space from duplicate videos.'
                : 'Make your best memories shine.',
            maxLines: 1,
            style: const TextStyle(
              fontSize: 26,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: -.5,
              color: AppColors.heroTitle,
            ),
            ),
          ),
          const SizedBox(height: 3),
          Text.rich(
            TextSpan(
              children: [
                const WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.auto_awesome,
                      size: 18,
                      color: AppColors.heroBadge,
                    ),
                  ),
                ),
                TextSpan(
                  text: _videoMode
                      ? 'Find identical copies of your videos and clear them out safely.'
                      : 'Discover your best photos, organise your gallery and find duplicate pictures effortlessly.',
                ),
              ],
            ),
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: AppColors.heroBody,
            ),
          ),
          const SizedBox(height: 14),
          if (snapshot != null) ...[
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _heroStat(_thousands(snapshot.photos), 'Photos'),
                  ),
                  if (_videoEnabled) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: _heroStat(_thousands(snapshot.videos), 'Videos'),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: _heroStat(_thousands(snapshot.albums), 'Albums'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          // Said once, below the totals, instead of taking a tile of its own.
          const Row(
            children: [
              Icon(
                Icons.lock_outline,
                size: 16,
                color: AppColors.heroStatLabel,
              ),
              SizedBox(width: 6),
              Text(
                '100% on device · nothing leaves your phone',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.heroStatLabel,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String value, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.heroStat,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.heroStatAccent,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.heroStatLabel,
          ),
        ),
      ],
    ),
  );

  // ignore: unused_element

  Widget _toolsGrid() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _toolTile(
                title: 'Best Moments',
                text: _settings.momentCount == 1
                    ? 'The best photo of each moment, to share.'
                    : 'The best ${_settings.momentCount} photos of each moment, to share.',
                chip: 'On-device AI',
                icon: Icons.collections_outlined,
                colors: AppToolColors.moments,
                mode: ScanMode.bestMoments,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _toolTile(
                title: 'Exact Duplicates',
                text: 'Find identical copies and free space.',
                chip: 'Smart scan',
                icon: Icons.copy_all_outlined,
                colors: AppToolColors.duplicates,
                mode: ScanMode.duplicates,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _toolTile(
                title: 'Best Shots',
                text: 'Keep the best photo from similar clicks.',
                chip: 'On-device AI',
                icon: Icons.photo_camera_outlined,
                colors: AppToolColors.bestShot,
                mode: ScanMode.bestShot,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _toolTile(
                title: 'Clutter',
                text: 'Find screenshots, blank and blurry photos.',
                chip: 'Smart scan',
                icon: Icons.cleaning_services_outlined,
                colors: AppToolColors.clutter,
                mode: ScanMode.clutter,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  /// The Videos tab's tools. They are previews: nothing scans yet.
  Widget _videoToolsGrid() {
    Widget tile(
      VideoTool tool,
      String title,
      String text,
      IconData icon,
      ToolCardColors colors,
    ) => _toolTile(
      title: title,
      text: text,
      chip: tool == VideoTool.exactDuplicates ? 'Smart scan' : 'Coming soon',
      icon: icon,
      colors: colors,
      highlighted: _videoTool == tool,
      onTap: () => _openVideoConfiguration(tool),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: tile(
                  VideoTool.exactDuplicates,
                  'Exact Duplicates',
                  'Find identical video copies and free space.',
                  Icons.copy_all_outlined,
                  AppToolColors.videoDuplicates,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: tile(
                  VideoTool.similarVideos,
                  'Similar Videos',
                  'Find repeated recordings of the same scene.',
                  Icons.movie_outlined,
                  AppToolColors.videoSimilar,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: tile(
                  VideoTool.bestMoments,
                  'Best Moments',
                  'Discover meaningful moments inside your videos.',
                  Icons.video_library_outlined,
                  AppToolColors.videoMoments,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: tile(
                  VideoTool.enhance,
                  'Video Enhance',
                  'Improve brightness, clarity and stability.',
                  Icons.auto_fix_high_outlined,
                  AppToolColors.videoEnhance,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// One tile of "Explore smart tools". Tapping a tile with a [mode] makes it
  /// the scan the main button runs (shown by its coloured outline); tiles
  /// without one are not available yet.
  Widget _toolTile({
    required String title,
    required String text,
    required IconData icon,
    required ToolCardColors colors,
    String? chip,
    ScanMode? mode,
    bool? highlighted,
    VoidCallback? onTap,
  }) {
    final selected = highlighted ?? (mode != null && _scanMode == mode);
    final end = colors.backgroundEnd;
    return Material(
      color: end == null ? colors.background : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: end == null ? colors.background : null,
          gradient: end == null
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colors.background, end],
                ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _scanActive
              ? null
              : onTap ??
                    (mode == null
                        ? () => _showMessage('$title is coming soon.')
                        : () {
                            _openPhotoConfiguration(mode);
                          }),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? colors.selectedBorder : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FeatureArtwork(
                  icon: icon,
                  background: colors.artBackground,
                  accent: colors.iconInk,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          title,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: colors.title,
                          ),
                        ),
                      ),
                    ),
                    if (AppColors.modern)
                      Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x1A000000),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          color: colors.iconInk,
                          size: 18,
                        ),
                      )
                    else
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: colors.iconInk,
                        size: 18,
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    color: colors.caption,
                  ),
                ),
                const SizedBox(height: 8),
                if (chip != null) ...[
                  const SizedBox(height: 8),
                  // Its own line, so the label can wrap instead of being cut.
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.chipBackground,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      chip,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: colors.chipInk,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

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
        ? (_moments ? 'best moments' : 'similar-photo groups')
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
        // What was scanned and with which filters comes first, so the rest of
        // the page is read in that context.
        _scopeStrip(scan, bestShots: bestShots, groupLabel: groupLabel),
        _resultsHeader(scan, bestShots: bestShots, groupLabel: groupLabel),
        if (bestShots && scan.duplicateGroups.isNotEmpty)
          _shareResultsActions(scan),
        if (scan.duplicateGroups.isNotEmpty &&
            !bestShots &&
            _scanRemovals(scan, bestShots: false).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton.tonalIcon(
              onPressed: _scanningFolder
                  ? null
                  : () => _deleteAllScanRemovables(bestShots: false),
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Delete all duplicates'),
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
                    ? 'Everything in this scan has been reviewed. Tap Back to home to check another folder.'
                    : bestShots
                    ? 'No similar photo groups found. PictoIQ groups visually alike shots taken close together and ranks face quality when faces are detected.'
                    : 'No exact duplicate photos found. Exact duplicates have identical file contents.',
                style: TextStyle(color: AppColors.hint),
              ),
            ),
          )
        else
          ..._resultCards(scan, bestShots: bestShots),
      ],
    );
  }

  Widget _shareResultsActions(FolderScanResult scan) => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppColors.tintBorder),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(Icons.ios_share_outlined, size: 18, color: _green),
            SizedBox(width: 8),
            Text(
              'Share your memories',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Share the selected photos, or turn them into a short video reel.',
          style: TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.body),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    _sharePhotos(_picksToShare(scan.duplicateGroups)),
                icon: const Icon(Icons.ios_share_outlined, size: 18),
                label: const Text('Share'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _green,
                  side: const BorderSide(color: AppColors.tintBorder),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _scanningFolder || _creatingReel
                    ? null
                    : () => _createPhotoReel(scan),
                icon: _creatingReel
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.movie_creation_outlined, size: 18),
                label: Text(_creatingReel ? 'Creating…' : 'Create reel'),
                style: FilledButton.styleFrom(foregroundColor: _ink),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  /// The group cards. For best shots they are organised as Event > Scene:
  /// each heading is a stretch of time (a day, an outing) and the cards below
  /// are the scenes in it where similar shots were found. Events are only for
  /// browsing; cleanup decisions are still made per scene.
  List<Widget> _resultCards(FolderScanResult scan, {required bool bestShots}) {
    final groups = [for (final group in scan.duplicateGroups) group];
    if (!bestShots) {
      return [
        for (var i = 0; i < groups.length; i++)
          _exactDuplicateCard(groups[i], i + 1),
      ];
    }
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
    // Newest event first; photos with no usable date come last.
    final dated = [
      for (final key in byEvent.keys)
        if (key < events.length && !events[key].isUndated) key,
    ]..sort((a, b) => b.compareTo(a));
    final undated = [
      for (final key in byEvent.keys)
        if (key >= events.length || events[key].isUndated) key,
    ]..sort();
    final order = [...dated, ...undated];
    int dateOf(FolderDuplicateGroup group) {
      var newest = 0;
      for (final photo in group.photos) {
        final value = trusted(photo) ? photo.capturedAt : photo.modifiedAt;
        if (value > newest) newest = value;
      }
      return newest;
    }

    final hint = Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          const Icon(
            Icons.touch_app_outlined,
            size: 16,
            color: AppColors.hint,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _moments
                  ? 'Tap a photo to enlarge it · the top moment is selected; tap the circle on the other photo to choose it instead'
                  : 'Tap a photo to enlarge it · tap its circle to keep that one',
              style: const TextStyle(fontSize: 12, color: AppColors.hint),
            ),
          ),
        ],
      ),
    );
    // Within an event, the newest group comes first.
    for (final list in byEvent.values) {
      list.sort((a, b) {
        final byDate = dateOf(b).compareTo(dateOf(a));
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
    }
    // Name the groups in the order they are shown.
    final names = <String, String>{};
    for (final key in order) {
      for (final group in byEvent[key]!) {
        names[group.id] = _groupName(group, names.length + 1);
      }
    }
    return [
      if (order.isNotEmpty) hint,
      for (final key in order) ...[
        if (headings && key < events.length)
          _eventHeader(events[key], scenes: byEvent[key]!.length),
        for (final group in byEvent[key]!)
          _folderDuplicateCard(group, names[group.id] ?? ''),
      ],
    ];
  }

  String _documentNote(FolderScanResult scan) => scan.documentsLeftOut == 0
      ? ''
      : ' ${scan.documentsLeftOut} image${scan.documentsLeftOut == 1 ? ' was' : 's were'} left out (documents, screens or objects).';

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
          style: const TextStyle(fontSize: 12, color: AppColors.body),
        ),
      ],
    ),
  );

  /// One compact card for the whole scan result, laid out top to bottom:
  /// folder and date range (with a menu), the headline numbers, any progress
  /// so far, a one-line status and the actions.
  /// How many separate events the shown moments belong to (same time-gap
  /// rule as the event headings).
  int _momentEventCount(FolderScanResult scan) {
    final photos = scan.scannedPhotos;
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
    final eventOfUri = <String, int>{
      for (var e = 0; e < events.length; e++)
        for (final index in events[e].members) photos[index].uri: e,
    };
    final used = <int>{};
    for (final group in scan.duplicateGroups) {
      var best = events.length;
      for (final photo in group.photos) {
        final e = eventOfUri[photo.uri];
        if (e != null && e < best) best = e;
      }
      used.add(best);
    }
    return used.length;
  }

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
    final reviewGroups = bestShots && !_moments
        ? _reviewQueue(scan)
        : const <FolderDuplicateGroup>[];
    final status = groups == 0
        ? (_freedBytes > 0
              ? 'All done. Nothing left to review in this scan.'
              : _noGroupsText(scan, bestShots: bestShots))
        : !bestShots
        ? 'Exact copies. Review before deleting.'
        : _moments
        ? 'Best moments are selected. Nothing is deleted from this list.'
        : ready.isEmpty
        ? 'Nothing is ready for bulk cleanup. Check each group below.'
        : 'Ready now: ${ready.length} photo${ready.length == 1 ? '' : 's'} (${_formatBytes(readyBytes)}) in confident groups.';

    Widget tile(String value, String label) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.tint,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  color: _green,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              label,
              maxLines: 2,
              style: const TextStyle(fontSize: 12, color: AppColors.body),
            ),
          ],
        ),
      ),
    );
    final headline = groups == 0
        ? (_freedBytes > 0 ? 'All done' : 'Nothing found')
        : _moments
        ? '$groups moments found'
        : bestShots
        ? '$groups similar groups found'
        : '$groups duplicate groups found';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.tintBorder),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. The headline: what was found, and what to do next.
          Text(
            headline,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            status,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: AppColors.body,
            ),
          ),
          // 2. The headline numbers.
          if (groups > 0) ...[
            const SizedBox(height: 14),
            Row(
              children: _moments
                  ? [
                      tile('${_momentEventCount(scan)}', 'events'),
                      const SizedBox(width: 8),
                      tile('$groups', 'moments'),
                      const SizedBox(width: 8),
                      tile(
                        '${scan.duplicateGroups.fold<int>(0, (total, group) => total + _momentPair(group).length)}',
                        'photos picked',
                      ),
                    ]
                  : [
                      tile(_formatBytes(potentialBytes), 'can be freed'),
                      const SizedBox(width: 8),
                      tile('${potential.length}', 'photos to remove'),
                    ],
            ),
          ],
          // 3. Actions for best shot.
          if (bestShots && !_moments && groups > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _scanningFolder
                        ? null
                        : () => _showAutoClean(scan),
                    icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
                    label: const Text('Clean up all'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _green,
                      minimumSize: const Size(0, 46),
                      side: const BorderSide(color: AppColors.tintBorder),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _scanningFolder || reviewGroups.isEmpty
                        ? null
                        : () => _showReviewMode(reviewGroups),
                    icon: const Icon(Icons.rate_review_outlined, size: 18),
                    label: const Text('Review all'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.tintStrong,
                      foregroundColor: _green,
                      minimumSize: const Size(0, 46),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
          // 4. Progress so far.
          if (_freedBytes > 0) ...[
            const SizedBox(height: 12),
            Row(
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
                      fontSize: groups == 0 ? 22 : 14,
                    ),
                  ),
                ),
                Text(
                  '$_freedPhotos photo${_freedPhotos == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.body,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// What was scanned (folder and dates), shown right above the results it
  /// produced, with the scan's menu.
  Widget _scopeStrip(
    FolderScanResult scan, {
    required bool bestShots,
    required String groupLabel,
  }) {
    final category = _moments && bestShots
        ? SettingsCategory.bestMoments
        : bestShots
        ? SettingsCategory.bestShot
        : SettingsCategory.duplicates;
    void viewFiles() => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScannedFilesPage(
          scan: scan,
          loadPreview: _folderScanner.loadPreview,
        ),
      ),
    );
    return ScanScopeCard(
      margin: const EdgeInsets.only(bottom: 10),
      folder: scan.folderName,
      range: scan.rangeDescription,
      counts:
          '${scan.imagesScanned} photos scanned · ${scan.duplicateGroups.length} $groupLabel',
      scannedLine: '${scan.imagesScanned} of ${scan.imageFilesFound} photos',
      category: category,
      settings: _settings,
      scannedWith: _resultsScanSettings ?? _settings,
      onChanged: _updateSettings,
      onFindAgain: () => _openPhotoConfiguration(_resultsMode),
      onViewFiles: viewFiles,
      menu: PopupMenuButton<String>(
        tooltip: 'More',
        padding: EdgeInsets.zero,
        onSelected: (value) {
          if (value == 'files') {
            viewFiles();
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
          const PopupMenuItem(value: 'details', child: Text('About this scan')),
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
      color: AppColors.tint,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      'Estimated space to recover: up to ${_formatBytes(bytes)}',
      style: const TextStyle(fontWeight: FontWeight.w700, color: _green),
    ),
  );

  Widget _exactDuplicateCard(FolderDuplicateGroup group, int number) {
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
              'Set $number · ${group.photos.length} identical photos',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            const Text(
              'Tap a thumbnail to inspect it before deleting copies.',
              style: TextStyle(fontSize: 11, color: AppColors.hint),
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
                    _exactDuplicateThumbnail(photo, group.oldestFirst),
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

  Widget _exactDuplicateThumbnail(
    FolderScanPhoto photo,
    List<FolderScanPhoto> among,
  ) {
    final preview = photo.previewBytes;
    return Tooltip(
      message: preview == null ? 'Preview unavailable' : 'Tap to enlarge',
      child: InkWell(
        onTap: () => _showExactPhotoPreview(photo, among: among),
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

  /// Opens the full-screen viewer on [photo]. When [among] is given the person
  /// can swipe to the other photos of the same group.
  Future<void> _showExactPhotoPreview(
    FolderScanPhoto photo, {
    List<FolderScanPhoto>? among,
  }) {
    var list = among ?? [photo];
    var index = list.indexWhere((p) => p.uri == photo.uri);
    if (index < 0) {
      list = [photo];
      index = 0;
    }
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => PhotoViewerPage(
          initialIndex: index,
          photos: [
            for (final item in list)
              ViewerPhoto(
                title: item.relativePath,
                preview: item.previewBytes,
                loadLarge: () => _folderScanner.loadLargePreview(item.uri),
              ),
          ],
        ),
      ),
    );
  }

  Widget _confidenceChip(SimilarityEvidence evidence) {
    final (color, background) = switch (evidence.confidence) {
      SimilarityConfidence.high => (_green, AppColors.tint),
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

  Widget _folderDuplicateCard(FolderDuplicateGroup group, String name) {
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
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                    ),
                    Tooltip(
              message: _moments
                  ? 'Hide this moment from the results'
                  : 'Skip this group: all its photos stay and nothing is deleted',
              child: TextButton.icon(
                onPressed: _scanningFolder ? null : () => _skipGroup(group),
                icon: Icon(
                  Icons.close_rounded,
                  size: 14,
                ),
                label: Text(_moments ? 'Skip moment' : 'Skip group'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.body,
                  backgroundColor: Colors.white.withValues(alpha: .94),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 30),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_moments)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 2),
                    child: Text(
                      'Selected from ${group.photos.length} photos in this moment',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.body,
                      ),
                    ),
                  ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final count = group.photos.length;
                    final columns = _moments
                        ? (_momentPair(group).length < 2
                              ? 2
                              : _momentPair(group).length)
                        : (count >= 9 ? 5 : 4);
                    const gap = 8.0;
                    final width =
                        ((constraints.maxWidth - gap * (columns - 1)) / columns)
                            .floorToDouble();
                    return Wrap(
                      alignment: WrapAlignment.start,
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final photo
                            in _moments ? _momentPair(group) : group.bestFirst)
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
        ],
      ),
    );
  }

  /// Keeps every photo in a group by removing it from cleanup review.
  void _skipGroup(FolderDuplicateGroup group) {
    final scan = _bestShotsScan;
    if (scan == null) return;
    final updated = scan.withoutGroup(group.id);
    setState(() => _bestShotsScan = updated);
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final undoBar = messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: Text(
          _moments
              ? 'Moment skipped.'
              : 'Group skipped. All its photos stay.',
        ),
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
    Future.delayed(const Duration(seconds: 4), undoBar.close);
  }

  /// The clean-up button. In a two-photo group it sits in the free third
  /// slot beside the photos; otherwise it spans the row below them.
  /// Compare and the keep button, in one row under the photos of every group.
  Widget _cardActions(FolderDuplicateGroup group, KeepDecision decision) {
    // The match tag (Same shot / Similar / Check) is hidden for now; bring it
    // back with _confidenceChip(group.evidence!).
    final compare = IconButton.filledTonal(
      tooltip: 'Details',
      onPressed: () => _showCompareShots(group),
      icon: const Icon(Icons.fact_check_outlined, size: 20),
      color: _ink,
    );
    final Widget keep;
    if (_moments) {
      // Nothing is deleted from best moments, so there is no keep button.
      keep = const SizedBox.shrink();
    } else if (!decision.hasDecision) {
      keep = const Text(
        'Choose the photo to keep.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: AppColors.hint),
      );
    } else {
      final word = decision.isUserChoice
          ? (decision.keepIds.length > 1 ? 'Keep my picks' : 'Keep my pick')
          : 'Keep best';
      final size =
          'Save ${_formatBytes(_groupRecoveryBytes(group, bestShots: true))}';
      keep = Tooltip(
        message: '$word, delete the rest',
        child: FilledButton.tonalIcon(
          onPressed: _scanningFolder ? null : () => _deleteSimilarShots(group),
          icon: const Icon(Icons.delete_sweep_outlined, size: 20),
          label: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(size, maxLines: 1),
          ),
          style: FilledButton.styleFrom(
            foregroundColor: _ink,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
      );
    }
    return Row(
      children: [
        if (decision.hasDecision && _resultsAreBestShots) ...[
          IconButton.filledTonal(
            tooltip: decision.keepIds.length > 1
                ? 'Share the kept photos'
                : 'Share the kept photo',
            onPressed: () => _sharePhotos(_picksToShare([group])),
            icon: const Icon(Icons.ios_share_outlined, size: 20),
            color: _green,
          ),
          const SizedBox(width: 8),
        ],
        compare,
        const SizedBox(width: 8),
        Expanded(child: keep),
      ],
    );
  }

  /// Every group, safest first: the order review mode
  /// steps through.
  List<FolderDuplicateGroup> _reviewQueue(FolderScanResult scan) {
    final groups = [for (final group in scan.duplicateGroups) group];
    groups.sort((a, b) {
      final byConfidence = (a.evidence?.confidence.index ?? 3).compareTo(
        b.evidence?.confidence.index ?? 3,
      );
      return byConfidence != 0 ? byConfidence : a.id.compareTo(b.id);
    });
    return groups;
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
              return AppScaffold(
                appBar: AppBar(
                  title: const Text('Review finished'),
                  leading: const AppBackButton(),
                  leadingWidth: appBackButtonWidth,
                  actions: const [AppMenuButton()],
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
                            color: AppColors.hint,
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
            return AppScaffold(
              appBar: AppBar(
                title: Text('Review ${index + 1} of ${queue.length}'),
                leading: const AppBackButton(),
                leadingWidth: appBackButtonWidth,
                actions: const [AppMenuButton()],
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
                      style: TextStyle(fontSize: 12, color: AppColors.hint),
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
                          color: AppColors.body,
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
                'You reviewed ${groups.length} group${groups.length == 1 ? '' : 's'}. PictoIQ keeps the photo(s) you chose in each and deletes the others from "${scan.folderName}". This cannot be undone.',
              ),
              const SizedBox(height: 10),
              _recoveryEstimate(bytes),
              const SizedBox(height: 10),
              for (final photo in remove.take(8))
                Text(photo.relativePath, style: const TextStyle(fontSize: 12)),
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
    final momentRank = _moments
        ? _momentPair(group).indexWhere((p) => p.uri == photo.uri)
        : -1;
    final badge = _moments
        ? (momentRank == 0
              ? (width < 90 ? 'BEST' : 'BEST MOMENT')
              : momentRank == 1
              ? (width < 90 ? '2ND' : '2ND BEST')
              : (width < 90 ? '3RD' : '3RD BEST'))
        : selected
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
              onTap: () => _showExactPhotoPreview(
                photo,
                among: _moments ? _momentPair(group) : group.bestFirst,
              ),
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
                message: _moments
                    ? (selected ? 'Selected for sharing' : 'Select for sharing')
                    : (selected
                          ? (_multiKeep && keepIds.length > 1
                                ? 'Tap to remove from the photos to keep'
                                : 'This photo will be kept')
                          : (_multiKeep
                                ? 'Also keep this photo'
                                : 'Keep this photo')),
                child: InkResponse(
                  onTap: selected && !(_multiKeep && keepIds.length > 1)
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
                        color: selected ? _green : AppColors.hint,
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
    if (_multiKeep) {
      // Best shot, "multiple" mode: add or remove this photo from the set to
      // keep. Until the user chooses, the set is PictoIQ's own pick, so the
      // first tap adds to it instead of replacing it.
      final decision = _decisionFor(group, bestShots: true);
      final keep = {...decision.keepIds};
      if (!decision.isUserChoice) {
        keep.add(uri);
      } else if (keep.contains(uri)) {
        if (keep.length <= 1) return; // a group always keeps one photo
        keep.remove(uri);
      } else {
        keep.add(uri);
      }
      setState(() {
        for (final photo in group.photos) {
          _photoRatings[photo.uri] = keep.contains(photo.uri) ? 1 : 0;
        }
      });
      return;
    }
    if (_moments) {
      // Best moments: exactly one of the two photos is selected for sharing.
      setState(() {
        for (final photo in _momentPair(group)) {
          _photoRatings[photo.uri] = photo.uri == uri ? 1 : 0;
        }
      });
      return;
    }
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
                  'Details · ${group.photos.length} similar photos',
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
                        color: AppColors.hint,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  ranking == null
                      ? 'No ranking is available for this group.'
                      : '${ranking.headline}. Scores compare these photos with each other only; they are not a rating of the photo itself.',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.hint,
                  ),
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
              line(Icons.error_outline, const Color(0xFFB37957), reason),
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
                    label: Text(
                      'Your pick · save ${_formatBytes(saves)} · undo',
                    ),
                  )
                : FilledButton.tonal(
                    onPressed: () {
                      _chooseKeeper(group, photo.uri);
                      setDialogState(() {});
                    },
                    child: Text(
                      '${_multiKeep ? 'Also keep this' : 'Keep this'} · save ${_formatBytes(saves)}',
                    ),
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

  Future<void> _openSettings() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => SettingsPage(
        initial: _settings,
        onChanged: _updateSettings,
        showVideoSettings: _videoEnabled,
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
  final what = bestShots
      ? 'No similar shots found.'
      : 'No exact duplicates found.';
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
  if (mb < 1024) return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(gb >= 100 ? 0 : 1)} GB';
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
