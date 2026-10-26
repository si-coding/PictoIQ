import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'scan_image_processing.dart' show resizeLongestEdge;

/// Longest edge, in pixels, that sharpness and exposure are measured at. The
/// same size is used for every photo, so scores are comparable.
const _measureEdge = 512;

/// Pixel-level measurements of one photo.
class ImageSignals {
  const ImageSignals({
    required this.sharpness,
    required this.meanLuma,
    required this.highlightClip,
    required this.shadowClip,
  });

  /// Nothing measured; used when a photo has no analysis data.
  static const unknown = ImageSignals(
    sharpness: 0,
    meanLuma: 128,
    highlightClip: 0,
    shadowClip: 0,
  );

  /// Laplacian variance of the sharpest quarter of the frame at
  /// [_measureEdge] pixels (so a blurred portrait-mode background does not
  /// count against a crisp subject). Only meaningful when compared with
  /// other photos of the same scene: higher means sharper.
  final double sharpness;

  /// Average brightness, 0 (black) to 255 (white).
  final double meanLuma;

  /// Share of pixels that are almost white (0-1).
  final double highlightClip;

  /// Share of pixels that are almost black (0-1).
  final double shadowClip;

  /// 0-100. Penalises a mean brightness far from mid-grey and large areas of
  /// pure white or pure black. Highlights count against a photo more than
  /// shadows because blown highlights cannot be recovered.
  double get exposureScore {
    final tonal = 100 - math.min(60, (meanLuma - 120).abs() * 0.8);
    final clipPenalty = math.min(
      40,
      highlightClip * 100 * 4 + shadowClip * 100 * 1.5,
    );
    return (tonal - clipPenalty).clamp(0, 100).toDouble();
  }
}

/// Measures sharpness and exposure of [image] at a fixed working size.
ImageSignals measureImage(img.Image image) {
  final small = resizeLongestEdge(image, _measureEdge);
  final width = small.width;
  final height = small.height;
  final count = width * height;
  if (count == 0) return ImageSignals.unknown;

  final luma = Float64List(count);
  var sum = 0.0;
  var highlights = 0;
  var shadows = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final value = small.getPixel(x, y).luminanceNormalized * 255;
      luma[y * width + x] = value.toDouble();
      sum += value;
      if (value >= 250) highlights++;
      if (value <= 5) shadows++;
    }
  }

  // Sharpness is the Laplacian variance of the sharpest quarter of a grid of
  // tiles, not of the whole frame. Portrait mode and shallow depth of field
  // blur the background on purpose, and the whole-frame figure would call
  // such a photo soft even though its subject is crisp. A photo that is soft
  // everywhere still scores low, because every tile is soft.
  var variance = 0.0;
  if (width >= 3 && height >= 3) {
    final grid = math.max(1, math.min(6, math.min(width, height) ~/ 16));
    final tiles = <double>[];
    for (var ty = 0; ty < grid; ty++) {
      for (var tx = 0; tx < grid; tx++) {
        final x0 = math.max(1, tx * width ~/ grid);
        final x1 = math.min(width - 1, (tx + 1) * width ~/ grid);
        final y0 = math.max(1, ty * height ~/ grid);
        final y1 = math.min(height - 1, (ty + 1) * height ~/ grid);
        if (x1 <= x0 || y1 <= y0) continue;
        var lapSum = 0.0;
        var lapSquares = 0.0;
        for (var y = y0; y < y1; y++) {
          for (var x = x0; x < x1; x++) {
            final i = y * width + x;
            final laplacian =
                luma[i - width] +
                luma[i + width] +
                luma[i - 1] +
                luma[i + 1] -
                4 * luma[i];
            lapSum += laplacian;
            lapSquares += laplacian * laplacian;
          }
        }
        final samples = (x1 - x0) * (y1 - y0);
        final mean = lapSum / samples;
        tiles.add(math.max(0.0, lapSquares / samples - mean * mean));
      }
    }
    if (tiles.isNotEmpty) {
      tiles.sort((a, b) => b.compareTo(a));
      final keep = math.max(1, (tiles.length / 4).ceil());
      var total = 0.0;
      for (var i = 0; i < keep; i++) {
        total += tiles[i];
      }
      variance = total / keep;
    }
  }

  return ImageSignals(
    sharpness: variance,
    meanLuma: sum / count,
    highlightClip: highlights / count,
    shadowClip: shadows / count,
  );
}

/// What face detection found in one photo.
class FaceSignals {
  const FaceSignals({
    required this.count,
    required this.eyesOpenMin,
    required this.smileAverage,
    this.edgeCutoff = false,
    this.lookingAwayMax,
    this.subjectColors,
  });

  static const none = FaceSignals(
    count: 0,
    eyesOpenMin: null,
    smileAverage: null,
  );

  final int count;

  /// Lowest eye-open probability (0-1) over all faces and both eyes, so one
  /// blinking or winking person is enough to lower it. Null when unknown.
  final double? eyesOpenMin;

  /// Average smile probability (0-1) over the faces that report one.
  final double? smileAverage;

  /// True when a face touches or runs past the edge of the picture, which
  /// usually means someone's head is cut off.
  final bool edgeCutoff;

  /// Largest head turn away from the camera, in degrees, over all faces
  /// (0 = facing the camera). Null when unknown.
  final double? lookingAwayMax;

  /// Colours below the largest face (clothing), used only to keep photos of
  /// differently dressed people out of one group. Null when not measured.
  final List<double>? subjectColors;
}

/// Everything the ranking needs to know about one photo.
class ShotFeatures {
  const ShotFeatures({
    required this.signals,
    required this.megapixels,
    this.faces,
  });

  static const unknown = ShotFeatures(
    signals: ImageSignals.unknown,
    megapixels: 0,
  );

  final ImageSignals signals;

  /// Size of the original image in millions of pixels.
  final double megapixels;

  /// Null when face detection was turned off or failed for this photo.
  final FaceSignals? faces;
}

/// One photo handed to [rankShots].
class ShotInput {
  const ShotInput({
    required this.id,
    required this.features,
    required this.tieBreaker,
  });

  final String id;
  final ShotFeatures features;

  /// Stable ordering key (for example the relative path) for equal scores.
  final String tieBreaker;
}

class RankedShot {
  const RankedShot({
    required this.id,
    required this.rank,
    required this.score,
    required this.strengths,
    required this.concerns,
    required this.features,
    this.disqualifiers = const [],
    this.isFinalist = false,
  });

  final String id;

  /// 1 for the best shot.
  final int rank;

  /// 0-100, relative to the other photos in the same group. It says which
  /// shot is best here, not how good the photo is in absolute terms.
  final int score;

  /// Reasons in this photo's favour, compared with the rest of the group.
  final List<String> strengths;

  /// Reasons against it.
  final List<String> concerns;

  final ShotFeatures features;

  /// Faults serious enough that this photo should not be the one to keep or
  /// frame while a photo without them exists (closed eyes, a face cut off,
  /// looking away, badly blurred or washed out).
  final List<String> disqualifiers;

  bool get isDisqualified => disqualifiers.isNotEmpty;

  /// One of the few photos worth choosing between (at most three, none with a
  /// disqualifier, all close to the best score). The first is the top pick.
  final bool isFinalist;

  /// One line for a list row.
  String get summary {
    if (isDisqualified) return 'Not recommended: ${disqualifiers.first}';
    if (strengths.isEmpty && concerns.isEmpty) return 'Similar to the others';
    return [...strengths.take(2), ...concerns.take(1)].join(' · ');
  }
}

class GroupRanking {
  const GroupRanking({required this.shots, required this.usedFaceSignals});

  /// Best first.
  final List<RankedShot> shots;

  /// Whether face and eye signals contributed to the scores.
  final bool usedFaceSignals;

  RankedShot get best => shots.first;

  RankedShot? shotFor(String id) {
    for (final shot in shots) {
      if (shot.id == id) return shot;
    }
    return null;
  }

  /// Points between the best and second-best shot.
  int get margin => shots.length < 2 ? 100 : shots[0].score - shots[1].score;

  /// The photos worth choosing between, best first. Empty when every photo
  /// has a disqualifying fault.
  List<RankedShot> get finalists => [
    for (final shot in shots)
      if (shot.isFinalist) shot,
  ];

  /// False when the top two shots are too close to call, in which case the
  /// app should not choose between them without the user's help. A top shot
  /// with a fault is never a clear winner; a clean top shot beating a faulty
  /// runner-up always is.
  bool get isClearWinner {
    if (shots.length < 2) return true;
    if (best.isDisqualified) return false;
    if (shots[1].isDisqualified) return true;
    return margin >= clearWinnerMargin;
  }

  /// Minimum score gap for [isClearWinner].
  static const clearWinnerMargin = 6;

  /// Short explanation of the recommendation.
  String get headline {
    if (shots.isNotEmpty && best.isDisqualified) {
      return 'Every shot has a fault; look closely before choosing';
    }
    if (!isClearWinner) {
      final count = finalists.length;
      return count > 1
          ? '$count strong candidates; you decide'
          : 'These shots are very close; you decide';
    }
    final reasons = best.strengths.take(2).toList();
    return reasons.isEmpty
        ? 'Best overall balance'
        : 'Recommended: ${reasons.join(', ').toLowerCase()}';
  }
}

// A shot with a disqualifying fault loses this many points per fault (at most
// two count) and is never chosen over a shot without one.
const _faultPenalty = 20;

// Faults that rule a photo out as the one to keep.
const _closedEyes = 0.4;
const _lookingAwayDegrees = 30.0;
const _blurRatio = 0.35;
const _washedOutShare = 0.15;
const _crushedShare = 0.5;

// Finalists: up to this many photos within this many points of the best clean one.
const _maxFinalists = 3;
const _finalistWindow = 15;

// Score weights. They add up to 100 when faces are used, 70 when not.
const _sharpnessWeight = 40.0;
const _exposureWeight = 20.0;
const _resolutionWeight = 10.0;
const _faceWeight = 30.0;

/// Ranks photos of the same scene and explains why.
///
/// Sharpness is compared with the sharpest photo in the group, because the
/// raw value depends on the scene. Face signals only count when every photo
/// was assessed and at least one shows a face; otherwise their weight is left
/// out rather than guessed.
GroupRanking rankShots(List<ShotInput> inputs) {
  if (inputs.isEmpty) {
    return const GroupRanking(shots: [], usedFaceSignals: false);
  }

  final maxSharpness = inputs.map((i) => i.features.signals.sharpness).reduce(
    math.max,
  );
  final maxMegapixels = inputs.map((i) => i.features.megapixels).reduce(
    math.max,
  );
  final minMegapixels = inputs.map((i) => i.features.megapixels).reduce(
    math.min,
  );
  final allAssessed = inputs.every((i) => i.features.faces != null);
  final maxFaces = allAssessed
      ? inputs.map((i) => i.features.faces!.count).reduce(math.max)
      : 0;
  final minFaces = allAssessed
      ? inputs.map((i) => i.features.faces!.count).reduce(math.min)
      : 0;
  final useFaces = allAssessed && maxFaces > 0;
  final possible =
      _sharpnessWeight +
      _exposureWeight +
      _resolutionWeight +
      (useFaces ? _faceWeight : 0);

  final scored = <({ShotInput input, double points})>[];
  for (final input in inputs) {
    final features = input.features;
    final sharpRatio = maxSharpness <= 0
        ? 1.0
        : features.signals.sharpness / maxSharpness;
    final resolutionRatio = maxMegapixels <= 0
        ? 1.0
        : features.megapixels / maxMegapixels;
    var points =
        _sharpnessWeight * math.sqrt(sharpRatio.clamp(0, 1)) +
        _exposureWeight * features.signals.exposureScore / 100 +
        _resolutionWeight * resolutionRatio.clamp(0, 1);
    if (useFaces) {
      final faces = features.faces!;
      if (faces.count > 0) {
        final eyes = faces.eyesOpenMin ?? 0.5;
        final smile = faces.smileAverage ?? 0.5;
        final presence = faces.count / maxFaces;
        points += _faceWeight * (0.55 * eyes + 0.25 * smile + 0.20 * presence);
      }
    }
    scored.add((input: input, points: points));
  }

  final shots = <RankedShot>[];
  for (final entry in scored) {
    final features = entry.input.features;
    final strengths = <String>[];
    final concerns = <String>[];

    final sharpRatio = maxSharpness <= 0
        ? 1.0
        : features.signals.sharpness / maxSharpness;
    if (inputs.length > 1 && maxSharpness > 0) {
      if (sharpRatio >= 0.995) {
        strengths.add('Sharpest in the group');
      } else if (sharpRatio >= 0.9) {
        strengths.add('Nearly as sharp as the best shot');
      } else {
        concerns.add(
          'Softer: sharpness is ${(sharpRatio * 100).round()}% of the best shot',
        );
      }
    }

    final signals = features.signals;
    if (signals.highlightClip > 0.03) {
      concerns.add(
        'Bright areas washed out (${(signals.highlightClip * 100).round()}% of the picture)',
      );
    }
    if (signals.shadowClip > 0.15) {
      concerns.add(
        'Dark areas lose detail (${(signals.shadowClip * 100).round()}% of the picture)',
      );
    }
    if (signals.meanLuma < 60) {
      concerns.add('Looks underexposed');
    } else if (signals.meanLuma > 200) {
      concerns.add('Looks overexposed');
    }
    if (signals.exposureScore >= 85 &&
        signals.highlightClip <= 0.03 &&
        signals.shadowClip <= 0.15) {
      strengths.add('Well exposed');
    }

    if (minMegapixels < maxMegapixels * 0.95) {
      if (features.megapixels >= maxMegapixels * 0.999) {
        strengths.add('Highest resolution (${_mp(features.megapixels)})');
      } else if (features.megapixels < maxMegapixels * 0.95) {
        concerns.add(
          'Lower resolution (${_mp(features.megapixels)} vs ${_mp(maxMegapixels)})',
        );
      }
    }

    if (useFaces) {
      final faces = features.faces!;
      if (faces.count == 0) {
        concerns.add('No face found (other shots show $maxFaces)');
      } else {
        final eyes = faces.eyesOpenMin;
        if (eyes != null && eyes < 0.4) {
          concerns.add('Someone may have their eyes closed');
        } else if (eyes != null && eyes >= 0.65) {
          strengths.add(
            faces.count == 1 ? 'Eyes look open' : 'Everyone’s eyes look open',
          );
        }
        final smile = faces.smileAverage;
        if (smile != null && smile >= 0.55) {
          strengths.add(faces.count == 1 ? 'Smiling' : 'Mostly smiling');
        }
        if (faces.count < maxFaces) {
          concerns.add(
            'Fewer faces visible than other shots (${faces.count} of $maxFaces)',
          );
        } else if (minFaces < maxFaces) {
          strengths.add('Everyone in frame ($maxFaces faces)');
        }
      }
    }

    final faults = <String>[];
    if (inputs.length > 1 && maxSharpness > 0 && sharpRatio < _blurRatio) {
      faults.add('too blurry compared with the others');
    }
    if (signals.highlightClip > _washedOutShare) faults.add('washed out');
    if (signals.shadowClip > _crushedShare) faults.add('too dark');
    final faceInfo = features.faces;
    if (faceInfo != null && faceInfo.count > 0) {
      final eyes = faceInfo.eyesOpenMin;
      if (eyes != null && eyes < _closedEyes) faults.add('eyes closed');
      if (faceInfo.edgeCutoff) faults.add('a face is cut off at the edge');
      final away = faceInfo.lookingAwayMax;
      if (away != null && away > _lookingAwayDegrees) {
        faults.add('someone is looking away');
      }
    }
    final rawScore = (100 * entry.points / possible).round();
    final penalty = _faultPenalty * math.min(faults.length, 2);

    shots.add(
      RankedShot(
        id: entry.input.id,
        rank: 0,
        score: (rawScore - penalty).clamp(0, 100).toInt(),
        strengths: List.unmodifiable(strengths),
        concerns: List.unmodifiable(concerns),
        features: features,
        disqualifiers: List.unmodifiable(faults),
      ),
    );
  }

  final tieBreakers = {for (final input in inputs) input.id: input.tieBreaker};
  shots.sort((a, b) {
    if (a.isDisqualified != b.isDisqualified) return a.isDisqualified ? 1 : -1;
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final bySharpness = b.features.signals.sharpness.compareTo(
      a.features.signals.sharpness,
    );
    if (bySharpness != 0) return bySharpness;
    return tieBreakers[a.id]!.compareTo(tieBreakers[b.id]!);
  });

  final cleanBest = shots.isNotEmpty && !shots.first.isDisqualified
      ? shots.first.score
      : null;
  var finalists = 0;
  bool isFinalist(RankedShot shot) {
    if (cleanBest == null || shot.isDisqualified) return false;
    if (finalists >= _maxFinalists) return false;
    if (shot.score < cleanBest - _finalistWindow) return false;
    finalists++;
    return true;
  }

  return GroupRanking(
    shots: List.unmodifiable([
      for (var i = 0; i < shots.length; i++)
        RankedShot(
          id: shots[i].id,
          rank: i + 1,
          score: shots[i].score,
          strengths: shots[i].strengths,
          concerns: shots[i].concerns,
          features: shots[i].features,
          disqualifiers: shots[i].disqualifiers,
          isFinalist: isFinalist(shots[i]),
        ),
    ]),
    usedFaceSignals: useFaces,
  );
}

String _mp(double megapixels) => '${megapixels.toStringAsFixed(1)} MP';
