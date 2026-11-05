import 'package:pictoiq_mobile/shared/similarity_grouping.dart';

/// A photo's place in time, for [clusterEvents].
class EventInput {
  const EventInput({
    required this.capturedAt,
    required this.captureSource,
    required this.tieBreaker,
  });

  final int capturedAt;
  final int captureSource;
  final String tieBreaker;
}

/// A run of photos taken around the same time (a trip day, a party, an
/// outing). Events are only for browsing: they never decide what to delete.
class PhotoEvent {
  const PhotoEvent({
    required this.members,
    required this.startMs,
    required this.endMs,
    required this.source,
  });

  /// Indexes into the list given to [clusterEvents], in time order.
  final List<int> members;
  final int startMs;
  final int endMs;
  final int source;

  bool get isUndated => source == CaptureSource.unknown;

  /// Only the day is known, so there is no time of day to show.
  bool get isDayOnly => source == CaptureSource.day;
}

/// Splits photos into events: a new event starts when the gap to the previous
/// photo is longer than [gapMs] (default 3 hours), when only-the-day photos
/// change day, or when the time source changes. Photos without any time form
/// one undated event. Events are returned oldest first, undated last.
List<PhotoEvent> clusterEvents(
  List<EventInput> photos, {
  int gapMs = 3 * 60 * 60 * 1000,
}) {
  final order = List<int>.generate(photos.length, (index) => index)
    ..sort((a, b) {
      final left = photos[a];
      final right = photos[b];
      final bySource = left.captureSource.compareTo(right.captureSource);
      if (bySource != 0) return bySource;
      final byTime = left.capturedAt.compareTo(right.capturedAt);
      return byTime != 0
          ? byTime
          : left.tieBreaker.compareTo(right.tieBreaker);
    });

  final events = <PhotoEvent>[];
  var members = <int>[];
  var start = 0;
  var end = 0;
  var source = -1;
  void close() {
    if (members.isEmpty) return;
    events.add(
      PhotoEvent(members: members, startMs: start, endMs: end, source: source),
    );
    members = <int>[];
  }

  for (final index in order) {
    final photo = photos[index];
    final unknown = photo.captureSource == CaptureSource.unknown;
    final gap = photo.capturedAt - end;
    final startsNew =
        members.isEmpty ||
        photo.captureSource != source ||
        (!unknown &&
            (photo.captureSource == CaptureSource.day ? gap > 0 : gap > gapMs));
    if (startsNew) {
      close();
      start = photo.capturedAt;
      source = photo.captureSource;
    }
    members.add(index);
    end = photo.capturedAt;
  }
  close();

  events.sort((a, b) {
    if (a.isUndated != b.isUndated) return a.isUndated ? 1 : -1;
    return a.startMs.compareTo(b.startMs);
  });
  return events;
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _two(int value) => value.toString().padLeft(2, '0');

/// A short heading such as `9 Nov 2022 · 14:05–16:40`, or `Undated`.
String eventLabel(PhotoEvent event) {
  if (event.isUndated) return 'Undated';
  final first = DateTime.fromMillisecondsSinceEpoch(event.startMs);
  final last = DateTime.fromMillisecondsSinceEpoch(event.endMs);
  String day(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
  final sameDay =
      first.year == last.year &&
      first.month == last.month &&
      first.day == last.day;
  if (event.isDayOnly) return day(first);
  String clock(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';
  if (!sameDay) return '${day(first)} – ${day(last)}';
  if (clock(first) == clock(last)) return '${day(first)} · ${clock(first)}';
  return '${day(first)} · ${clock(first)}–${clock(last)}';
}
