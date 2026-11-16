import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart';

void main() {
  test('scan concurrency grows with cores but stays between 3 and 6', () {
    expect(defaultScanConcurrency(2), 3);
    expect(defaultScanConcurrency(4), 3);
    expect(defaultScanConcurrency(8), 5);
    expect(defaultScanConcurrency(16), 6);
  });
}
