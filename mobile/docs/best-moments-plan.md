# Best Moments: development plan

Goal: discover meaningful moments (events > moments > best 1-3 photos), not just similar photos. Best Shot stays separate (one winner from near-identical shots). Everything on device; nothing deleted from Best Moments.

## Status against the brief

| Item | Status |
|---|---|
| Events by time gaps (`shared/event_grouping.dart`) | Done |
| Moments inside an event: time window + visual + clothing + composition | Done (heuristic, untuned) |
| Configurable: moment length, photos per moment, variety, expressions, clothing strictness, split portraits/couples/groups | Done (Settings > Best moments) |
| Photo quality kept separate from moment grouping | Done (`shared/shot_ranking.dart` vs `features/photos/best_moments/moment_selection.dart`) |
| Diversity-aware picks (MMR), faults penalised, smiles tunable (candid not punished) | Done |
| One primary moment per photo | Done (clustering) |
| Results summary: events / moments / recommended photos | Done |
| Alternatives kept for review | Done (Details, photo viewer) |
| Composition-specific quality weights (portrait, couple, group, scene) | Done (`CompositionProfile`; starting values) |
| Evaluation tool (grouping precision/recall, pick diversity, missed moments) | Done: `tool/evaluate_moments.dart`; needs your labelled photos |
| Labelled test gallery (100+ photos, several events) | Next (you) |
| In-app "good picks?" thumbs up/down, to measure agreement | Skipped for now (decided Nov 2026) |
| Location signal: EXIF GPS keeps different places apart (Settings > Best moments > Keep different places apart, off by default; no new permission, so Android may hide GPS) | Done |
| Scene/activity labels (needs an on-device model) | Later |
| Recurring person identification (local, opt-in) | Later |
| Personalised ranking, cross-event memories | Later |

## Next steps, in order

1. ~~Composition strategies~~ (done: eyes, smile, cut-off and people-in-frame weights per photo type).
2. **Test gallery and evaluation.** Label helper: `dart run tool/make_labels.dart <folder>` proposes labels and a review page to correct. Tool is built (`dart run tool/evaluate_moments.dart <folder> <labels.csv>`, labels `file,moment[,faces[,quality]]`). Remaining: label a gallery and tune thresholds from its output. Original scope: A small labelled set of real photos (several events, same people across events, solo and group, missing timestamps, poor shots) plus a script that reports grouping accuracy, diversity of picks and missed moments. Use it to tune the time and similarity thresholds.
3. ~~Feedback signal.~~ Skipped for now. Original idea: A thumbs up/down on picks, stored locally, to measure how often users agree with the recommendations (the main success metric).
4. **Optional signals.** ~~EXIF GPS as a location split~~ (done, off by default). Next: a small on-device scene model, behind a setting.
