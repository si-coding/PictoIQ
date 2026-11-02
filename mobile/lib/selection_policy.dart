/// Decides which photos of a group to keep, as conservatively as possible.
///
/// The rules, in order:
///
/// 1. Photos the user marked to keep (thumbs-up) are always kept, and nothing
///    is chosen automatically for the rest.
/// 2. If the user prefers to choose for themselves, nothing is kept or
///    removed until they mark a photo.
/// 3. Otherwise the [keepCount] best-ranked photos the user has not rejected
///    are kept (one for a best shot, two for best moments). If the user
///    rejected every photo, the top-ranked one is kept anyway, so a group can
///    never lose all of its photos.
///
/// A group is [KeepDecision.needsReview] unless the user made the choice or
/// the grouping and ranking are both trustworthy ([confident]). Bulk actions
/// should skip groups that need review.
class KeepDecision {
  const KeepDecision({
    required this.keepIds,
    required this.isUserChoice,
    required this.needsReview,
  });

  /// Photos that will be kept. Empty means no decision has been made, and
  /// then [removals] is empty too.
  final Set<String> keepIds;

  /// True when the keep set comes from the user's thumbs-up marks.
  final bool isUserChoice;

  /// True when PictoIQ should not act on this group without a person looking
  /// at it first.
  final bool needsReview;

  bool get hasDecision => keepIds.isNotEmpty;

  /// The photos from [ids] that would be deleted. Never includes a kept
  /// photo, and is empty when no decision has been made.
  List<String> removals(Iterable<String> ids) => keepIds.isEmpty
      ? const []
      : [
          for (final id in ids)
            if (!keepIds.contains(id)) id,
        ];
}

/// [rankedIds] lists the group's photos best first. [liked] and [disliked]
/// are the user's thumbs-up and thumbs-down marks, and may include ids from
/// other groups.
KeepDecision decideKeepers({
  required List<String> rankedIds,
  required Set<String> liked,
  required Set<String> disliked,
  required bool manualOnly,
  required bool confident,
  int keepCount = 1,
}) {
  if (rankedIds.isEmpty) {
    return const KeepDecision(
      keepIds: {},
      isUserChoice: false,
      needsReview: true,
    );
  }

  final likedHere = {
    for (final id in rankedIds)
      if (liked.contains(id)) id,
  };
  if (likedHere.isNotEmpty) {
    return KeepDecision(
      keepIds: likedHere,
      isUserChoice: true,
      needsReview: false,
    );
  }

  if (manualOnly) {
    return const KeepDecision(
      keepIds: {},
      isUserChoice: false,
      needsReview: true,
    );
  }

  final keepers = [
    for (final id in rankedIds)
      if (!disliked.contains(id)) id,
  ].take(keepCount < 1 ? 1 : keepCount).toSet();
  return KeepDecision(
    keepIds: keepers.isEmpty ? {rankedIds.first} : keepers,
    isUserChoice: false,
    needsReview: !confident,
  );
}
