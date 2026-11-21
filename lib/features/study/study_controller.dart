import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' show Rating;

import '../../data/database.dart';
import '../../models/reviewer_item.dart';
import '../../providers.dart';
import '../../services/grader.dart';

enum StudyPhase { loading, answering, feedback, done }

enum StudyMode { review, quiz, flashcards, test }

/// The 5 quiz formats (everything except flashcards).
const quizTypeNames = {
  'multiple_choice',
  'identification',
  'modified_true_false',
  'enumeration',
  'true_false',
};

/// What happened to one card in this session (for feedback + summary).
class StudyAnswer {
  const StudyAnswer({required this.card, required this.grade, this.answeredText});
  final StudyCard card;
  final GradeResult grade;
  final String? answeredText;
}

class StudyState {
  const StudyState({
    this.phase = StudyPhase.loading,
    this.queue = const [],
    this.index = 0,
    this.answers = const [],
    this.heldBackNew = 0,
  });

  final StudyPhase phase;
  final List<StudyCard> queue;
  final int index;
  final List<StudyAnswer> answers;

  /// Review only: new cards left out because today's new-card limit is used
  /// up (bug B3), so the screen can say so and offer "Study anyway".
  final int heldBackNew;

  StudyCard? get current => index < queue.length ? queue[index] : null;
  ReviewerItem? get item => current?.question.toItem();
  StudyAnswer? get lastAnswer => answers.isEmpty ? null : answers.last;
  int get correctCount => answers.where((a) => a.grade.isCorrect).length;

  StudyState copyWith({StudyPhase? phase, List<StudyCard>? queue, int? index, List<StudyAnswer>? answers}) =>
      StudyState(
        phase: phase ?? this.phase,
        queue: queue ?? this.queue,
        index: index ?? this.index,
        answers: answers ?? this.answers,
        heldBackNew: heldBackNew,
      );
}

/// One review session. Fully offline: grading is local Dart rules (ADR-004),
/// scheduling is fsrs, and every answer is saved right away so closing the
/// app mid-session loses nothing.
class StudyController extends Notifier<StudyState> {
  @override
  StudyState build() => const StudyState();

  StudyMode _mode = StudyMode.review;
  StudyMode get mode => _mode;

  /// Loads the cards for a mode (design feedback #2 and #4):
  /// - review: everything due (Home's "Mag-review na"), deck or all decks,
  ///   with the daily new-card limit unless [ignoreNewLimit];
  /// - quiz: due quiz questions of one deck, new ones included: the student
  ///   picked this deck on purpose, so no daily limit (bug B3);
  /// - flashcards: ALL flashcards of one deck, due or not (still saved to FSRS);
  /// - test: [types] of one deck, shuffled, up to [limit]; practice only.
  Future<void> start({
    int? deckId,
    StudyMode mode = StudyMode.review,
    Set<String>? types,
    int? limit,
    bool ignoreNewLimit = false,
  }) async {
    _mode = mode;
    final db = ref.read(databaseProvider);
    final settings = await db.getSettings();
    final now = ref.read(clockProvider)();
    const noLimit = 1 << 30;
    if (mode == StudyMode.review) {
      final queue = await db.loadStudyQueue(
          deckId: deckId, now: now, newCardsPerDay: ignoreNewLimit ? noLimit : settings.newCardsPerDay);
      final all = ignoreNewLimit ? queue : await db.loadStudyQueue(deckId: deckId, now: now, newCardsPerDay: noLimit);
      state = StudyState(
        phase: queue.isEmpty ? StudyPhase.done : StudyPhase.answering,
        queue: queue,
        heldBackNew: all.length - queue.length,
      );
      return;
    }
    final queue = switch (mode) {
      StudyMode.review => const <StudyCard>[], // handled above
      StudyMode.quiz => await db.loadStudyQueue(
          deckId: deckId, now: now, newCardsPerDay: noLimit, types: quizTypeNames),
      StudyMode.flashcards => await db.loadDeckCards(deckId!, types: const {'flashcard'}),
      StudyMode.test => ((await db.loadDeckCards(deckId!, types: types ?? quizTypeNames))..shuffle())
          .take(limit ?? 1 << 30)
          .toList(),
    };
    state = StudyState(phase: queue.isEmpty ? StudyPhase.done : StudyPhase.answering, queue: queue);
  }

  /// Flashcards mode: go again through the cards marked "still learning".
  Future<void> restartWith(List<int> questionIds) async {
    final queue = await ref.read(databaseProvider).loadCardsByIds(questionIds);
    state = StudyState(phase: queue.isEmpty ? StudyPhase.done : StudyPhase.answering, queue: queue);
  }

  /// A graded answer (every type except flashcards). Quiz/review show
  /// feedback next; Test moves straight on and saves nothing (practice only).
  Future<void> submit(GradeResult grade, {String? answeredText}) async {
    final card = state.current;
    if (card == null || state.phase != StudyPhase.answering) return;
    final answer = StudyAnswer(card: card, grade: grade, answeredText: answeredText);
    if (_mode == StudyMode.test) {
      state = state.copyWith(answers: [...state.answers, answer]);
      next();
      return;
    }
    final rating = ref.read(reviewSchedulerProvider).ratingFor(grade);
    await _save(card, rating, grade.isCorrect, answeredText);
    state = state.copyWith(phase: StudyPhase.feedback, answers: [...state.answers, answer]);
  }

  /// Flashcards: the student rates how well they remembered, then we move on.
  Future<void> rateFlashcard(Rating rating) async {
    final card = state.current;
    if (card == null || state.phase != StudyPhase.answering) return;
    final remembered = rating != Rating.again;
    // Show the next card FIRST, then save (bug B1): a swiped card must leave
    // the screen in the same frame, or Flutter flashes a "dismissed
    // Dismissible is still part of the tree" error while the save runs.
    state = state.copyWith(answers: [
      ...state.answers,
      StudyAnswer(card: card, grade: GradeResult(isCorrect: remembered, score: remembered ? 1 : 0)),
    ]);
    next();
    await _save(card, rating, remembered, null);
  }

  /// Next card, or the summary after the last one.
  void next() {
    final nextIndex = state.index + 1;
    state = state.copyWith(
      index: nextIndex,
      phase: nextIndex >= state.queue.length ? StudyPhase.done : StudyPhase.answering,
    );
  }

  Future<void> _save(StudyCard card, Rating rating, bool wasCorrect, String? answeredText) async {
    final db = ref.read(databaseProvider);
    final now = ref.read(clockProvider)().toUtc();
    final reviewed = ref.read(reviewSchedulerProvider).review(db.cardFrom(card.state), rating, now: now);
    await db.recordReview(
      card: reviewed.card,
      rating: rating.value,
      wasCorrect: wasCorrect,
      answeredText: answeredText,
      reviewedAt: now,
    );
  }
}

final studyProvider = NotifierProvider.autoDispose<StudyController, StudyState>(StudyController.new);
