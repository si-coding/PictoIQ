import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/shared/event_grouping.dart';
import 'package:pictoiq_mobile/shared/similarity_grouping.dart';

const _hour = 60 * 60 * 1000;

EventInput _at(DateTime time, String name, {int? source}) => EventInput(
  capturedAt: time.millisecondsSinceEpoch,
  captureSource: source ?? CaptureSource.exif,
  tieBreaker: name,
);

void main() {
  group('clusterEvents', () {
    test('splits on gaps longer than three hours', () {
      final photos = [
        _at(DateTime(2024, 5, 1, 10, 0), 'a'),
        _at(DateTime(2024, 5, 1, 10, 20), 'b'),
        _at(DateTime(2024, 5, 1, 12, 50), 'c'), // 2h30 after b: same event
        _at(DateTime(2024, 5, 1, 18, 0), 'd'), // 5h10 later: new event
        _at(DateTime(2024, 5, 2, 9, 0), 'e'),
      ];
      final events = clusterEvents(photos);
      expect([for (final e in events) e.members.length], [3, 1, 1]);
      expect(events.first.members, [0, 1, 2]);
    });

    test('does not depend on input order', () {
      final photos = [
        _at(DateTime(2024, 5, 2, 9, 0), 'e'),
        _at(DateTime(2024, 5, 1, 10, 0), 'a'),
        _at(DateTime(2024, 5, 1, 10, 20), 'b'),
      ];
      final events = clusterEvents(photos);
      expect(events.length, 2);
      expect(events.first.members, [1, 2]);
      expect(events.last.members, [0]);
    });

    test('day-only photos form one event per day', () {
      final photos = [
        _at(DateTime(2022, 11, 9), 'a', source: CaptureSource.day),
        _at(DateTime(2023, 11, 27), 'b', source: CaptureSource.day),
        _at(DateTime(2022, 11, 9), 'c', source: CaptureSource.day),
      ];
      final events = clusterEvents(photos);
      expect([for (final e in events) e.members.length], [2, 1]);
      expect(events.first.isDayOnly, isTrue);
    });

    test('photos without a time go in one undated event, last', () {
      final photos = [
        const EventInput(
          capturedAt: 0,
          captureSource: CaptureSource.unknown,
          tieBreaker: 'x',
        ),
        _at(DateTime(2024, 5, 1, 10, 0), 'a'),
        const EventInput(
          capturedAt: 0,
          captureSource: CaptureSource.unknown,
          tieBreaker: 'y',
        ),
      ];
      final events = clusterEvents(photos);
      expect(events.length, 2);
      expect(events.last.isUndated, isTrue);
      expect(events.last.members.length, 2);
    });

    test('empty input gives no events', () {
      expect(clusterEvents(const []), isEmpty);
    });

    test('gap setting is respected', () {
      final photos = [
        _at(DateTime(2024, 5, 1, 10, 0), 'a'),
        _at(DateTime(2024, 5, 1, 11, 30), 'b'),
      ];
      expect(clusterEvents(photos, gapMs: _hour).length, 2);
      expect(clusterEvents(photos, gapMs: 2 * _hour).length, 1);
    });
  });

  group('eventLabel', () {
    test('shows date and time range for one day', () {
      final events = clusterEvents([
        _at(DateTime(2024, 5, 1, 9, 5), 'a'),
        _at(DateTime(2024, 5, 1, 11, 40), 'b'),
      ]);
      expect(eventLabel(events.single), '1 May 2024 · 09:05–11:40');
    });

    test('shows only the date for day-only photos', () {
      final events = clusterEvents([
        _at(DateTime(2022, 11, 9), 'a', source: CaptureSource.day),
      ]);
      expect(eventLabel(events.single), '9 Nov 2022');
    });

    test('shows both dates across midnight', () {
      final events = clusterEvents([
        _at(DateTime(2024, 12, 31, 23, 0), 'a'),
        _at(DateTime(2025, 1, 1, 1, 0), 'b'),
      ]);
      expect(eventLabel(events.single), '31 Dec 2024 – 1 Jan 2025');
    });

    test('labels undated photos', () {
      final events = clusterEvents(const [
        EventInput(
          capturedAt: 0,
          captureSource: CaptureSource.unknown,
          tieBreaker: 'x',
        ),
      ]);
      expect(eventLabel(events.single), 'Undated');
    });
  });
}
