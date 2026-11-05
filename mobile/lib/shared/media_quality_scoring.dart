/// One quality score for a photo or a video frame, 0-100, comparable only
/// with other items of the same moment. `shot_ranking.dart` implements it for
/// photos; the video tools will reuse it on frames.
abstract interface class MediaQualityScoring {
  double score(String uri);
}
