/// The elapsed time of a scan as a short clock with units: "42s" under a
/// minute, then "1m 05s".
String scanClock(Duration elapsed) {
  final seconds = elapsed.inSeconds % 60;
  if (elapsed.inMinutes == 0) return '${seconds}s';
  return '${elapsed.inMinutes}m ${seconds.toString().padLeft(2, '0')}s';
}
