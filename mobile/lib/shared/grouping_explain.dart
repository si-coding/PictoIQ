import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart';
import 'package:pictoiq_mobile/shared/shot_ranking.dart';
import 'package:pictoiq_mobile/shared/similarity_grouping.dart';

/// Which tool produced the scan whose ungrouped photos are being explained.
enum UngroupedTool { exactDuplicates, bestShots, bestMoments }

/// Plain-language reasons a scanned photo is not in any group.
///
/// The first entry is the main reason; any more are details. This describes
/// what the scan did and why, so a person can judge whether a photo they
/// expected to see was missed.
List<String> explainUngrouped({
  required FolderScanPhoto photo,
  required UngroupedTool tool,
  required DocumentMode documentMode,
  required ContentFilter contentFilter,
}) {
  if (tool == UngroupedTool.exactDuplicates) {
    return const [
      'No other photo has exactly the same file contents, so it has no exact duplicate.',
    ];
  }
  if (FolderDuplicateScanner.isLeftOut(photo, documentMode, contentFilter)) {
    if (photo.isDocumentLike) {
      return const [
        'It looks like a document, screenshot or text photo, and this tool is set to leave those out.',
      ];
    }
    final faces = photo.features?.faces;
    if (contentFilter.includesPeople &&
        faces != null &&
        faces.isUnclearSubject()) {
      return const [
        'The main person is out of focus, so it was left out as a people photo nobody would keep.',
      ];
    }
    return [
      'It does not match the content filter (${contentFilter.label}), so it was not compared with other photos.',
    ];
  }
  final features = photo.features;
  if (tool == UngroupedTool.bestShots) {
    return const [
      'No other photo was similar enough, close enough in time, to be a retake of this one.',
      'Best shots only lists scenes with two or more similar photos, so a single photo is not listed.',
      'If you expected it to match other photos (same person, moved or posed differently), try Loose matching, which also groups shots where people moved.',
    ];
  }
  // Best moments also lists a lone photo, but only when it shows a clearly
  // visible person and is clearly good.
  final reasons = <String>[
    'No other photo was similar enough to be part of the same moment.',
  ];
  if (features == null) {
    reasons.add('PictoIQ could not measure its quality, so it was not offered on its own.');
  } else {
    final problems = momentProblems(features);
    if (problems.isNotEmpty) {
      reasons.add('On its own it was not offered as a moment because:');
      reasons.addAll(problems);
    }
  }
  return reasons;
}
