// Measures similar-photo grouping on your own labelled photos.
//
//   dart run tool/evaluate_similarity.dart <photo-folder> <labels.csv>
//
// labels.csv has one line per photo: `file name,scene label`. Photos that
// share a label are the same scene (burst, near-duplicate). Give every other
// photo a label of its own. Aim for 100+ photos including tricky pairs:
// same place at different times, and different people in the same pose.
//
// The tool prints precision and recall for a range of link distances so you
// can pick thresholds with evidence instead of guessing. It reads file
// modified times, not EXIF-only times, so copy photos with their dates kept.
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:pictoiq_mobile/shared/similarity_grouping.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('Usage: dart run tool/evaluate_similarity.dart <folder> <labels.csv>');
    exitCode = 64;
    return;
  }
  final folder = Directory(args[0]);
  final truth = <String, String>{};
  for (final line in await File(args[1]).readAsLines()) {
    final comma = line.lastIndexOf(',');
    if (line.trim().isEmpty || comma < 1) continue;
    truth[line.substring(0, comma).trim()] = line.substring(comma + 1).trim();
  }

  final names = <String>[];
  final candidates = <SimilarityCandidate>[];
  for (final entry in truth.entries) {
    final file = File('${folder.path}${Platform.pathSeparator}${entry.key}');
    if (!await file.exists()) {
      stderr.writeln('Missing file, skipped: ${entry.key}');
      continue;
    }
    final image = img.decodeImage(await file.readAsBytes());
    if (image == null) {
      stderr.writeln('Not an image, skipped: ${entry.key}');
      continue;
    }
    final modified = (await file.lastModified()).millisecondsSinceEpoch;
    final (time, source) = captureTimeOf(image, modified, fileName: entry.key);
    names.add(entry.key);
    candidates.add(
      SimilarityCandidate(
        visualHash: differenceHash(image),
        colorHistogram: colorHistogram(image),
        colorLayout: colorLayout(image),
        capturedAt: time,
        captureSource: source,
        tieBreaker: entry.key,
      ),
    );
  }
  final usable = {for (final name in names) name: truth[name]!};
  stdout.writeln('${names.length} photos, ${usable.values.toSet().length} scenes');
  stdout.writeln('link  window  groups  precision  recall   f1     high-conf precision');
  for (final distance in [4, 6, 8, 10, 12, 14, 16]) {
    for (final windowSeconds in [10, 30, 60]) {
      final thresholds = SimilarityThresholds(
        maxLinkDistance: distance,
        windowMs: windowSeconds * 1000,
      );
      final clusters = clusterSimilar(candidates, thresholds: thresholds);
      final all = evaluateGrouping(
        truth: usable,
        predicted: [
          for (final c in clusters) [for (final i in c.members) names[i]],
        ],
      );
      final high = evaluateGrouping(
        truth: usable,
        predicted: [
          for (final c in clusters)
            if (c.evidence.confidence == SimilarityConfidence.high)
              [for (final i in c.members) names[i]],
        ],
      );
      stdout.writeln(
        '${distance.toString().padRight(5)} ${('${windowSeconds}s').padRight(7)} '
        '${clusters.length.toString().padRight(7)} '
        '${all.precision.toStringAsFixed(3).padRight(10)} '
        '${all.recall.toStringAsFixed(3).padRight(8)} '
        '${all.f1.toStringAsFixed(3).padRight(6)} '
        '${high.precision.toStringAsFixed(3)}',
      );
    }
  }

  // Quick shots (same moment): how loose the colour test can be.
  stdout.writeln('');
  for (final color in [0.05, 0.1, 0.15, 0.2, 0.25, 0.3]) {
    final clusters = clusterSimilar(
      candidates,
      thresholds: SimilarityThresholds(burstColorDistance: color),
    );
    final metrics = evaluateGrouping(
      truth: usable,
      predicted: [
        for (final c in clusters) [for (final i in c.members) names[i]],
      ],
    );
    stdout.writeln(
      'burst colour $color: ${clusters.length} groups, '
      'precision ${metrics.precision.toStringAsFixed(3)}, '
      'recall ${metrics.recall.toStringAsFixed(3)}',
    );
  }

  // Same-session mode: label photos of one photo session with a shared scene
  // label to measure it. Expect lower precision than burst mode.
  stdout.writeln('');
  for (final distance in [14, 18, 22]) {
    final thresholds = SimilarityThresholds(
      maxLinkDistance: distance,
      windowMs: SimilarityThresholds.session.windowMs,
      highDistance: SimilarityThresholds.session.highDistance,
      highSpanMs: SimilarityThresholds.session.highSpanMs,
      mediumDistance: SimilarityThresholds.session.mediumDistance,
      isSession: true,
    );
    final clusters = clusterSimilar(candidates, thresholds: thresholds);
    final metrics = evaluateGrouping(
      truth: usable,
      predicted: [
        for (final c in clusters) [for (final i in c.members) names[i]],
      ],
    );
    stdout.writeln(
      'session link $distance, 10 min: ${clusters.length} groups, '
      'precision ${metrics.precision.toStringAsFixed(3)}, '
      'recall ${metrics.recall.toStringAsFixed(3)}',
    );
  }

  // Content-only mode (what the app uses): no time involved.
  stdout.writeln('');
  stdout.writeln('content mode: hash link / layout link / shift layout');
  for (final hash in [8, 10, 12]) {
    for (final layout in [0.06, 0.10, 0.14]) {
      for (final shift in [0.04, 0.07, 0.10]) {
        final clusters = clusterSimilar(
          candidates,
          thresholds: SimilarityThresholds(
            useCaptureTime: false,
            maxLinkDistance: hash,
            layoutLinkDistance: layout,
            shiftLayoutDistance: shift,
            highDistance: 4,
            mediumDistance: 20,
          ),
        );
        final metrics = evaluateGrouping(
          truth: usable,
          predicted: [
            for (final c in clusters) [for (final i in c.members) names[i]],
          ],
        );
        stdout.writeln(
          '$hash / $layout / $shift: ${clusters.length} groups, '
          'precision ${metrics.precision.toStringAsFixed(3)}, '
          'recall ${metrics.recall.toStringAsFixed(3)}',
        );
      }
    }
  }
}
