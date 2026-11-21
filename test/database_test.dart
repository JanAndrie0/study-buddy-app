// Database tests (Phase 2): an in-memory SQLite database, nothing on disk.

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:study_buddy/data/database.dart';
import 'package:study_buddy/services/reviewer_parser.dart';

void main() {
  late AppDatabase db;
  final now = DateTime.utc(2026, 11, 20, 8);
  final sample = ReviewerParser.parse(
    File('test/fixtures/sample_reviewer.json').readAsStringSync(),
    pageCount: 10,
  );

  DecksCompanion deck() => DecksCompanion.insert(
        title: sample.deckTitle,
        sourceFileName: 'LECT4.pdf',
        fileHash: 'abc123',
        pageCount: 10,
        language: sample.explanationLanguage,
      );

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('insertDeck saves the deck, every question and a card for each', () async {
    final deckId = await db.insertDeck(deck: deck(), items: sample.items, now: now);
    expect(await db.select(db.decks).get(), hasLength(1));
    final saved = await (db.select(db.questions)..where((q) => q.deckId.equals(deckId))).get();
    expect(saved, hasLength(6));
    expect(await db.select(db.cardStates).get(), hasLength(6));

    final mcq = saved.firstWhere((q) => q.type == 'multiple_choice');
    expect(mcq.choices, hasLength(4)); // List<String> survives the JSON column
    final modified = saved.firstWhere((q) => q.type == 'modified_true_false');
    expect(modified.underlinedWord, 'appraisal');
    expect(modified.correction, 'prevention');
  });

  test('new cards are due at save time, not before', () async {
    await db.insertDeck(deck: deck(), items: sample.items, now: now);
    expect(await db.countDue(now), 6);
    expect(await db.countDue(now.subtract(const Duration(minutes: 1))), 0);
  });

  test('an fsrs card survives a save and load round trip', () async {
    await db.insertDeck(deck: deck(), items: sample.items, now: now);
    final row = (await db.select(db.cardStates).get()).first;
    final reviewed = fsrs.Scheduler(enableFuzzing: false)
        .reviewCard(db.cardFrom(row), fsrs.Rating.good, reviewDateTime: now)
        .card;
    await db.into(db.cardStates).insertOnConflictUpdate(db.cardStateFrom(reviewed));

    final loaded = db.cardFrom(
      await (db.select(db.cardStates)..where((c) => c.questionId.equals(row.questionId))).getSingle(),
    );
    expect(loaded.state, reviewed.state);
    expect(loaded.stability, reviewed.stability);
    expect(loaded.due.isAtSameMomentAs(reviewed.due), isTrue);
    expect(await db.countDue(now), 5);
  });

  test('deleting a deck also deletes its questions, cards and notes', () async {
    final deckId =
        await db.insertDeck(deck: deck(), items: sample.items, notes: sample.notes, now: now);
    expect(await db.select(db.noteSections).get(), hasLength(2));
    await db.deleteDeck(deckId);
    expect(await db.select(db.questions).get(), isEmpty);
    expect(await db.select(db.cardStates).get(), isEmpty);
    expect(await db.select(db.noteSections).get(), isEmpty);
  });

  test('notes keep their order and points', () async {
    await db.insertDeck(deck: deck(), items: const [], notes: sample.notes, now: now);
    final rows = await (db.select(db.noteSections)..orderBy([(n) => OrderingTerm.asc(n.position)])).get();
    expect(rows.map((r) => r.heading), ['Cost of Quality (CoQ)', 'Failure costs']);
    expect(rows.first.points, hasLength(2));
    expect(rows.first.position, 0);
  });

  test('a failed save leaves nothing behind (transaction)', () async {
    // A deck row missing a required column makes the insert throw.
    await expectLater(
      db.insertDeck(deck: const DecksCompanion(title: Value('x')), items: sample.items),
      throwsA(anything),
    );
    expect(await db.select(db.decks).get(), isEmpty);
    expect(await db.select(db.questions).get(), isEmpty);
  });
}
