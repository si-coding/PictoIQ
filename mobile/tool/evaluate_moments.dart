// Measures Best Moments on your own labelled photos.
//
//   dart run tool/evaluate_moments.dart <photo-folder> <labels.csv>
//
// labels.csv has one line per photo:
//   file name,moment label[,face count[,quality 0-100]]
// Photos that share a moment label belong to one moment (same people, place
// and activity). Give every other photo a label of its own. The face count
// is optional: this tool cannot run face detection, so leave it out and the
// people/composition checks are skipped, or fill it in by hand (0 for none).
// Quality defaults to 50. Aim for 100+ photos from several events, including
// the same people at different places and different people at one place.
//
// For each setting it prints, per moment window and people strictness:
//  - precision / recall of the grouping (pairs of photos);
//  - diversity: how different the chosen photos of a moment are (0 = twins);
//  - missed moments: real moments (2+ photos) with no photo recommended.
// Photo times are read from EXIF or the file name, then the modified time.
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:pictoiq_mobile/features/photos/best_moments/moment_selection.dart';
import 'package:pictoiq_mobile/shared/similarity_grouping.dart';

class _Row {
  _Row(this.name, this.moment, this.faces, this.quality);
  final String name;
  final String moment;
  final int? faces;
  final double quality;
}

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/evaluate_moments.dart <folder> <labels.csv>',
    );
    exitCode = 64;
    return;
  }
  final folder = Directory(args[0]);
  final rows = <_Row>[];
  for (final line in await File(args[1]).readAsLines()) {
    final parts = line.split(',').map((part) => part.trim()).toList();
    if (parts.length < 2 || parts[0].isEmpty) continue;
    rows.add(
      _Row(
        parts[0],
        parts[1],
        parts.length > 2 ? int.tryParse(parts[2]) : null,
        parts.length > 3 ? (double.tryParse(parts[3]) ?? 50) : 50,
      ),
    );
  }

  final names = <String>[];
  final truth = <String, String>{};
  final candidates = <SimilarityCandidate>[];
  final photos = <MomentPhoto>[];
  for (final row in rows) {
    final file = File('${folder.path}${Platform.pathSeparator}${row.name}');
    if (!await file.exists()) {
      stderr.writeln('Missing file, skipped: ${row.name}');
      continue;
    }
    final image = img.decodeImage(await file.readAsBytes());
    if (image == null) {
      stderr.writeln('Not an image, skipped: ${row.name}');
      continue;
    }
    final modified = (await file.lastModified()).millisecondsSinceEpoch;
    final (time, source) = captureTimeOf(image, modified, fileName: row.name);
    final hash = differenceHash(image);
    final layout = colorLayout(image);
    names.add(row.name);
    truth[row.name] = row.moment;
    candidates.add(
      SimilarityCandidate(
        visualHash: hash,
        colorHistogram: colorHistogram(image),
        colorLayout: layout,
        faceCount: row.faces,
        capturedAt: time,
        captureSource: source,
        tieBreaker: row.name,
      ),
    );
    photos.add(
      MomentPhoto(
        id: row.name,
        baseScore: row.quality / 100,
        visualHash: hash,
        colorLayout: layout,
        faceCount: row.faces,
      ),
    );
  }
  final moments = <String, List<String>>{};
  truth.forEach((name, moment) => moments.putIfAbsent(moment, () => []).add(name));
  final realMoments = moments.values.where((list) => list.length > 1).toList();
  stdout.writeln(
    '${names.length} photos, ${moments.length} labelled moments '
    '(${realMoments.length} with 2+ photos)',
  );
  stdout.writeln(
    'window    people    split  groups  precision  recall   f1     diversity  missed',
  );

  for (final window in MomentWindow.values) {
    for (final people in MatchLevel.values) {
      for (final split in [true, false]) {
        final thresholds = SimilarityThresholds.moments(
          splitByPeople: true,
          windowMs: window.capMs,
          trustedGapMs: window.trustedMs,
          people: people,
          splitComposition: split,
        );
        final clusters = clusterSimilar(candidates, thresholds: thresholds);
        final predicted = [
          for (final c in clusters) [for (final i in c.members) names[i]],
        ];
        final metrics = evaluateGrouping(truth: truth, predicted: predicted);

        final byName = {for (final photo in photos) photo.id: photo};
        final chosenAll = <String>{};
        var diversitySum = 0.0;
        var diversityCount = 0;
        for (final group in predicted) {
          final chosen = chooseMomentPhotos(
            [for (final name in group) byName[name]!],
            count: 2,
          );
          chosenAll.addAll(chosen);
          if (chosen.length == 2) {
            diversitySum += momentDissimilarity(
              byName[chosen[0]]!,
              byName[chosen[1]]!,
            );
            diversityCount++;
          }
        }
        final missed = realMoments
            .where((list) => !list.any(chosenAll.contains))
            .length;
        stdout.writeln(
          '${window.label.padRight(9)} ${people.label.padRight(9)} '
          '${(split ? 'yes' : 'no').padRight(6)} '
          '${predicted.length.toString().padRight(7)} '
          '${metrics.precision.toStringAsFixed(3).padRight(10)} '
          '${metrics.recall.toStringAsFixed(3).padRight(8)} '
          '${metrics.f1.toStringAsFixed(3).padRight(6)} '
          '${(diversityCount == 0 ? 0 : diversitySum / diversityCount).toStringAsFixed(2).padRight(10)} '
          '$missed/${realMoments.length}',
        );
      }
    }
  }
}
