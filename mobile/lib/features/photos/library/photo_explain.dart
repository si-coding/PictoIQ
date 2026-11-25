import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart'
    show FolderScanPhoto;
import 'package:pictoiq_mobile/shared/photo_content.dart';

String _percent(double value) => '${(value * 100).round()}%';

/// Plain-language facts about how one photo was judged, for the "Why is this
/// here?" panel: what the face detector and the on-device labeller saw, and
/// the measurements behind sharpness. Everything shown was computed on the
/// phone. Empty for scans that do not analyse pixels (exact duplicates).
List<String> explainPhoto(FolderScanPhoto photo) {
  final lines = <String>[];
  if (photo.isFavorite) {
    lines.add('Marked as a favourite in your gallery, so it is always kept.');
  }
  final features = photo.features;
  if (features == null) return lines;

  for (final note in features.notes) {
    lines.add(note);
  }
  final faces = features.faces;
  if (faces == null) {
    lines.add('People: faces were not checked for this photo.');
  } else if (faces.count == 0) {
    lines.add('People: no faces found.');
  } else {
    final area = faces.largestFaceArea;
    final size = area == null
        ? ''
        : ', the largest fills ${(area * 100).toStringAsFixed(1)}% of the picture';
    final small = faces.hasProminentFace
        ? ''
        : ' (too small to count as the subject)';
    lines.add('People: ${faces.count} face(s)$size$small.');
    final face = faces.faceSharpness;
    final frame = faces.frameSharpness;
    if (face != null && frame != null) {
      lines.add(
        'Face sharpness ${face.round()} against ${frame.round()} for the '
        'whole picture. A face far softer than the picture means the focus '
        'is behind the person.',
      );
    }
    final eyes = faces.eyesOpenMin;
    if (eyes != null) lines.add('Eyes open (lowest): ${_percent(eyes)}.');
    if (faces.hasSunglasses) {
      lines.add(
        'Sunglasses on ${faces.sunglassesCount} face(s): their eyes are not '
        'judged, so the look is not counted as a blink.',
      );
    }
    final away = faces.lookingAwayMax;
    if (away != null) {
      lines.add('Head turned away by up to ${away.round()} degrees.');
    }
  }

  final labels = features.labels;
  if (labels == null) {
    lines.add(
      'Objects and scenery: not checked (a clear face was found, the filter '
      'is off, or the labeller failed).',
    );
  } else if (labels.isEmpty) {
    lines.add('Objects and scenery: nothing recognised.');
  } else {
    final top = [...labels]
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    lines.add(
      'Recognised: ${top.take(6).map((l) => '${l.name} ${_percent(l.confidence)}').join(', ')}.',
    );
    final scores = labelScores(labels);
    lines.add(
      'Strongest match: people ${_percent(scores.people)}, scenery '
      '${_percent(scores.scenery)}, objects ${_percent(scores.thing)}.',
    );
  }

  lines.add(
    'Sharpness ${features.signals.sharpness.round()}, brightness '
    '${features.signals.meanLuma.round()} of 255.',
  );
  if (photo.isDocumentLike) {
    lines.add('Looks like a page of text or a screenshot.');
  }
  if (photo.qualityNotes.isNotEmpty) {
    lines.add('Ranking notes: ${photo.qualityNotes.join(' · ')}.');
  }
  return lines;
}
