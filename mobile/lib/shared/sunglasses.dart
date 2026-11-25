import 'dart:math' as math;
import 'dart:typed_data';

/// Whether both eyes are hidden behind dark glasses.
///
/// The face detector cannot see eyes through sunglasses, so its "eyes open"
/// number is unreliable there (often low, which would wrongly mark a cool,
/// deliberate shot as a blink). This looks at the pixels around each eye and
/// compares them with the cheek below: dark lenses are much darker than skin,
/// while open or closed eyes are only a little darker, and darker skin tones
/// stay about as dark around the eyes as on the cheek.
///
/// [rgba] is the image the detector saw (width x height x 4 bytes); the eye
/// positions are in the same pixels. Returns false when the eyes are too close
/// to the edge to measure, or too close together to be two eyes.
bool eyesHiddenBySunglasses(
  Uint8List rgba,
  int width,
  int height, {
  required (double, double) leftEye,
  required (double, double) rightEye,
  double darkRatio = 0.62,
  double darkLuma = 95,
}) {
  if (rgba.length < width * height * 4) return false;
  final dx = rightEye.$1 - leftEye.$1;
  final dy = rightEye.$2 - leftEye.$2;
  final gap = math.sqrt(dx * dx + dy * dy);
  if (gap < 12) return false;
  final half = math.max(2.0, gap * 0.18);

  double? mean(double cx, double cy) {
    final x0 = (cx - half).round();
    final x1 = (cx + half).round();
    final y0 = (cy - half).round();
    final y1 = (cy + half).round();
    if (x0 < 0 || y0 < 0 || x1 >= width || y1 >= height) return null;
    var sum = 0.0;
    var count = 0;
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final i = (y * width + x) * 4;
        sum += 0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2];
        count++;
      }
    }
    return count == 0 ? null : sum / count;
  }

  final left = mean(leftEye.$1, leftEye.$2);
  final right = mean(rightEye.$1, rightEye.$2);
  // Skin reference: the cheeks, straight below each eye.
  final leftCheek = mean(leftEye.$1, leftEye.$2 + gap * 0.65);
  final rightCheek = mean(rightEye.$1, rightEye.$2 + gap * 0.65);
  if (left == null || right == null) return false;
  final skin = [leftCheek, rightCheek].whereType<double>();
  if (skin.isEmpty) return false;
  final reference = skin.reduce((a, b) => a + b) / skin.length;
  if (reference <= 1) return false;
  bool dark(double eye) => eye < darkLuma && eye < reference * darkRatio;
  return dark(left) && dark(right);
}
