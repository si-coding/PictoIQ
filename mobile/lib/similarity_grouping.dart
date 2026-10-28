import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Where a capture time came from. Times from different sources are never
/// compared with each other, because EXIF stores local wall-clock time while
/// the file's modified time is a real instant.
abstract final class CaptureSource {
  static const unknown = 0;
  static const exif = 1;
  static const modified = 2;

  /// Only the day is known (from a file name such as `IMG-20221109-WA0007`).
  /// Same-day photos are not treated as shot at the same moment.
  static const day = 3;
}

/// Number of differing bits between two 64-bit hashes.
int hammingDistance(int left, int right) {
  var x = left ^ right;
  x = x - ((x >>> 1) & 0x5555555555555555);
  x = (x & 0x3333333333333333) + ((x >>> 2) & 0x3333333333333333);
  x = (x + (x >>> 4)) & 0x0f0f0f0f0f0f0f0f;
  return (x * 0x0101010101010101) >>> 56;
}

/// 64-bit difference hash: each bit records whether a pixel is brighter than
/// its right-hand neighbour in a 9x8 downscale. It reacts to structure rather
/// than overall brightness, so it separates different scenes better than an
/// average hash while still matching near-identical burst frames.
int differenceHash(img.Image image) {
  final small = img.copyResize(
    image,
    width: 9,
    height: 8,
    interpolation: img.Interpolation.average,
  );
  int luminance(int x, int y) {
    final pixel = small.getPixel(x, y);
    return (pixel.r.toInt() * 299 +
            pixel.g.toInt() * 587 +
            pixel.b.toInt() * 114) ~/
        1000;
  }

  var hash = 0;
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      hash = (hash << 1) | (luminance(x, y) > luminance(x + 1, y) ? 1 : 0);
    }
  }
  return hash;
}

/// Number of colour bins in a [colorHistogram] (4 levels per channel).
const colorHistogramBins = 64;

/// Coarse colour profile of [image]: the share of pixels in each of 64 colour
/// bins. It ignores where things are in the picture, so it survives small
/// camera movements, zoom and people shifting position, which the structure
/// hash [differenceHash] does not.
List<double> colorHistogram(img.Image image) {
  final small = img.copyResize(
    image,
    width: 64,
    height: 64,
    interpolation: img.Interpolation.average,
  );
  final counts = List<double>.filled(colorHistogramBins, 0);
  for (var y = 0; y < small.height; y++) {
    for (var x = 0; x < small.width; x++) {
      final pixel = small.getPixel(x, y);
      final r = math.min(255, math.max(0, pixel.r.toInt())) >> 6;
      final g = math.min(255, math.max(0, pixel.g.toInt())) >> 6;
      final b = math.min(255, math.max(0, pixel.b.toInt())) >> 6;
      counts[(r << 4) | (g << 2) | b] += 1;
    }
  }
  final total = small.width * small.height;
  return [for (final count in counts) count / total];
}

/// How different two colour profiles are: 0 for the same, towards 1 for
/// nothing in common (one minus the Bhattacharyya coefficient).
double histogramDistance(List<double> a, List<double> b) {
  var overlap = 0.0;
  final length = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    overlap += math.sqrt(a[i] * b[i]);
  }
  return (1 - overlap).clamp(0.0, 1.0).toDouble();
}

/// A histogram (same 64 colour bins as [colorHistogram]) of the pixels of an
/// RGBA image inside the box [left, top, right, bottom], sampled so that at
/// most about 2,500 pixels are read. Null when the box has no pixels.
List<double>? regionHistogram(
  List<int> rgba,
  int width,
  int height,
  int left,
  int top,
  int right,
  int bottom,
) {
  final x0 = math.max(0, left);
  final y0 = math.max(0, top);
  final x1 = math.min(width, right);
  final y1 = math.min(height, bottom);
  if (x1 <= x0 || y1 <= y0 || rgba.length < width * height * 4) return null;
  final area = (x1 - x0) * (y1 - y0);
  final step = math.max(1, math.sqrt(area / 2500).ceil());
  final counts = List<double>.filled(colorHistogramBins, 0);
  var total = 0;
  for (var y = y0; y < y1; y += step) {
    for (var x = x0; x < x1; x += step) {
      final offset = (y * width + x) * 4;
      final r = rgba[offset] >> 6;
      final g = rgba[offset + 1] >> 6;
      final b = rgba[offset + 2] >> 6;
      counts[(r << 4) | (g << 2) | b] += 1;
      total += 1;
    }
  }
  if (total == 0) return null;
  return [for (final count in counts) count / total];
}

/// True for pages of text, forms, receipts and similar: almost all pixels
/// are grey or white and most are bright. A heuristic, so a pale snowy photo
/// could be mistaken for one; callers also check that no faces were found.
bool looksLikeDocument(img.Image image) {
  final small = img.copyResize(
    image,
    width: 48,
    height: 48,
    interpolation: img.Interpolation.average,
  );
  var neutral = 0;
  var bright = 0;
  for (var y = 0; y < small.height; y++) {
    for (var x = 0; x < small.width; x++) {
      final pixel = small.getPixel(x, y);
      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();
      if (math.max(r, math.max(g, b)) - math.min(r, math.min(g, b)) <= 40) {
        neutral += 1;
        if ((r * 299 + g * 587 + b * 114) ~/ 1000 >= 160) bright += 1;
      }
    }
  }
  const total = 48 * 48;
  return neutral / total >= 0.9 && bright / total >= 0.6;
}

/// Brightness on a 24 x 24 grid (0-1), a finer view than [colorLayout] so two
/// pages with different text can be told apart.
List<double> documentDetail(img.Image image) {
  final small = img.copyResize(
    image,
    width: 24,
    height: 24,
    interpolation: img.Interpolation.average,
  );
  return [
    for (var y = 0; y < small.height; y++)
      for (var x = 0; x < small.width; x++)
        (small.getPixel(x, y).r * 0.299 +
                small.getPixel(x, y).g * 0.587 +
                small.getPixel(x, y).b * 0.114) /
            255,
  ];
}

/// Grid size of a [colorLayout] (6 x 6 cells, 3 channels each).
const colorLayoutSize = 6;

/// Where the colours are: the average colour of each cell of a 6 x 6 grid,
/// scaled to 0-1. Unlike [colorHistogram] it keeps position, so it tells a
/// beach background from a restaurant even when both contain the same people
/// in dark clothes.
List<double> colorLayout(img.Image image) {
  final small = img.copyResize(
    image,
    width: colorLayoutSize,
    height: colorLayoutSize,
    interpolation: img.Interpolation.average,
  );
  final values = <double>[];
  for (var y = 0; y < small.height; y++) {
    for (var x = 0; x < small.width; x++) {
      final pixel = small.getPixel(x, y);
      values
        ..add(pixel.r / 255)
        ..add(pixel.g / 255)
        ..add(pixel.b / 255);
    }
  }
  return values;
}

/// Mean absolute difference between two [colorLayout]s: 0 for the same
/// arrangement of colours, towards 1 for opposite.
double layoutDistance(List<double> a, List<double> b) {
  final length = math.min(a.length, b.length);
  if (length == 0) return 1;
  var total = 0.0;
  for (var i = 0; i < length; i++) {
    total += (a[i] - b[i]).abs();
  }
  return total / length;
}

/// The date (and time, when present) written in a file name such as
/// `IMG-20221109-WA0007.jpg`, `IMG_20221109_123456.jpg` or
/// `PXL_20221109_123456789.jpg`. Returns the date, the time of day in
/// seconds, or null seconds when only the date is given; null when the name
/// has no plausible date.
(DateTime, int?)? fileNameDate(String name) {
  final match = RegExp(
    r'(?<!\d)((?:19|20)\d{2})(\d{2})(\d{2})(?:[_-]?(\d{2})(\d{2})(\d{2}))?',
  ).firstMatch(name);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (year < 1990 || year > 2100 || month < 1 || month > 12) return null;
  if (day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  if (date.month != month) return null;
  final hour = match.group(4);
  if (hour == null) return (date, null);
  final h = int.parse(hour);
  final m = int.parse(match.group(5)!);
  final sec = int.parse(match.group(6)!);
  if (h > 23 || m > 59 || sec > 59) return (date, null);
  return (date, h * 3600 + m * 60 + sec);
}

/// When the photo was taken, as (milliseconds, [CaptureSource]): EXIF capture
/// time when present; otherwise the file's modified time, unless the file
/// name shows a different day (a bulk copy or download resets modified times,
/// and trusting it would make photos from different years look simultaneous);
/// otherwise the date in the file name; otherwise unknown.
(int, int) captureTimeOf(img.Image image, int modifiedAt, {String? fileName}) {
  try {
    if (image.hasExif) {
      final raw = image.exif.exifIfd[0x9003]?.toString().trim();
      final match = raw == null
          ? null
          : RegExp(
              r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})',
            ).firstMatch(raw);
      if (match != null) {
        final year = int.parse(match.group(1)!);
        final month = int.parse(match.group(2)!);
        final day = int.parse(match.group(3)!);
        if (year >= 1990 && month >= 1 && month <= 12 && day >= 1) {
          final time = DateTime(
            year,
            month,
            day,
            int.parse(match.group(4)!),
            int.parse(match.group(5)!),
            int.parse(match.group(6)!),
          );
          return (time.millisecondsSinceEpoch, CaptureSource.exif);
        }
      }
    }
  } catch (_) {
    // Fall back to the file's modified time below.
  }
  final named = fileName == null ? null : fileNameDate(fileName);
  if (named != null) {
    final (date, seconds) = named;
    // A time in the name was written by the camera at capture; file dates
    // change when files are copied, so the name is the better witness.
    if (seconds != null) {
      return (
        date.millisecondsSinceEpoch + seconds * 1000,
        CaptureSource.exif,
      );
    }
    final modifiedAgrees =
        modifiedAt > 0 &&
        (DateTime.fromMillisecondsSinceEpoch(modifiedAt)
                    .difference(date)
                    .inHours
                    .abs() <=
                48);
    if (!modifiedAgrees) {
      return (date.millisecondsSinceEpoch, CaptureSource.day);
    }
  }
  if (modifiedAt > 0) return (modifiedAt, CaptureSource.modified);
  return (0, CaptureSource.unknown);
}

/// How readily the scan groups photos. Stricter finds fewer, safer groups;
/// looser finds more groups but may put different scenes together.
enum MatchLevel {
  strict(
    'Strict',
    'Only near-identical pictures. Fewest groups, safest for cleanup.',
  ),
  balanced(
    'Balanced',
    'Same background and framing, including small camera movement.',
  ),
  loose(
    'Loose',
    'Also groups shots with moved poses or framing. More groups; review them before deleting.',
  );

  const MatchLevel(this.label, this.description);

  final String label;
  final String description;
}

/// Whether, and how, capture time takes part in grouping.
enum TimeMode {
  off(
    'Ignore',
    'Only the pictures matter. Best when files were copied from elsewhere.',
  ),
  hint(
    'Hint',
    'Pictures decide. Photos with a reliable camera time (EXIF, or a time in the file name) taken within about 10 seconds also group when their colours match, even if people moved or the framing changed.',
  ),
  moment(
    'Moment',
    'Photos must also be taken within about 30 seconds of each other.',
  ),
  session(
    'Session',
    'Photos must also be taken within about 10 minutes of each other.',
  );

  const TimeMode(this.label, this.description);

  final String label;
  final String description;
}

/// What to do with pages of text, receipts and similar document images.
enum DocumentMode {
  leaveOut(
    'Leave out',
    'Documents are not grouped or offered for deletion at all.',
  ),
  strict(
    'Compare strictly',
    'Documents are grouped only when they are near-identical copies of the same page.',
  );

  const DocumentMode(this.label, this.description);

  final String label;
  final String description;
}

/// Tunable limits for similar-photo grouping and its confidence levels.
///
/// The defaults are starting points. Measure them on a labelled photo set
/// (see `test/similarity_evaluation_test.dart`) before trusting them.
class SimilarityThresholds {
  const SimilarityThresholds({
    this.maxLinkDistance = 10,
    this.windowMs = 30 * 1000,
    this.highDistance = 4,
    this.highSpanMs = 10 * 1000,
    this.mediumDistance = 8,
    this.maxClusterForDiameter = 300,
    this.isSession = false,
    this.burstGapMs = 8 * 1000,
    this.burstHashDistance = 14,
    this.burstColorDistance = 0.25,
    this.maxFaceCountDifference = 2,
    this.useCaptureTime = true,
    this.layoutLinkDistance = 0.10,
    this.shiftHashDistance = 20,
    this.shiftLayoutDistance = 0.07,
    this.noLayoutHashDistance = 6,
    this.highLayoutDistance = 0.04,
    this.mediumLayoutDistance = 0.12,
    this.maxSubjectDistance = 1.0,
    this.documentHashDistance = 4,
    this.documentDetailDistance = 0.02,
    this.histLinkDistance = 0,
    this.histLayoutDistance = 0,
    this.histHashDistance = 32,
    this.trustedGapMs = 0,
    this.trustedColorDistance = 0.25,
    this.trustedLayoutDistance = 0.16,
  });

  /// Groups photos by what is in them, ignoring when they were taken or
  /// modified. Files are copied between folders and devices, so their dates
  /// say little about the scene. Two photos are linked when their structure
  /// hashes are close and their colour layouts match ([maxLinkDistance] with
  /// [layoutLinkDistance]), or when the colour layout matches very closely
  /// even though framing shifted ([shiftHashDistance] with
  /// [shiftLayoutDistance]). All limits are untuned starting points.
  static const content = SimilarityThresholds(
    useCaptureTime: false,
    maxLinkDistance: 10,
    highDistance: 4,
    mediumDistance: 20,
  );

  /// Thresholds for a user-chosen [level] and [timeMode]. With the time mode
  /// off they are content-only; otherwise photos must also be close in time. With [splitByPeople]
  /// off, photos are grouped whatever the number of faces in them. All values
  /// are untuned starting points.
  factory SimilarityThresholds.forLevel(
    MatchLevel level, {
    bool splitByPeople = true,
    TimeMode timeMode = TimeMode.off,
  }) {
    final faces = splitByPeople ? 2 : 1000;
    if (timeMode == TimeMode.moment) {
      return switch (level) {
        MatchLevel.strict => SimilarityThresholds(
          maxLinkDistance: 8,
          burstHashDistance: 10,
          burstColorDistance: 0.15,
          maxFaceCountDifference: faces,
        ),
        MatchLevel.balanced => SimilarityThresholds(
          maxFaceCountDifference: faces,
        ),
        MatchLevel.loose => SimilarityThresholds(
          maxLinkDistance: 12,
          windowMs: 60 * 1000,
          burstHashDistance: 16,
          burstColorDistance: 0.3,
          maxFaceCountDifference: faces,
        ),
      };
    }
    if (timeMode == TimeMode.session) {
      final link = switch (level) {
        MatchLevel.strict => 14,
        MatchLevel.balanced => 18,
        MatchLevel.loose => 22,
      };
      return SimilarityThresholds(
        maxLinkDistance: link,
        windowMs: 10 * 60 * 1000,
        highDistance: -1,
        highSpanMs: 0,
        mediumDistance: link + 8,
        isSession: true,
        maxFaceCountDifference: faces,
      );
    }
    return switch (level) {
      MatchLevel.strict => SimilarityThresholds(
        useCaptureTime: false,
        maxLinkDistance: 8,
        layoutLinkDistance: 0.06,
        shiftHashDistance: 14,
        shiftLayoutDistance: 0.04,
        highDistance: 4,
        mediumDistance: 14,
        mediumLayoutDistance: 0.09,
        maxFaceCountDifference: faces,
        maxSubjectDistance: splitByPeople ? 0.12 : 1.0,
        histLinkDistance: 0.03,
        histLayoutDistance: 0.07,
        trustedGapMs: timeMode == TimeMode.hint ? 10 * 1000 : 0,
        trustedColorDistance: 0.15,
        trustedLayoutDistance: 0.10,
      ),
      MatchLevel.balanced => SimilarityThresholds(
        useCaptureTime: false,
        maxLinkDistance: 10,
        highDistance: 4,
        mediumDistance: 20,
        maxFaceCountDifference: faces,
        maxSubjectDistance: splitByPeople ? 0.18 : 1.0,
        histLinkDistance: 0.05,
        histLayoutDistance: 0.10,
        trustedGapMs: timeMode == TimeMode.hint ? 10 * 1000 : 0,
        trustedColorDistance: 0.25,
        trustedLayoutDistance: 0.16,
      ),
      MatchLevel.loose => SimilarityThresholds(
        useCaptureTime: false,
        maxLinkDistance: 12,
        layoutLinkDistance: 0.14,
        shiftHashDistance: 24,
        shiftLayoutDistance: 0.10,
        highDistance: 4,
        mediumDistance: 26,
        mediumLayoutDistance: 0.16,
        maxFaceCountDifference: faces,
        maxSubjectDistance: splitByPeople ? 0.32 : 1.0,
        histLinkDistance: 0.08,
        histLayoutDistance: 0.13,
        trustedGapMs: timeMode == TimeMode.hint ? 10 * 1000 : 0,
        trustedColorDistance: 0.30,
        trustedLayoutDistance: 0.22,
      ),
    };
  }

  /// Content mode: photos whose main person's clothing colours differ by
  /// more than this (see [histogramDistance]) are never grouped. 1.0 turns
  /// the check off. A weak stand-in for telling people apart.
  final double maxSubjectDistance;

  /// Content mode: a pair also links when its position-free colour profiles
  /// match within [histLinkDistance] and its colour layouts within
  /// [histLayoutDistance], whatever the structure hash (up to
  /// [histHashDistance]). This catches people who moved or a camera that
  /// zoomed, which change the hash but not the colours. 0 turns it off.
  final double histLinkDistance;
  final double histLayoutDistance;
  final int histHashDistance;

  /// Content mode, [TimeMode.hint]: photos with a reliable capture time
  /// (EXIF or a time in the file name) within this many milliseconds link
  /// when their colour profiles differ by at most [trustedColorDistance].
  /// 0 turns it off.
  final int trustedGapMs;
  final double trustedColorDistance;

  /// ...and their colour layouts by at most this much, so two different
  /// places saved in the same second (an app export, a carousel) do not link.
  final double trustedLayoutDistance;

  /// Content mode, document images: both limits must hold for a link.
  final int documentHashDistance;
  final double documentDetailDistance;

  /// When false, capture and modified times play no part in grouping.
  final bool useCaptureTime;

  /// Content mode: largest colour-layout difference for a close hash match.
  final double layoutLinkDistance;

  /// Content mode: largest hash difference for the shifted-framing match...
  final int shiftHashDistance;

  /// ...which also needs a colour layout at least this close.
  final double shiftLayoutDistance;

  /// Content mode, photos without a colour layout: hash-only limit.
  final int noLayoutHashDistance;

  /// Content mode: a group is High only when its colour layouts all differ by
  /// at most this much (and the hashes by at most [highDistance])...
  final double highLayoutDistance;

  /// ...and is Low when any pair differs by more than this.
  final double mediumLayoutDistance;

  /// Looser grouping for "same session" photos: the same people and place
  /// over several minutes, where poses differ. Groups are never rated High,
  /// because look-alike photos minutes apart are not duplicates, and the hash
  /// distances are untuned starting points.
  static const session = SimilarityThresholds(
    maxLinkDistance: 18,
    windowMs: 10 * 60 * 1000,
    highDistance: -1,
    highSpanMs: 0,
    mediumDistance: 26,
    isSession: true,
  );

  /// Photos whose face counts differ by this many or more are never linked
  /// (a couple and a family are different scenes, whatever the background).
  /// Only applies when face detection ran for both photos.
  final int maxFaceCountDifference;

  /// True for the looser session settings, so the UI can say so.
  final bool isSession;

  /// Photos taken within this many milliseconds of each other are almost
  /// certainly the same moment (a burst, or a few quick shots), so they are
  /// linked on a looser test: a hash difference up to [burstHashDistance], or
  /// a colour difference up to [burstColorDistance]. Small camera movement
  /// changes the structure hash a lot but barely changes the colours.
  final int burstGapMs;
  final int burstHashDistance;

  /// Colour difference (see [histogramDistance]) allowed within the burst gap.
  final double burstColorDistance;

  /// Two photos may be linked when their hashes differ by at most this many
  /// bits (out of 64).
  final int maxLinkDistance;

  /// Photos with a known capture time are only linked when taken within this
  /// many milliseconds of each other.
  final int windowMs;

  /// A group is "high" confidence only when every pair differs by at most
  /// this many bits...
  final int highDistance;

  /// ...and the whole group was taken within this many milliseconds, and the
  /// capture time comes from EXIF.
  final int highSpanMs;

  /// Above this pairwise difference a group is always "low" confidence.
  final int mediumDistance;

  /// Groups larger than this are not measured pair by pair and are treated as
  /// low confidence.
  final int maxClusterForDiameter;
}

enum SimilarityConfidence {
  high('High'),
  medium('Medium'),
  low('Low');

  const SimilarityConfidence(this.label);

  final String label;
}

/// Why a group was given its confidence level.
class SimilarityEvidence {
  const SimilarityEvidence({
    required this.confidence,
    required this.maxDistance,
    required this.spanMs,
    required this.captureSource,
    required this.size,
    this.isSession = false,
    this.maxColorDistance,
    this.byContent = false,
    this.maxLayoutDistance,
  });

  /// True when the group was formed from picture content alone, with no
  /// capture times involved.
  final bool byContent;

  /// Largest colour-layout difference between any two photos (0-1), or null.
  final double? maxLayoutDistance;

  /// Colour differences up to this count as "the same scene" in the UI and
  /// keep a quick burst at medium confidence even when the hash differs.
  static const sameSceneColor = 0.1;

  final SimilarityConfidence confidence;

  /// Largest colour difference between any two photos in the group (0-1), or
  /// null when colour profiles were not available.
  final double? maxColorDistance;

  /// True when the group came from the looser same-session settings.
  final bool isSession;

  /// Largest hash difference between any two photos in the group (0-64).
  final int maxDistance;

  /// Time between the first and last photo, or null when no capture time is
  /// available.
  final int? spanMs;

  final int captureSource;
  final int size;

  /// Plain-language facts behind the confidence level, for the UI.
  List<String> get notes {
    if (byContent) {
      final layout = maxLayoutDistance;
      return [
        maxDistance <= 4
            ? 'Nearly identical pictures'
            : 'Similar pictures (up to $maxDistance of 64 structure differences'
                  '${layout == null ? '' : ', colour layout ${(layout * 100).round()}% apart'})',
        'Grouped by what is in the pictures, not by when they were taken',
      ];
    }
    final sameColors =
        maxColorDistance != null && maxColorDistance! <= sameSceneColor;
    final content = maxDistance <= 4
        ? 'Nearly identical content'
        : (maxDistance <= 8
              ? 'Very similar content'
              : (sameColors
                    ? 'Same scene, framing differs'
                    : 'Loosely similar content'));
    final result = <String>[
      if (isSession) 'Same session: poses and framing may differ',
      '$content (up to $maxDistance of 64 differences)',
    ];
    final span = spanMs;
    if (span == null) {
      result.add('No capture time, so grouping relied on appearance only');
    } else {
      final seconds = (span / 1000).ceil();
      final basis = captureSource == CaptureSource.exif
          ? 'camera time'
          : 'file time, less reliable';
      result.add(
        seconds <= 0
            ? 'Taken at the same moment ($basis)'
            : 'Taken within $seconds s ($basis)',
      );
    }
    return result;
  }
}

/// What the grouping step needs to know about one photo.
class SimilarityCandidate {
  const SimilarityCandidate({
    required this.visualHash,
    required this.capturedAt,
    required this.captureSource,
    required this.tieBreaker,
    this.colorHistogram,
    this.faceCount,
    this.colorLayout,
    this.subjectColors,
    this.personColors,
    this.isDocument = false,
    this.documentDetail,
  });

  /// Colours of the main person's clothing (see [regionHistogram]), or null.
  final List<double>? subjectColors;

  /// Clothing colours of up to four faces (see [FaceSignals.personColors]).
  final List<List<double>>? personColors;

  /// Everyone's clothing, from [personColors] or the single [subjectColors].
  List<List<double>>? get people =>
      personColors ?? (subjectColors == null ? null : [subjectColors!]);

  /// True for document-like images; they only link to each other, strictly.
  final bool isDocument;

  /// Fine brightness grid for [isDocument] images.
  final List<double>? documentDetail;

  /// Colour arrangement from [colorLayout], when available.
  final List<double>? colorLayout;

  /// Number of faces found, or null when face detection did not run. Photos
  /// with clearly different numbers of people are different scenes.
  final int? faceCount;

  /// Colour profile from [colorHistogram], when available.
  final List<double>? colorHistogram;

  final int visualHash;
  final int capturedAt;
  final int captureSource;

  /// Stable ordering key for photos with identical timestamps (for example
  /// the relative path), so results do not depend on file order.
  final String tieBreaker;
}

class SimilarityCluster {
  const SimilarityCluster({required this.members, required this.evidence});

  /// Indexes into the candidate list passed to [clusterSimilar], in capture
  /// order.
  final List<int> members;
  final SimilarityEvidence evidence;
}

/// Groups visually similar photos that were taken close together.
///
/// Photos are put in capture-time order and linked to earlier neighbours
/// whose hash is close enough; linked photos form one group, so the result
/// does not depend on input order. Photos with different time sources are
/// never compared with each other, and photos with a known time must fall
/// within [SimilarityThresholds.windowMs] of each other.
///
/// Linking is transitive, so a chain of look-alikes can form a group whose
/// first and last photos differ a lot. The returned [SimilarityEvidence]
/// measures the real spread and marks such groups as low confidence.
List<SimilarityCluster> clusterSimilar(
  List<SimilarityCandidate> candidates, {
  SimilarityThresholds thresholds = const SimilarityThresholds(),
}) {
  if (!thresholds.useCaptureTime) {
    return _clusterByContent(candidates, thresholds);
  }
  final order = List<int>.generate(candidates.length, (index) => index)
    ..sort((a, b) {
      final left = candidates[a];
      final right = candidates[b];
      final bySource = left.captureSource.compareTo(right.captureSource);
      if (bySource != 0) return bySource;
      final byTime = left.capturedAt.compareTo(right.capturedAt);
      if (byTime != 0) return byTime;
      return left.tieBreaker.compareTo(right.tieBreaker);
    });

  final parent = List<int>.generate(order.length, (index) => index);
  int find(int index) {
    var root = index;
    while (parent[root] != root) {
      parent[root] = parent[parent[root]];
      root = parent[root];
    }
    return root;
  }

  for (var i = 1; i < order.length; i++) {
    final current = candidates[order[i]];
    final timed =
        current.captureSource != CaptureSource.unknown &&
        current.captureSource != CaptureSource.day;
    for (var j = i - 1; j >= 0; j--) {
      final earlier = candidates[order[j]];
      if (earlier.captureSource != current.captureSource) break;
      final gap = current.capturedAt - earlier.capturedAt;
      if (timed && gap > thresholds.windowMs) break;
      // Day-only photos must at least share the same day.
      if (current.captureSource == CaptureSource.day && gap > 0) break;
      // Without a capture time there is nothing to keep loose matches local,
      // so session grouping falls back to the strict distance.
      final limit = timed || !thresholds.isSession
          ? thresholds.maxLinkDistance
          : const SimilarityThresholds().maxLinkDistance;
      final earlierFaces = earlier.faceCount;
      final currentFaces = current.faceCount;
      if (earlierFaces != null &&
          currentFaces != null &&
          (earlierFaces - currentFaces).abs() >=
              thresholds.maxFaceCountDifference) {
        continue;
      }
      final distance = hammingDistance(earlier.visualHash, current.visualHash);
      var linked = distance <= limit;
      if (!linked && timed && gap <= thresholds.burstGapMs) {
        // Same moment: tolerate small shifts in framing.
        final a = earlier.colorHistogram;
        final b = current.colorHistogram;
        linked =
            distance <= thresholds.burstHashDistance ||
            (a != null &&
                b != null &&
                histogramDistance(a, b) <= thresholds.burstColorDistance);
      }
      if (linked) {
        final rootCurrent = find(i);
        final rootEarlier = find(j);
        if (rootCurrent != rootEarlier) parent[rootCurrent] = rootEarlier;
      }
    }
  }

  final positions = <int, List<int>>{};
  for (var i = 0; i < order.length; i++) {
    positions.putIfAbsent(find(i), () => []).add(i);
  }
  return [
    for (final group in positions.values)
      if (group.length > 1)
        SimilarityCluster(
          members: [for (final position in group) order[position]],
          evidence: _evidenceFor(
            [for (final position in group) candidates[order[position]]],
            thresholds,
          ),
        ),
  ];
}

/// The colours of [region] (a person's clothing) that stand out from the
/// [whole] picture, normalised to sum to one. Colours the whole scene shares,
/// such as the rocks and trees behind two different people, cancel out. Null
/// when almost nothing stands out, so the clothing is treated as unknown.
List<double>? distinctiveColors(List<double> region, List<double> whole) {
  final out = List<double>.filled(region.length, 0);
  var total = 0.0;
  for (var k = 0; k < region.length; k++) {
    final extra = region[k] - (k < whole.length ? whole[k] : 0.0);
    if (extra > 0) {
      out[k] = extra;
      total += extra;
    }
  }
  if (total < 0.08) return null;
  return [for (final value in out) value / total];
}

/// True when two photos cannot show the same people in the same clothes:
/// someone in the photo with fewer people has no clothing match (within
/// [limit]) among the people of the other. Extra people in one photo are
/// fine (a stranger walking by); unknown clothing never conflicts.
bool clothingConflict(
  List<List<double>>? a,
  List<List<double>>? b,
  double limit,
) {
  if (a == null || b == null || a.isEmpty || b.isEmpty || limit >= 1.0) {
    return false;
  }
  final fewer = a.length <= b.length ? a : b;
  final more = a.length <= b.length ? b : a;
  final used = <int>{};
  for (final person in fewer) {
    var best = -1;
    var bestDistance = double.infinity;
    for (var i = 0; i < more.length; i++) {
      if (used.contains(i)) continue;
      final distance = histogramDistance(person, more[i]);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    if (best < 0 || bestDistance > limit) return true;
    used.add(best);
  }
  return false;
}

/// Content-only grouping (see [SimilarityThresholds.content]): every pair is
/// compared, with no time window, so a copied-in photo can match one taken
/// years earlier. Quadratic in the number of photos, which is fine for a
/// phone folder of a few thousand.
List<SimilarityCluster> _clusterByContent(
  List<SimilarityCandidate> candidates,
  SimilarityThresholds thresholds,
) {
  final order = List<int>.generate(candidates.length, (index) => index)
    ..sort(
      (a, b) => candidates[a].tieBreaker.compareTo(candidates[b].tieBreaker),
    );
  final parent = List<int>.generate(order.length, (index) => index);
  int find(int index) {
    var root = index;
    while (parent[root] != root) {
      parent[root] = parent[parent[root]];
      root = parent[root];
    }
    return root;
  }

  // Whether two photos are directly alike (every guard and tier applies).
  bool linkedPair(int i, int j) {
    final current = candidates[order[i]];
      final earlier = candidates[order[j]];
      final earlierFaces = earlier.faceCount;
      final currentFaces = current.faceCount;
      // The loosest tier (colours only) also wants the same number of people.
      final sameFaces =
          earlierFaces == null ||
          currentFaces == null ||
          earlierFaces == currentFaces;
      if (earlierFaces != null &&
          currentFaces != null &&
          (earlierFaces - currentFaces).abs() >=
              thresholds.maxFaceCountDifference) {
        return false;
      }
      final distance = hammingDistance(earlier.visualHash, current.visualHash);
      if (earlier.isDocument || current.isDocument) {
        // Pages of text look alike at low resolution, so a document links
        // only to a near-identical copy of itself.
        final detailA = earlier.documentDetail;
        final detailB = current.documentDetail;
        if (earlier.isDocument &&
            current.isDocument &&
            detailA != null &&
            detailB != null &&
            distance <= thresholds.documentHashDistance &&
            layoutDistance(detailA, detailB) <=
                thresholds.documentDetailDistance) {
          return true;
        }
        return false;
      }
      // A trustworthy camera time (never a file date) can confirm a match
      // that the pictures alone only suggest, however the structure changed.
      final trusted =
          thresholds.trustedGapMs > 0 &&
          earlier.captureSource == CaptureSource.exif &&
          current.captureSource == CaptureSource.exif &&
          (current.capturedAt - earlier.capturedAt).abs() <=
              thresholds.trustedGapMs;
      final hashGate = math.max(
        thresholds.shiftHashDistance,
        thresholds.histLinkDistance > 0 ? thresholds.histHashDistance : 0,
      );
      if (distance > hashGate && !trusted) return false;
      // Same people in the same clothes: everyone in the photo with fewer
      // people must have a match in the other one.
      if (clothingConflict(
        earlier.people,
        current.people,
        thresholds.maxSubjectDistance,
      )) {
        return false;
      }
      final a = earlier.colorLayout;
      final b = current.colorLayout;
      var linked = false;
      if (a == null || b == null) {
        linked = distance <= thresholds.noLayoutHashDistance;
      } else {
        final layout = layoutDistance(a, b);
        linked =
            (distance <= thresholds.maxLinkDistance &&
                layout <= thresholds.layoutLinkDistance) ||
            (distance <= thresholds.shiftHashDistance &&
                layout <= thresholds.shiftLayoutDistance);
        // People moved or the camera zoomed: structure changed, colours did
        // not.
        final histA = earlier.colorHistogram;
        final histB = current.colorHistogram;
        if (!linked &&
            thresholds.histLinkDistance > 0 &&
            histA != null &&
            histB != null &&
            distance <= thresholds.histHashDistance &&
            sameFaces &&
            layout <= thresholds.histLayoutDistance &&
            histogramDistance(histA, histB) <= thresholds.histLinkDistance) {
          linked = true;
        }
      }
      if (!linked && trusted) {
        final histA = earlier.colorHistogram;
        final histB = current.colorHistogram;
        linked =
            histA != null &&
            histB != null &&
            a != null &&
            b != null &&
            histogramDistance(histA, histB) <=
                thresholds.trustedColorDistance &&
            layoutDistance(a, b) <= thresholds.trustedLayoutDistance;
      }
      return linked;
  }

  // Direct links are kept, not just their union, so a long chain of
  // look-alikes can be split afterwards.
  final links = List<Set<int>>.generate(order.length, (_) => <int>{});
  for (var i = 1; i < order.length; i++) {
    for (var j = 0; j < i; j++) {
      if (!linkedPair(i, j)) continue;
      links[i].add(j);
      links[j].add(i);
      parent[find(i)] = find(j);
    }
  }

  final positions = <int, List<int>>{};
  for (var i = 0; i < order.length; i++) {
    positions.putIfAbsent(find(i), () => []).add(i);
  }
  return [
    for (final component in positions.values)
      for (final group in _splitLooseChain(component, links))
        if (group.length > 1)
          SimilarityCluster(
            members: [for (final position in group) order[position]],
            evidence: _contentEvidenceFor([
              for (final position in group) candidates[order[position]],
            ], thresholds),
          ),
  ];
}

/// Single links can chain a whole beach day together: A looks like B, B like
/// C, and so on, though A and Z share only the place. A photo stays in a
/// group only when it is directly alike at least half of the photos already
/// in it, so a group is a set of mutually similar shots (same people, same
/// pose, same spot) rather than a chain.
List<List<int>> _splitLooseChain(List<int> component, List<Set<int>> links) {
  if (component.length < 4) return [component];
  final remaining = [...component]
    ..sort((a, b) {
      final byDegree = links[b].length.compareTo(links[a].length);
      return byDegree != 0 ? byDegree : a.compareTo(b);
    });
  final groups = <List<int>>[];
  while (remaining.isNotEmpty) {
    final group = <int>[remaining.removeAt(0)];
    while (true) {
      int? best;
      var bestShare = 0.0;
      for (final candidate in remaining) {
        final shared = group.where(links[candidate].contains).length;
        final share = shared / group.length;
        if (share >= 0.5 && share > bestShare) {
          best = candidate;
          bestShare = share;
        }
      }
      if (best == null) break;
      group.add(best);
      remaining.remove(best);
    }
    groups.add(group..sort());
  }
  return groups;
}

SimilarityEvidence _contentEvidenceFor(
  List<SimilarityCandidate> members,
  SimilarityThresholds thresholds,
) {
  var maxDistance = 0;
  double? maxLayout;
  if (members.length > thresholds.maxClusterForDiameter) {
    maxDistance = 64;
  } else {
    for (var i = 0; i < members.length; i++) {
      for (var j = i + 1; j < members.length; j++) {
        final distance = hammingDistance(
          members[i].visualHash,
          members[j].visualHash,
        );
        if (distance > maxDistance) maxDistance = distance;
        final a = members[i].colorLayout;
        final b = members[j].colorLayout;
        if (a != null && b != null) {
          final layout = layoutDistance(a, b);
          if (maxLayout == null || layout > maxLayout) maxLayout = layout;
        }
      }
    }
  }
  final layout = maxLayout;
  SimilarityConfidence confidence;
  if (maxDistance > thresholds.mediumDistance ||
      (layout != null && layout > thresholds.mediumLayoutDistance)) {
    confidence = SimilarityConfidence.low;
  } else if (maxDistance <= thresholds.highDistance &&
      layout != null &&
      layout <= thresholds.highLayoutDistance) {
    confidence = SimilarityConfidence.high;
  } else {
    confidence = SimilarityConfidence.medium;
  }
  // Never rate a document group High: similar-looking pages are not safe to
  // clean up in bulk.
  if (confidence == SimilarityConfidence.high &&
      members.any((member) => member.isDocument)) {
    confidence = SimilarityConfidence.medium;
  }
  return SimilarityEvidence(
    confidence: confidence,
    maxDistance: maxDistance,
    spanMs: null,
    captureSource: CaptureSource.unknown,
    size: members.length,
    maxLayoutDistance: maxLayout,
    byContent: true,
  );
}

SimilarityEvidence _evidenceFor(
  List<SimilarityCandidate> members,
  SimilarityThresholds thresholds,
) {
  var maxDistance = 0;
  double? maxColor;
  if (members.length > thresholds.maxClusterForDiameter) {
    maxDistance = 64;
  } else {
    for (var i = 0; i < members.length; i++) {
      for (var j = i + 1; j < members.length; j++) {
        final distance = hammingDistance(
          members[i].visualHash,
          members[j].visualHash,
        );
        if (distance > maxDistance) maxDistance = distance;
        final a = members[i].colorHistogram;
        final b = members[j].colorHistogram;
        if (a != null && b != null) {
          final color = histogramDistance(a, b);
          if (maxColor == null || color > maxColor) maxColor = color;
        }
      }
    }
  }

  final source = members.first.captureSource;
  int? spanMs;
  if (source != CaptureSource.unknown) {
    var earliest = members.first.capturedAt;
    var latest = earliest;
    for (final member in members) {
      if (member.capturedAt < earliest) earliest = member.capturedAt;
      if (member.capturedAt > latest) latest = member.capturedAt;
    }
    spanMs = latest - earliest;
  }

  final span = spanMs;
  final SimilarityConfidence confidence;
  // A quick burst whose colours match is the same scene even if the camera
  // moved enough to change the structure hash.
  final quickSameScene =
      span != null &&
      span <= thresholds.highSpanMs &&
      maxColor != null &&
      maxColor <= SimilarityEvidence.sameSceneColor;
  if (span == null ||
      (maxDistance > thresholds.mediumDistance && !quickSameScene) ||
      span > thresholds.windowMs) {
    confidence = SimilarityConfidence.low;
  } else if (maxDistance <= thresholds.highDistance &&
      span <= thresholds.highSpanMs &&
      source == CaptureSource.exif) {
    confidence = SimilarityConfidence.high;
  } else {
    confidence = SimilarityConfidence.medium;
  }

  return SimilarityEvidence(
    confidence: confidence,
    maxDistance: maxDistance,
    spanMs: spanMs,
    captureSource: source,
    size: members.length,
    isSession: thresholds.isSession,
    maxColorDistance: maxColor,
  );
}

/// Pairwise precision and recall of a grouping against labelled truth.
///
/// A "pair" is two photos placed in the same group. Precision is the share of
/// predicted pairs that are truly the same scene; recall is the share of true
/// pairs that were found.
class PairMetrics {
  const PairMetrics({
    required this.truePositives,
    required this.falsePositives,
    required this.falseNegatives,
  });

  final int truePositives;
  final int falsePositives;
  final int falseNegatives;

  double get precision {
    final predicted = truePositives + falsePositives;
    return predicted == 0 ? 1 : truePositives / predicted;
  }

  double get recall {
    final actual = truePositives + falseNegatives;
    return actual == 0 ? 1 : truePositives / actual;
  }

  double get f1 {
    final p = precision;
    final r = recall;
    return p + r == 0 ? 0 : 2 * p * r / (p + r);
  }
}

/// Compares [predicted] groups of photo ids with [truth], a map from photo id
/// to its labelled scene. Photos sharing a label are the same scene; photos
/// with a label nobody else shares are singletons.
///
/// Throws [ArgumentError] if a predicted group contains an id missing from
/// [truth], which usually means the labels file and the scan disagree.
PairMetrics evaluateGrouping({
  required Map<String, String> truth,
  required Iterable<Iterable<String>> predicted,
}) {
  String key(String a, String b) =>
      a.compareTo(b) <= 0 ? '$a\u0000$b' : '$b\u0000$a';

  Set<String> pairsOf(Iterable<String> ids) {
    final list = ids.toList();
    return {
      for (var i = 0; i < list.length; i++)
        for (var j = i + 1; j < list.length; j++) key(list[i], list[j]),
    };
  }

  final byLabel = <String, List<String>>{};
  truth.forEach((id, label) => byLabel.putIfAbsent(label, () => []).add(id));
  final truthPairs = <String>{};
  for (final ids in byLabel.values) {
    truthPairs.addAll(pairsOf(ids));
  }

  final predictedPairs = <String>{};
  for (final group in predicted) {
    final ids = group.toList();
    for (final id in ids) {
      if (!truth.containsKey(id)) {
        throw ArgumentError.value(id, 'predicted', 'has no label in truth');
      }
    }
    predictedPairs.addAll(pairsOf(ids));
  }

  final hits = predictedPairs.intersection(truthPairs).length;
  return PairMetrics(
    truePositives: hits,
    falsePositives: predictedPairs.length - hits,
    falseNegatives: truthPairs.length - hits,
  );
}
