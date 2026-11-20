// Scheduler tests (Phase 2): our mapping to fsrs, with fuzzing off so due
// dates are predictable.

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart';
import 'package:study_buddy/services/grader.dart';
import 'package:study_buddy/services/scheduler.dart';

void main() {
  final scheduler = ReviewScheduler(fsrs: Scheduler(enableFuzzing: false));
  final now = DateTime.utc(2026, 11, 20, 8);

  test('a new card is due right away and in the learning state', () {
    final card = scheduler.newCard(1, now: now);
    expect(card.cardId, 1);
    expect(card.state, State.learning);
    expect(scheduler.isDue(card, now: now), isTrue);
  });

  test('grades map to ratings', () {
    expect(scheduler.ratingFor(const GradeResult(isCorrect: true, score: 1.0)), Rating.good);
    expect(scheduler.ratingFor(const GradeResult(isCorrect: false, score: 0.5)), Rating.hard);
    expect(scheduler.ratingFor(const GradeResult(isCorrect: false, score: 0.75)), Rating.hard);
    expect(scheduler.ratingFor(const GradeResult(isCorrect: false, score: 0.25)), Rating.again);
    expect(scheduler.ratingFor(const GradeResult(isCorrect: false, score: 0.0)), Rating.again);
  });

  test('Again brings the card back sooner than Good', () {
    final card = scheduler.newCard(1, now: now);
    final again = scheduler.review(card, Rating.again, now: now).card;
    final good = scheduler.review(card, Rating.good, now: now).card;
    expect(again.due.isBefore(good.due), isTrue);
    expect(again.due.difference(now), lessThanOrEqualTo(const Duration(minutes: 10)));
  });

  test('a reviewed card is not due until its due date', () {
    final card = scheduler.review(scheduler.newCard(1, now: now), Rating.good, now: now).card;
    expect(scheduler.isDue(card, now: now), isFalse);
    expect(scheduler.isDue(card, now: card.due), isTrue);
  });

  test('repeated Good answers move the card to review with growing gaps', () {
    var card = scheduler.newCard(1, now: now);
    var time = now;
    final gaps = <Duration>[];
    for (var i = 0; i < 4; i++) {
      final reviewed = scheduler.review(card, Rating.good, now: time).card;
      gaps.add(reviewed.due.difference(time));
      time = reviewed.due;
      card = reviewed;
    }
    expect(card.state, State.review);
    expect(gaps.last, greaterThan(gaps[gaps.length - 2]));
    expect(gaps.last, greaterThanOrEqualTo(const Duration(days: 2)));
  });

  test('review log records the rating and time', () {
    final log = scheduler.review(scheduler.newCard(7, now: now), Rating.hard, now: now).reviewLog;
    expect(log.cardId, 7);
    expect(log.rating, Rating.hard);
    expect(log.reviewDateTime, now);
  });
}
