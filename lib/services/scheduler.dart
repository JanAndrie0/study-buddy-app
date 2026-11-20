import 'package:fsrs/fsrs.dart';

import 'grader.dart';

/// Spaced repetition with the `fsrs` package (CLAUDE.md: no custom SRS math).
///
/// This class only translates between Study Buddy and fsrs:
/// - graded answers (right / wrong / partial) become fsrs [Rating]s;
/// - flashcards let the student pick Again / Hard / Good / Easy directly.
/// fsrs decides the next due date. Times are always UTC (fsrs requires it).
class ReviewScheduler {
  /// [fsrs] can be swapped in tests, e.g. `Scheduler(enableFuzzing: false)`
  /// so due dates are predictable.
  ReviewScheduler({Scheduler? fsrs}) : _fsrs = fsrs ?? Scheduler();

  final Scheduler _fsrs;

  /// A brand-new card for a question. New cards are due right away.
  Card newCard(int questionId, {DateTime? now}) =>
      Card(cardId: questionId, due: (now ?? DateTime.now()).toUtc());

  /// Maps a grade to an fsrs rating.
  /// Full marks → Good, at least half (enumeration partial credit, or
  /// modified true/false with a wrong correction) → Hard, otherwise → Again.
  Rating ratingFor(GradeResult grade) {
    if (grade.score >= 1.0) return Rating.good;
    if (grade.score >= 0.5) return Rating.hard;
    return Rating.again;
  }

  /// Applies one review and returns the updated card plus fsrs' review log.
  ({Card card, ReviewLog reviewLog}) review(
    Card card,
    Rating rating, {
    DateTime? now,
  }) =>
      _fsrs.reviewCard(card, rating, reviewDateTime: (now ?? DateTime.now()).toUtc());

  /// Whether the card should show up in "due today".
  bool isDue(Card card, {DateTime? now}) =>
      !card.due.isAfter((now ?? DateTime.now()).toUtc());
}
