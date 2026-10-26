import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pictoiq_mobile/similarity_grouping.dart';

const _t0 = 1700000000000;

SimilarityCandidate _shot(
  String name,
  int hash,
  int secondsAfterStart, {
  int source = CaptureSource.exif,
}) => SimilarityCandidate(
  visualHash: hash,
  capturedAt: source == CaptureSource.unknown ? 0 : _t0 + secondsAfterStart * 1000,
  captureSource: source,
  tieBreaker: name,
);

/// Sets the lowest [bits] bits, so two hashes built this way differ by
/// exactly the difference between their bit counts.
int _bits(int bits) => bits == 0 ? 0 : (1 << bits) - 1;

List<List<String>> _names(
  List<SimilarityCandidate> shots,
  List<SimilarityCluster> clusters,
) => [
  for (final cluster in clusters)
    [for (final index in cluster.members) shots[index].tieBreaker]..sort(),
]..sort((a, b) => a.first.compareTo(b.first));

img.Image _gradient({bool flipped = false}) {
  final image = img.Image(width: 90, height: 80);
  for (var y = 0; y < 80; y++) {
    for (var x = 0; x < 90; x++) {
      final value = flipped ? 255 - (x * 255 ~/ 89) : x * 255 ~/ 89;
      image.setPixelRgb(x, y, value, value, value);
    }
  }
  return image;
}

void main() {
  group('hash helpers', () {
    test('hammingDistance counts differing bits', () {
      expect(hammingDistance(0, 0), 0);
      expect(hammingDistance(0, 1), 1);
      expect(hammingDistance(0, _bits(10)), 10);
      expect(hammingDistance(0, -1), 64);
      expect(hammingDistance(-1, -1), 0);
    });

    test('differenceHash is stable and reacts to image structure', () {
      expect(differenceHash(_gradient()), differenceHash(_gradient()));
      expect(
        hammingDistance(
          differenceHash(_gradient()),
          differenceHash(_gradient(flipped: true)),
        ),
        greaterThan(32),
      );
    });
  });

  group('clusterSimilar', () {
    test('groups near-identical shots taken seconds apart as high confidence', () {
      final shots = [
        _shot('a', _bits(0), 0),
        _shot('b', _bits(2), 2),
        _shot('c', _bits(1), 4),
      ];
      final clusters = clusterSimilar(shots);
      expect(_names(shots, clusters), [
        ['a', 'b', 'c'],
      ]);
      expect(clusters.single.evidence.confidence, SimilarityConfidence.high);
      expect(clusters.single.evidence.maxDistance, 2);
      expect(clusters.single.evidence.spanMs, 4000);
    });

    test('does not group look-alikes taken far apart', () {
      final shots = [_shot('a', 0, 0), _shot('b', 0, 31)];
      expect(clusterSimilar(shots), isEmpty);
    });

    test('does not group different-looking shots taken together', () {
      final shots = [_shot('a', 0, 0), _shot('b', _bits(20), 1)];
      expect(clusterSimilar(shots), isEmpty);
    });

    test('never compares capture times from different sources', () {
      final shots = [
        _shot('a', 0, 0),
        _shot('b', 0, 0, source: CaptureSource.modified),
      ];
      expect(clusterSimilar(shots), isEmpty);
    });

    test('file-time-only groups are at most medium confidence', () {
      final shots = [
        _shot('a', 0, 0, source: CaptureSource.modified),
        _shot('b', 0, 1, source: CaptureSource.modified),
      ];
      expect(
        clusterSimilar(shots).single.evidence.confidence,
        SimilarityConfidence.medium,
      );
    });

    test('moderate hash differences or a long span lower confidence', () {
      final moderate = [_shot('a', 0, 0), _shot('b', _bits(6), 1)];
      expect(
        clusterSimilar(moderate).single.evidence.confidence,
        SimilarityConfidence.medium,
      );
      final slow = [_shot('a', 0, 0), _shot('b', 0, 15)];
      expect(
        clusterSimilar(slow).single.evidence.confidence,
        SimilarityConfidence.medium,
      );
    });

    test('a chain of look-alikes is flagged low confidence', () {
      // a-b and b-c are within the link limit, but a and c differ by 16 bits.
      final shots = [
        _shot('a', _bits(0), 0),
        _shot('b', _bits(8), 1),
        _shot('c', _bits(16), 2),
      ];
      final clusters = clusterSimilar(shots);
      expect(_names(shots, clusters), [
        ['a', 'b', 'c'],
      ]);
      expect(clusters.single.evidence.maxDistance, 16);
      expect(clusters.single.evidence.confidence, SimilarityConfidence.low);
    });

    test('photos with no capture time group by appearance but are low confidence', () {
      final shots = [
        _shot('a', 0, 0, source: CaptureSource.unknown),
        _shot('b', _bits(1), 0, source: CaptureSource.unknown),
      ];
      final cluster = clusterSimilar(shots).single;
      expect(cluster.evidence.confidence, SimilarityConfidence.low);
      expect(cluster.evidence.spanMs, isNull);
      expect(cluster.evidence.notes.join(' '), contains('No capture time'));
    });

    test('result does not depend on input order', () {
      final shots = [
        _shot('a', 0, 0),
        _shot('b', _bits(2), 3),
        _shot('c', _bits(3), 6),
        _shot('d', 0, 100),
        _shot('e', _bits(1), 102),
        _shot('f', _bits(30), 50),
      ];
      final expected = _names(shots, clusterSimilar(shots));
      final reversed = shots.reversed.toList();
      expect(_names(reversed, clusterSimilar(reversed)), expected);
      expect(expected, [
        ['a', 'b', 'c'],
        ['d', 'e'],
      ]);
    });

    test('identical hashes taken together are high confidence', () {
      final shots = [_shot('a', 12345, 0), _shot('b', 12345, 0)];
      expect(
        clusterSimilar(shots).single.evidence.confidence,
        SimilarityConfidence.high,
      );
    });
  });

  group('same-session grouping', () {
    test('links different poses minutes apart that burst mode would not', () {
      final shots = [
        _shot('a', 0, 0),
        _shot('b', _bits(14), 120),
        _shot('c', _bits(16), 300),
      ];
      expect(clusterSimilar(shots), isEmpty);
      final clusters = clusterSimilar(
        shots,
        thresholds: SimilarityThresholds.session,
      );
      expect(_names(shots, clusters), [
        ['a', 'b', 'c'],
      ]);
      final evidence = clusters.single.evidence;
      expect(evidence.isSession, isTrue);
      expect(evidence.notes.first, contains('Same session'));
    });

    test('session groups are never high confidence', () {
      final shots = [_shot('a', 0, 0), _shot('b', 0, 1)];
      final cluster = clusterSimilar(
        shots,
        thresholds: SimilarityThresholds.session,
      ).single;
      expect(cluster.evidence.confidence, SimilarityConfidence.medium);
    });

    test('still respects the ten-minute window', () {
      final shots = [_shot('a', 0, 0), _shot('b', 0, 601)];
      expect(
        clusterSimilar(shots, thresholds: SimilarityThresholds.session),
        isEmpty,
      );
    });

    test('photos without a time only link at the strict distance', () {
      final shots = [
        _shot('a', 0, 0, source: CaptureSource.unknown),
        _shot('b', _bits(14), 0, source: CaptureSource.unknown),
      ];
      expect(
        clusterSimilar(shots, thresholds: SimilarityThresholds.session),
        isEmpty,
      );
    });

    test('very different spread is low confidence', () {
      final shots = [
        _shot('a', 0, 0),
        _shot('b', _bits(14), 100),
        _shot('c', _bits(28), 200),
      ];
      final cluster = clusterSimilar(
        shots,
        thresholds: SimilarityThresholds.session,
      ).single;
      expect(cluster.evidence.maxDistance, 28);
      expect(cluster.evidence.confidence, SimilarityConfidence.low);
    });
  });

  group('quick shots with shifted framing', () {
    List<double> hist(double red) => [
      red,
      1 - red,
      for (var i = 2; i < colorHistogramBins; i++) 0,
    ];

    SimilarityCandidate quick(
      String name,
      int hash,
      int seconds,
      List<double>? colors,
    ) => SimilarityCandidate(
      visualHash: hash,
      capturedAt: _t0 + seconds * 1000,
      captureSource: CaptureSource.exif,
      tieBreaker: name,
      colorHistogram: colors,
    );

    test('links shots seconds apart when the colours match', () {
      // 20 bits apart: too different for the strict hash test.
      final shots = [
        quick('a', 0, 0, hist(0.5)),
        quick('b', _bits(20), 3, hist(0.52)),
      ];
      final clusters = clusterSimilar(shots);
      expect(_names(shots, clusters), [
        ['a', 'b'],
      ]);
      final evidence = clusters.single.evidence;
      expect(evidence.maxDistance, 20);
      expect(evidence.maxColorDistance, lessThan(SimilarityEvidence.sameSceneColor));
      // A quick burst with matching colours is trusted at medium, not low.
      expect(evidence.confidence, SimilarityConfidence.medium);
      expect(evidence.notes.first, contains('Same scene'));
    });

    test('does not link shots whose colours differ', () {
      final shots = [
        quick('a', 0, 0, hist(0.9)),
        quick('b', _bits(20), 3, hist(0.1)),
      ];
      expect(clusterSimilar(shots), isEmpty);
    });

    test('colour only helps within the burst gap', () {
      final shots = [
        quick('a', 0, 0, hist(0.5)),
        quick('b', _bits(20), 12, hist(0.5)),
      ];
      expect(clusterSimilar(shots), isEmpty);
    });

    test('without colour profiles only the hash decides', () {
      final shots = [
        quick('a', 0, 0, null),
        quick('b', _bits(20), 3, null),
      ];
      expect(clusterSimilar(shots), isEmpty);
      final close = [quick('a', 0, 0, null), quick('b', _bits(13), 3, null)];
      expect(clusterSimilar(close), hasLength(1));
    });

    test('a loose colour link with a large hash gap is low confidence', () {
      final shots = [
        quick('a', 0, 0, hist(0.5)),
        quick('b', _bits(24), 4, hist(0.9)),
      ];
      final cluster = clusterSimilar(shots).single;
      expect(cluster.evidence.confidence, SimilarityConfidence.low);
    });
  });

  group('colour histogram', () {
    img.Image solid(int r, int g, int b) {
      final image = img.Image(width: 80, height: 60);
      img.fill(image, color: img.ColorRgb8(r, g, b));
      return image;
    }

    test('sums to one and matches itself', () {
      final h = colorHistogram(solid(200, 30, 30));
      expect(h.length, colorHistogramBins);
      expect(h.reduce((a, b) => a + b), closeTo(1, 1e-9));
      expect(histogramDistance(h, h), closeTo(0, 1e-9));
    });

    test('different colours are far apart, similar ones close', () {
      final red = colorHistogram(solid(200, 30, 30));
      final nearRed = colorHistogram(solid(205, 35, 25));
      final blue = colorHistogram(solid(30, 30, 200));
      expect(histogramDistance(red, nearRed), lessThan(0.05));
      expect(histogramDistance(red, blue), greaterThan(0.9));
    });
  });

  group('file name dates', () {
    test('reads WhatsApp, camera and Pixel style names', () {
      expect(fileNameDate('IMG-20221109-WA0007.jpg')!.$1, DateTime(2022, 11, 9));
      expect(fileNameDate('IMG-20221109-WA0007.jpg')!.$2, isNull);
      expect(fileNameDate('IMG_20221109_123456.jpg')!.$2, 12 * 3600 + 34 * 60 + 56);
      expect(fileNameDate('PXL_20221109_123456789.jpg')!.$1, DateTime(2022, 11, 9));
      expect(fileNameDate('holiday.jpg'), isNull);
      expect(fileNameDate('IMG-20221399-WA0001.jpg'), isNull);
    });

    test('ignores a modified time that disagrees with the name', () {
      final image = img.Image(width: 4, height: 4);
      final copied = DateTime(2025, 3, 1).millisecondsSinceEpoch;
      final (time, source) = captureTimeOf(
        image,
        copied,
        fileName: 'IMG-20221109-WA0007.jpg',
      );
      expect(source, CaptureSource.day);
      expect(time, DateTime(2022, 11, 9).millisecondsSinceEpoch);
    });

    test('keeps the modified time when it matches the name', () {
      final image = img.Image(width: 4, height: 4);
      final saved = DateTime(2022, 11, 9, 18, 30).millisecondsSinceEpoch;
      final (time, source) = captureTimeOf(
        image,
        saved,
        fileName: 'IMG-20221109-WA0007.jpg',
      );
      expect(source, CaptureSource.modified);
      expect(time, saved);
    });

    test('photos from different days are never grouped', () {
      SimilarityCandidate dayShot(String name, int hash, DateTime day) =>
          SimilarityCandidate(
            visualHash: hash,
            capturedAt: day.millisecondsSinceEpoch,
            captureSource: CaptureSource.day,
            tieBreaker: name,
          );
      final shots = [
        dayShot('a', 0, DateTime(2022, 11, 9)),
        dayShot('b', 0, DateTime(2023, 11, 27)),
        dayShot('c', 0, DateTime(2022, 11, 9)),
      ];
      expect(_names(shots, clusterSimilar(shots)), [
        ['a', 'c'],
      ]);
    });

    test('same-day photos need the strict hash match', () {
      SimilarityCandidate dayShot(String name, int hash) => SimilarityCandidate(
        visualHash: hash,
        capturedAt: DateTime(2022, 11, 9).millisecondsSinceEpoch,
        captureSource: CaptureSource.day,
        tieBreaker: name,
        colorHistogram: [1, for (var i = 1; i < colorHistogramBins; i++) 0],
      );
      final shots = [dayShot('a', 0), dayShot('b', _bits(16))];
      expect(clusterSimilar(shots), isEmpty);
    });
  });

  group('evaluateGrouping', () {
    test('counts pairwise precision and recall', () {
      final metrics = evaluateGrouping(
        truth: {'a': 's1', 'b': 's1', 'c': 's1', 'd': 's2'},
        predicted: [
          ['a', 'b'],
          ['c', 'd'],
        ],
      );
      expect(metrics.truePositives, 1);
      expect(metrics.falsePositives, 1);
      expect(metrics.falseNegatives, 2);
      expect(metrics.precision, 0.5);
      expect(metrics.recall, closeTo(1 / 3, 1e-9));
    });

    test('perfect grouping scores 1', () {
      final metrics = evaluateGrouping(
        truth: {'a': 's1', 'b': 's1', 'c': 's2'},
        predicted: [
          ['a', 'b'],
        ],
      );
      expect(metrics.precision, 1);
      expect(metrics.recall, 1);
      expect(metrics.f1, 1);
    });

    test('rejects predicted ids that have no label', () {
      expect(
        () => evaluateGrouping(
          truth: {'a': 's1'},
          predicted: [
            ['a', 'zzz'],
          ],
        ),
        throwsArgumentError,
      );
    });
  });
}
