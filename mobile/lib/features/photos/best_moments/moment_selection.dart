import 'dart:math' as math;

import 'package:pictoiq_mobile/shared/similarity_grouping.dart'
    show clothingConflict, hammingDistance, layoutDistance;

/// How far apart in time photos of one "moment" may be (both need a reliable
/// camera time; photos without one are not limited).
enum MomentWindow {
  quick('Quick', 'Photos taken within about 5 minutes.', 5, 2),
  activity('Activity', 'Photos taken within about 20 minutes.', 20, 3),
  outing('Outing', 'Photos taken within about 90 minutes.', 90, 8);

  const MomentWindow(
    this.label,
    this.description,
    this.capMinutes,
    this.trustedMinutes,
  );

  final String label;
  final String description;

  /// Two photos further apart than this never join the same moment.
  final int capMinutes;

  /// Photos this close in time may join on colours alone, whatever their
  /// structure (people moved, framing changed).
  final int trustedMinutes;

  int get capMs => capMinutes * 60 * 1000;
  int get trustedMs => trustedMinutes * 60 * 1000;
}

/// Whether photos taken in clearly different places stay in separate moments
/// (needs a location in the photo's EXIF data; photos without one are not
/// affected).
enum MomentPlace {
  off('Off', 'Location is not used.', 0),
  spot('Same spot', 'Photos more than about 150 m apart are different moments.', 150),
  area('Same area', 'Photos more than about 1 km apart are different moments.', 1000);

  const MomentPlace(this.label, this.description, this.meters);

  final String label;
  final String description;
  final int meters;
}

/// How strongly the photos chosen for a moment must differ from each other.
enum MomentVariety {
  off('Off', 'The top-scoring photos, even if they look alike.', 0.0),
  balanced('Balanced', 'Prefers a different pose or framing for the next pick.', 0.35),
  strong('Strong', 'Strongly prefers photos that look different from each other.', 0.6);

  const MomentVariety(this.label, this.description, this.weight);

  final String label;
  final String description;

  /// Weight of "different from what is already chosen" against quality.
  final double weight;
}

/// Whether smiles count for more or less when choosing.
enum MomentExpression {
  balanced('Balanced', 'Smiles count as they do in best shots.', 1.0),
  smiles('Favour smiles', 'Smiling faces count for more.', 2.0),
  candid('Favour candid', 'Smiles are ignored, so natural moments are not outranked by posed ones.', 0.0);

  const MomentExpression(this.label, this.description, this.smileInfluence);

  final String label;
  final String description;

  /// Multiplier on the smile part of the face score (1 = unchanged).
  final double smileInfluence;
}

/// What kind of photo it is, from the number of faces found.
enum Composition { unknown, noFaces, single, couple, group }

Composition compositionOf(int? faceCount) {
  if (faceCount == null) return Composition.unknown;
  if (faceCount <= 0) return Composition.noFaces;
  if (faceCount == 1) return Composition.single;
  if (faceCount == 2) return Composition.couple;
  return Composition.group;
}

/// One photo of a moment, with what the selection needs.
class MomentPhoto {
  const MomentPhoto({
    required this.id,
    required this.baseScore,
    required this.visualHash,
    this.faceCount,
    this.smile,
    this.eyesOpen,
    this.edgeCutoff = false,
    this.colorLayout,
    this.people,
    this.disqualified = false,
  });

  final String id;

  /// Quality score from the group ranking, 0 to 1.
  final double baseScore;
  final int visualHash;
  final int? faceCount;

  /// Average smile probability, 0 to 1, when known.
  final double? smile;
  final List<double>? colorLayout;

  /// Clothing colours of the people in the photo, when measured.
  final List<List<double>>? people;

  /// Lowest eye-open probability over all faces (0 to 1), when known. One
  /// person blinking is enough to lower it.
  final double? eyesOpen;

  /// A face touches the edge of the picture (probably cut off).
  final bool edgeCutoff;

  /// Has a serious fault (closed eyes, cut-off face, blur...).
  final bool disqualified;
}

/// How the photo's score is adjusted for the kind of photo it is. These are
/// starting values (0-1 score units), to be tuned on real galleries.
///
/// The ranking already scores faces; this only shifts the emphasis so that
/// each kind of photo is judged on what matters for it.
class CompositionProfile {
  const CompositionProfile({
    required this.smile,
    required this.eyes,
    required this.cutoff,
    required this.peopleInFrame,
  });

  /// Weight of the average smile (scaled by the expression setting).
  final double smile;

  /// Weight of eyes being open, around a typical 0.8 reading.
  final double eyes;

  /// Penalty for a face cut off by the frame.
  final double cutoff;

  /// Bonus for having more of the people of the moment in frame.
  final double peopleInFrame;

  static const portrait = CompositionProfile(
    smile: 0.075,
    eyes: 0.10,
    cutoff: 0.12,
    peopleInFrame: 0,
  );
  static const couple = CompositionProfile(
    smile: 0.075,
    eyes: 0.12,
    cutoff: 0.10,
    peopleInFrame: 0,
  );
  // Everyone's eyes open matters most; a smile from all is rare, so it counts
  // less than in a portrait.
  static const group = CompositionProfile(
    smile: 0.05,
    eyes: 0.14,
    cutoff: 0.08,
    peopleInFrame: 0.08,
  );
  static const scene = CompositionProfile(
    smile: 0,
    eyes: 0,
    cutoff: 0,
    peopleInFrame: 0,
  );

  static CompositionProfile of(Composition composition) => switch (composition) {
    Composition.single => portrait,
    Composition.couple => couple,
    Composition.group => group,
    Composition.noFaces || Composition.unknown => scene,
  };
}

const _faultPenalty = 0.4;

/// 0 (near-twins) to 1 (clearly different), from structure, colour layout and
/// the number of people.
double momentDissimilarity(MomentPhoto a, MomentPhoto b) {
  final hash = math.min(1.0, hammingDistance(a.visualHash, b.visualHash) / 24);
  final layoutA = a.colorLayout;
  final layoutB = b.colorLayout;
  final layout = layoutA == null || layoutB == null
      ? 0.5
      : math.min(1.0, layoutDistance(layoutA, layoutB) / 0.2);
  var faces = 0.0;
  final facesA = a.faceCount;
  final facesB = b.faceCount;
  if (facesA != null && facesB != null) {
    final most = math.max(facesA, facesB);
    faces = most == 0 ? 0.0 : (facesA - facesB).abs() / most;
  }
  return 0.5 * hash + 0.3 * layout + 0.2 * faces;
}

/// The ids of the [count] photos that best represent a moment, best first.
///
/// The first is the highest scoring photo. Each next one balances its own
/// score against how different it is from the photos already chosen
/// (maximal marginal relevance), so two near-identical shots are not both
/// picked while a clearly different good one is left out. A photo with a
/// serious fault is only chosen when no clean one is left.
List<String> chooseMomentPhotos(
  List<MomentPhoto> photos, {
  required int count,
  MomentVariety variety = MomentVariety.balanced,
  MomentExpression expression = MomentExpression.balanced,
  double clothingLimit = 1.0,
}) {
  if (photos.isEmpty || count < 1) return const [];
  final maxFaces = photos
      .map((photo) => photo.faceCount ?? 0)
      .reduce(math.max);

  double relevance(MomentPhoto photo) {
    var score = photo.baseScore;
    final faces = photo.faceCount ?? 0;
    if (faces > 0) {
      final profile = CompositionProfile.of(compositionOf(faces));
      final smile = photo.smile;
      if (smile != null) {
        score += (expression.smileInfluence - 1) * profile.smile * smile;
      }
      final eyes = photo.eyesOpen;
      if (eyes != null) score += profile.eyes * (eyes - 0.8);
      if (photo.edgeCutoff) score -= profile.cutoff;
      if (profile.peopleInFrame > 0 && maxFaces > 0) {
        score += profile.peopleInFrame * faces / maxFaces;
      }
    }
    if (photo.disqualified) score -= _faultPenalty;
    return score;
  }

  final remaining = [...photos];
  final chosen = <MomentPhoto>[];
  // Photos of other-looking people: used only when nothing else is left, so
  // a moment never shows fewer photos than asked for.
  final deferred = <MomentPhoto>[];
  while (chosen.length < count &&
      (remaining.isNotEmpty || deferred.isNotEmpty)) {
    if (remaining.isEmpty) {
      remaining.addAll(deferred);
      deferred.clear();
    }
    MomentPhoto? best;
    var bestValue = double.negativeInfinity;
    for (final candidate in remaining) {
      final quality = relevance(candidate);
      final double value;
      if (chosen.isEmpty || variety.weight == 0) {
        value = quality;
      } else {
        final apart = chosen
            .map((other) => momentDissimilarity(candidate, other))
            .reduce(math.min);
        value = (1 - variety.weight) * quality + variety.weight * apart;
      }
      if (value > bestValue) {
        best = candidate;
        bestValue = value;
      }
    }
    chosen.add(best!);
    remaining.remove(best);
    if (chosen.length == 1 && clothingLimit < 1.0) {
      // A moment can be chained together through photos in between, so a
      // different couple at the same place may have joined it. Only photos
      // of the people in the best photo may be shown next to it.
      final first = best;
      final conflicting = remaining
          .where(
            (other) =>
                clothingConflict(first.people, other.people, clothingLimit),
          )
          .toList();
      remaining.removeWhere(conflicting.contains);
      deferred.addAll(conflicting);
    }
  }
  return [for (final photo in chosen) photo.id];
}
