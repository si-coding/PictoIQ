import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart'
    show FolderScanPhoto;

/// Why a photo is probably clutter. Every photo gets at most one reason, the
/// first that applies in the order of [ClutterKind.values].
enum ClutterKind {
  screenshot('Screenshots', 'Pictures of your screen, not of life.'),
  document('Documents & receipts', 'Pages of text, receipts, notes and forms.'),
  blank('Blank or very dark', 'Black or white frames, pocket shots.'),
  blurry('Blurry', 'Soft all over, so nothing in focus.'),
  small('Tiny images', 'Very low resolution, such as forwards and stickers.');

  const ClutterKind(this.title, this.description);

  final String title;
  final String description;
}

/// One photo that looks like clutter, and why.
class ClutterItem {
  const ClutterItem({required this.photo, required this.kind});

  final FolderScanPhoto photo;
  final ClutterKind kind;
}

/// Tunable limits. Measured on the photo at analysis size, so they are the
/// same for every photo. They are cautious on purpose: the person always sees
/// the photos and confirms before anything is deleted.
class ClutterThresholds {
  const ClutterThresholds({
    this.blurrySharpness = 15,
    this.darkMeanLuma = 30,
    this.darkShadowShare = 0.6,
    this.smallMegapixels = 0.25,
  });

  /// Sharpness (see `ImageSignals.sharpness`) below this counts as blurry.
  final double blurrySharpness;

  /// Average brightness below this, together with [darkShadowShare] of almost
  /// black pixels, counts as a dark frame.
  final double darkMeanLuma;
  final double darkShadowShare;

  /// Images below this many megapixels are tiny.
  final double smallMegapixels;
}

/// Words in a file name or folder that mark a screenshot or screen recording
/// frame, across the usual Android makers.
final _screenshotWords = RegExp(
  r'screen[\s_\-]?shot|screen[\s_\-]?cap|screen[\s_\-]?record|screenshots',
  caseSensitive: false,
);

/// True when the file name or its folder says it is a screenshot.
bool looksLikeScreenshot(String name, String relativePath) =>
    _screenshotWords.hasMatch(name) || _screenshotWords.hasMatch(relativePath);

/// The reason [photo] is clutter, or null when it is a normal photo.
///
/// A photo with faces in it is never called a document, blurry or tiny: those
/// signals misfire on portraits, and people are what the app is for.
ClutterKind? clutterKindOf(
  FolderScanPhoto photo, {
  ClutterThresholds thresholds = const ClutterThresholds(),
}) {
  if (looksLikeScreenshot(photo.name, photo.relativePath)) {
    return ClutterKind.screenshot;
  }
  final features = photo.features;
  if (features == null) return null;
  final signals = features.signals;
  final hasFaces = (features.faces?.count ?? 0) > 0;
  if (photo.isDocumentLike) return ClutterKind.document;
  if (signals.isBlank ||
      (signals.meanLuma < thresholds.darkMeanLuma &&
          signals.shadowClip > thresholds.darkShadowShare)) {
    return ClutterKind.blank;
  }
  if (hasFaces) return null;
  if (signals.sharpness < thresholds.blurrySharpness) return ClutterKind.blurry;
  if (features.megapixels > 0 &&
      features.megapixels < thresholds.smallMegapixels) {
    return ClutterKind.small;
  }
  return null;
}

/// Every photo in [photos] that looks like clutter, biggest files first within
/// each kind so the most space is at the top.
List<ClutterItem> findClutter(
  Iterable<FolderScanPhoto> photos, {
  ClutterThresholds thresholds = const ClutterThresholds(),
}) {
  final items = <ClutterItem>[];
  for (final photo in photos) {
    final kind = clutterKindOf(photo, thresholds: thresholds);
    if (kind != null) items.add(ClutterItem(photo: photo, kind: kind));
  }
  items.sort((a, b) {
    final byKind = a.kind.index.compareTo(b.kind.index);
    if (byKind != 0) return byKind;
    final bySize = b.photo.size.compareTo(a.photo.size);
    return bySize != 0
        ? bySize
        : a.photo.relativePath.compareTo(b.photo.relativePath);
  });
  return items;
}
