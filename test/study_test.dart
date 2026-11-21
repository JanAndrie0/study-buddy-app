// Study sessions (Phase 4): queue, daily new-card limit, saving answers.
// In-memory database + a fixed clock; no network.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' show Rating, Scheduler;
import 'package:study_buddy/data/database.dart';
import 'package:study_buddy/features/study/study_controller.dart';
import 'package:study_buddy/providers.dart';
import 'package:study_buddy/services/grader.dart';
import 'package:study_buddy/services/reviewer_parser.dart';
import 'package:study_buddy/services/scheduler.dart';

void main() {
  final sample = ReviewerParser.parse(
    File('test/fixtures/sample_reviewer.json').readAsStringSync(),
    pageCount: 10,
  );
  final created = DateTime.utc(2026, 11, 20, 1);
  late AppDatabase db;
  late DateTime now;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 11, 20, 2);
    await db.insertDeck(
      deck: DecksCompanion.insert(
        title: 'Quality',
        sourceFileName: 'a.pdf',
        fileHash: 'h',
        pageCount: 10,
        language: 'taglish',
      ),
      items: sample.items,
      now: created,
    );
  });
  tearDown(() => db.close());

  ProviderContainer makeContainer() {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) => db),
      clockProvider.overrideWith((ref) => () => now),
      reviewSchedulerProvider.overrideWith((ref) => ReviewScheduler(fsrs: Scheduler(enableFuzzing: false))),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  group('database queue', () {
    test('new cards are limited per day', () async {
      final queue = await db.loadStudyQueue(now: now, newCardsPerDay: 4);
      expect(queue, hasLength(4));
      expect(queue.every((c) => c.isNew), isTrue);
    });

    test('nothing is due before the cards were created', () async {
      final queue = await db.loadStudyQueue(now: created.subtract(const Duration(hours: 1)), newCardsPerDay: 20);
      expect(queue, isEmpty);
    });

    test('settings row is created with defaults', () async {
      final settings = await db.getSettings();
      expect(settings.language, 'english');
      expect(settings.newCardsPerDay, 20);
      expect(settings.themeMode, 'system');
      expect(settings.onboardingDone, isFalse);
      await db.updateSettings(const AppSettingsCompanion(newCardsPerDay: Value(5)));
      expect((await db.getSettings()).newCardsPerDay, 5);
    });
  });

  group('study session', () {
    test('answers are graded, saved and move to the summary', () async {
      final container = makeContainer();
      final controller = container.read(studyProvider.notifier);
      await controller.start();
      var state = container.read(studyProvider);
      expect(state.phase, StudyPhase.answering);
      expect(state.queue, hasLength(6));

      // Answer every card: flashcards get "Good", the rest are graded correct.
      while (container.read(studyProvider).phase != StudyPhase.done) {
        state = container.read(studyProvider);
        if (state.item!.type.jsonName == 'flashcard') {
          await controller.rateFlashcard(Rating.good);
        } else {
          await controller.submit(const GradeResult(isCorrect: true, score: 1), answeredText: 'x');
          expect(container.read(studyProvider).phase, StudyPhase.feedback);
          controller.next();
        }
      }

      state = container.read(studyProvider);
      expect(state.correctCount, 6);
      expect(await db.select(db.reviewLogs).get(), hasLength(6));
      // Everything was answered correctly, so nothing is due right now.
      expect(await db.loadStudyQueue(now: now, newCardsPerDay: 20), isEmpty);
    });

    test('a wrong answer brings the card back sooner than a right one', () async {
      final container = makeContainer();
      final controller = container.read(studyProvider.notifier);
      await controller.start();
      final first = container.read(studyProvider).current!;
      await controller.submit(const GradeResult(isCorrect: false, score: 0));
      controller.next();
      final second = container.read(studyProvider).current!;
      await controller.submit(const GradeResult(isCorrect: true, score: 1));

      final states = {for (final s in await db.select(db.cardStates).get()) s.questionId: s};
      expect(states[first.question.id]!.due.isBefore(states[second.question.id]!.due), isTrue);
      final logs = await db.select(db.reviewLogs).get();
      expect(logs.first.wasCorrect, isFalse);
      expect(logs.first.rating, Rating.again.value);
    });

    test('new cards studied today count against tomorrow-less limit', () async {
      await db.updateSettings(const AppSettingsCompanion(newCardsPerDay: Value(2)));
      final container = makeContainer();
      final controller = container.read(studyProvider.notifier);
      await controller.start();
      expect(container.read(studyProvider).queue, hasLength(2));
      await controller.submit(const GradeResult(isCorrect: true, score: 1));
      controller.next();
      await controller.submit(const GradeResult(isCorrect: true, score: 1));

      // Same day, new session: the 2 new cards for today are used up.
      final again = await db.loadStudyQueue(now: now, newCardsPerDay: 2);
      expect(again.where((c) => c.isNew), isEmpty);
    });

    test('nothing due goes straight to the summary', () async {
      now = created.subtract(const Duration(hours: 1));
      final container = makeContainer();
      await container.read(studyProvider.notifier).start();
      expect(container.read(studyProvider).phase, StudyPhase.done);
    });
  });
}
