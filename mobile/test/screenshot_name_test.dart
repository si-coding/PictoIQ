import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart';

void main() {
  test('recognises screenshots by file name or folder', () {
    expect(looksLikeScreenshotFile('Screenshot_20261112.jpg', 'a/b.jpg'), isTrue);
    expect(looksLikeScreenshotFile('IMG_1.jpg', 'Pictures/Screenshots/IMG_1.jpg'), isTrue);
    expect(looksLikeScreenshotFile('screen_shot (2).png', 'x.png'), isTrue);
    expect(looksLikeScreenshotFile('Screen Recording 1.png', 'x.png'), isTrue);
  });

  test('does not flag ordinary photos', () {
    expect(looksLikeScreenshotFile('IMG_2026.jpg', 'Camera/IMG_2026.jpg'), isFalse);
    expect(looksLikeScreenshotFile('beach.jpg', 'Camera/beach.jpg'), isFalse);
  });
}
