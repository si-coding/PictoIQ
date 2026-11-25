import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/features/scan/scan_time_note.dart';

void main() {
  test('scanClock shows seconds with units', () {
    expect(scanClock(const Duration(seconds: 5)), '5s');
    expect(scanClock(const Duration(seconds: 59)), '59s');
    expect(scanClock(const Duration(seconds: 65)), '1m 05s');
    expect(scanClock(const Duration(minutes: 12, seconds: 9)), '12m 09s');
  });
}
