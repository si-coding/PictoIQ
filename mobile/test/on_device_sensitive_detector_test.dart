import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/shared/on_device_sensitive_detector.dart';

void main() {
  final bytes = Uint8List.fromList([1, 2, 3]);

  test('loads the model once and returns the score', () async {
    var loads = 0;
    final detector = OnDeviceSensitiveDetector(
      initialize: () async => loads++,
      scorer: (_) async => 0.8,
    );
    expect(detector.isAvailable, isTrue);
    expect(await detector.score(bytes), 0.8);
    expect(await detector.score(bytes), 0.8);
    expect(loads, 1);
  });

  test('a model that cannot load makes the detector unavailable', () async {
    final detector = OnDeviceSensitiveDetector(
      initialize: () async => throw StateError('no model'),
      scorer: (_) async => 0.9,
    );
    expect(await detector.score(bytes), isNull);
    expect(detector.isAvailable, isFalse);
  });

  test('a picture that cannot be scored gives no score, not a crash', () async {
    final detector = OnDeviceSensitiveDetector(
      initialize: () async {},
      scorer: (_) async => throw StateError('bad image'),
    );
    expect(await detector.score(bytes), isNull);
    expect(detector.isAvailable, isTrue);
  });
}
