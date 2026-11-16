import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/core/config/app_limits.dart';
import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart';

void main() {
  test('owner limits are 9 to share, 9 in a reel, 500 per scan', () {
    expect(AppLimits.shareMaxPhotos, 9);
    expect(AppLimits.reelMaxPhotos, 9);
    expect(AppLimits.scanMaxPhotos, 500);
  });

  test('a scan keeps the newest photos when there are too many', () {
    final times = [5, 0, 9, 1, 7];
    expect(newestWithinLimit(times, (t) => t, 3), [9, 7, 5]);
    expect(newestWithinLimit(times, (t) => t, 5), times);
    expect(newestWithinLimit(times, (t) => t, 10), times);
  });
}
