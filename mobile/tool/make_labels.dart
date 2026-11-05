// Starts a labelled test set for tool/evaluate_moments.dart.
//
//   dart run tool/make_labels.dart <photo-folder> [out-folder]
//
// It groups the photos with the app's own Best Moments rules and writes:
//   labels.csv   file name,moment label   (one line per photo)
//   review.html  the photos grouped by that label, to look through in a browser
// Open review.html, then fix labels.csv by hand: give photos that belong
// together the same label, and photos that do not a label of their own. The
// proposal is only a starting point (it is the thing being measured), so
// correct it from what you see, not from what the app thinks.
// Optionally add a face count (3rd column) and quality 0-100 (4th column).
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:pictoiq_mobile/shared/similarity_grouping.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln(
      'Usage: dart run tool/make_labels.dart <photo-folder> [out-folder]',
    );
    exitCode = 64;
    return;
  }
  final folder = Directory(args[0]);
  final out = Directory(args.length > 1 ? args[1] : '.');
  await out.create(recursive: true);

  final files = [
    for (final entity in folder.listSync())
      if (entity is File &&
          RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false)
              .hasMatch(entity.path))
        entity,
  ];
  final names = <String>[];
  final paths = <String>[];
  final candidates = <SimilarityCandidate>[];
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final image = img.decodeImage(await file.readAsBytes());
    if (image == null) {
      stderr.writeln('Not an image, skipped: $name');
      continue;
    }
    final modified = (await file.lastModified()).millisecondsSinceEpoch;
    final (time, source) = captureTimeOf(image, modified, fileName: name);
    names.add(name);
    paths.add(file.path);
    candidates.add(
      SimilarityCandidate(
        visualHash: differenceHash(image),
        colorHistogram: colorHistogram(image),
        colorLayout: colorLayout(image),
        capturedAt: time,
        captureSource: source,
        tieBreaker: name,
      ),
    );
  }

  final clusters = clusterSimilar(
    candidates,
    thresholds: SimilarityThresholds.moments(),
  );
  final label = List<String>.filled(names.length, '');
  var next = 1;
  final groups = <String, List<int>>{};
  for (final cluster in clusters) {
    final id = 'moment-${next.toString().padLeft(3, '0')}';
    next++;
    for (final i in cluster.members) {
      label[i] = id;
    }
    groups[id] = [...cluster.members];
  }
  // Photos that joined no group get a label of their own.
  for (var i = 0; i < names.length; i++) {
    if (label[i].isEmpty) {
      final id = 'single-${next.toString().padLeft(3, '0')}';
      next++;
      label[i] = id;
      groups[id] = [i];
    }
  }

  final csv = StringBuffer();
  for (var i = 0; i < names.length; i++) {
    csv.writeln('${names[i]},${label[i]}');
  }
  await File('${out.path}${Platform.pathSeparator}labels.csv')
      .writeAsString(csv.toString());

  final html = StringBuffer(
    '<!doctype html><meta charset="utf-8"><title>PictoIQ labels</title>'
    '<style>body{font:14px sans-serif;margin:16px}h2{margin:20px 0 6px}'
    'img{height:150px;margin:2px;border-radius:6px}figure{display:inline-block;margin:0}'
    'figcaption{font-size:11px;color:#555}</style>'
    '<h1>Proposed moments</h1><p>Fix <b>labels.csv</b> where a group mixes '
    'different moments or splits one.</p>',
  );
  groups.forEach((id, members) {
    html.writeln('<h2>$id (${members.length})</h2>');
    for (final i in members) {
      html.writeln(
        '<figure><img src="${Uri.file(paths[i])}"><figcaption>${names[i]}</figcaption></figure>',
      );
    }
  });
  await File('${out.path}${Platform.pathSeparator}review.html')
      .writeAsString(html.toString());
  stdout.writeln(
    '${names.length} photos, ${groups.length} proposed moments. '
    'Wrote labels.csv and review.html to ${out.path}.',
  );
}
