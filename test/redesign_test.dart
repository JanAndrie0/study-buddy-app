// Design feedback #1–4: bold terms, Match logic, study modes.
// In-memory database; no network.

import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' show Rating, Scheduler;
import 'package:study_buddy/data/database.dart';
import 'package:study_buddy/features/study/match_logic.dart';
import 'package:study_buddy/features/study/study_controller.dart';
import 'package:study_buddy/providers.dart';
import 'package:study_buddy/services/grader.dart';
import 'package:study_buddy/services/reviewer_parser.dart';
import 'package:study_buddy/services/scheduler.dart';
import 'package:study_buddy/widgets/rich_terms.dart';

void main() {
  group('bold terms (#1)', () {
    test('splits **bold** pieces', () {
      expect(splitBoldTerms('**Philosophy** comes from **philia**.'), [
        ('Philosophy', true),
        (' comes from ', false),
        ('philia', true),
        ('.', false),
      ]);
    });
    test('plain text stays one piece', () => expect(splitBoldTerms('No bold'), [('No bold', false)]));
    test('an unmatched ** is kept as plain text', () {
      expect(splitBoldTerms('a **b'), [('a **b', false)]);
    });
    test('stripBoldMarkers removes the markers', () {
      expect(stripBoldMarkers('**Appraisal cost** covers testing.'), 'Appraisal cost covers testing.');
    });
  });

  group('Match logic (#4)', () {
    final pairs = [for (var i = 0; i < 10; i++) ('Term $i', '**Meaning** $i')];

    test('uses at most 6 pairs = 12 tiles, each pair once as term and meaning', () {
      final tiles = buildMatchTiles(pairs, random: Random(1));
      expect(tiles, hasLength(12));
      for (var id = 0; id < 6; id++) {
        final pair = tiles.where((t) => t.pairId == id).toList();
        expect(pair.where((t) => t.isTerm), hasLength(1));
        expect(pair.where((t) => !t.isTerm), hasLength(1));
      }
      expect(tiles.any((t) => t.text.contains('**')), isFalse);
    });

    test('a term matches only its own meaning', () {
      final tiles = buildMatchTiles(pairs.take(2).toList(), random: Random(2));
      final term0 = tiles.firstWhere((t) => t.pairId == 0 && t.isTerm);
      final meaning0 = tiles.firstWhere((t) => t.pairId == 0 && !t.isTerm);
      final meaning1 = tiles.firstWhere((t) => t.pairId == 1 && !t.isTerm);
      expect(isMatch(term0, meaning0), isTrue);
      expect(isMatch(term0, meaning1), isFalse);
      expect(isMatch(term0, term0), isFalse);
    });

    test('long meanings are shortened', () {
      expect(shortMeaning('x' * 200).length, lessThanOrEqualTo(91));
    });
  });

  group('study modes (#2, #4)', () {
    final sample = ReviewerParser.parse(
      File('test/fixtures/sample_reviewer.json').readAsStringSync(),
      pageCount: 10,
    );
    late AppDatabase db;
    late int deckId;
    final now = DateTime.utc(2026, 11, 21, 2);

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      deckId = await db.insertDeck(
        deck: DecksCompanion.insert(
          title: 'Quality', sourceFileName: 'a.pdf', fileHash: 'h', pageCount: 10, language: 'english'),
        items: sample.items,
        now: DateTime.utc(2026, 11, 21, 1),
      );
    });
    tearDown(() => db.close());

    ProviderContainer container() {
      final c = ProviderContainer(overrides: [
        databaseProvider.overrideWith((ref) => db),
        clockProvider.overrideWith((ref) => () => now),
        reviewSchedulerProvider.overrideWith((ref) => ReviewScheduler(fsrs: Scheduler(enableFuzzing: false))),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('quiz mode loads only quiz types', () async {
      final c = container();
      await c.read(studyProvider.notifier).start(deckId: deckId, mode: StudyMode.quiz);
      final types = c.read(studyProvider).queue.map((s) => s.question.type).toSet();
      expect(types, isNot(contains('flashcard')));
      expect(types, isNotEmpty);
    });

    test('flashcards mode loads every flashcard, even when not due', () async {
      final c = container();
      final controller = c.read(studyProvider.notifier);
      await controller.start(deckId: deckId, mode: StudyMode.flashcards);
      expect(c.read(studyProvider).queue.map((s) => s.question.type).toSet(), {'flashcard'});
      await controller.rateFlashcard(Rating.good);
      expect(await db.select(db.reviewLogs).get(), hasLength(1)); // swipes are saved to FSRS
      // Not due anymore, but Flashcards mode still shows it.
      await controller.start(deckId: deckId, mode: StudyMode.flashcards);
      expect(c.read(studyProvider).queue, hasLength(1));
    });

    test('test mode saves nothing (practice only) and respects the limit', () async {
      final c = container();
      final controller = c.read(studyProvider.notifier);
      await controller.start(deckId: deckId, mode: StudyMode.test, types: {'multiple_choice', 'true_false'}, limit: 1);
      expect(c.read(studyProvider).queue, hasLength(1));
      await controller.submit(const GradeResult(isCorrect: false, score: 0));
      expect(c.read(studyProvider).phase, StudyPhase.done); // no feedback step in Test
      expect(await db.select(db.reviewLogs).get(), isEmpty);
    });

    test('B1: a flashcard rating shows the next card before the save finishes', () async {
      final c = container();
      final controller = c.read(studyProvider.notifier);
      await controller.start(deckId: deckId, mode: StudyMode.flashcards);
      final saving = controller.rateFlashcard(Rating.good); // not awaited yet
      expect(c.read(studyProvider).answers, hasLength(1)); // already moved on
      expect(c.read(studyProvider).phase, StudyPhase.done); // only 1 flashcard in the sample
      await saving;
      expect(await db.select(db.reviewLogs).get(), hasLength(1));
    });

    test('B3: a deck quiz shows new questions even past the daily limit', () async {
      await db.updateSettings(const AppSettingsCompanion(newCardsPerDay: Value(0)));
      final c = container();
      await c.read(studyProvider.notifier).start(deckId: deckId, mode: StudyMode.quiz);
      expect(c.read(studyProvider).queue, hasLength(5)); // the 5 quiz questions
    });

    test('B3: review says how many new cards the limit held back; Study anyway shows them', () async {
      await db.updateSettings(const AppSettingsCompanion(newCardsPerDay: Value(0)));
      final c = container();
      final controller = c.read(studyProvider.notifier);
      await controller.start();
      expect(c.read(studyProvider).queue, isEmpty);
      expect(c.read(studyProvider).heldBackNew, 6);
      await controller.start(ignoreNewLimit: true);
      expect(c.read(studyProvider).queue, hasLength(6));
    });

    test('restartWith reloads the still-learning cards', () async {
      final c = container();
      final controller = c.read(studyProvider.notifier);
      final cards = await db.loadDeckCards(deckId);
      await controller.restartWith([cards.first.question.id]);
      expect(c.read(studyProvider).queue.single.question.id, cards.first.question.id);
    });
  });
}
