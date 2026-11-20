import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

import '../models/reviewer_item.dart';

part 'database.g.dart';

// Run after changing any table:
//   dart run build_runner build
// and bump schemaVersion + add a migration step (CLAUDE.md rule).

/// Stores a `List<String>` as a JSON text column (choices, accepted answers, items).
class StringListConverter extends TypeConverter<List<String>, String> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) =>
      (jsonDecode(fromDb) as List).whereType<String>().toList();

  @override
  String toSql(List<String> value) => jsonEncode(value);
}

/// One reviewer = one uploaded lecture PDF.
class Decks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  TextColumn get subject => text().withDefault(const Constant(''))();
  TextColumn get sourceFileName => text()();

  /// SHA-256 of the PDF, to spot re-uploads of the same file.
  TextColumn get fileHash => text()();
  IntColumn get pageCount => integer()();

  /// Explanation language: english / filipino / taglish.
  TextColumn get language => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// The questions of a deck (one row per ReviewerItem).
class Questions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get deckId => integer().references(Decks, #id, onDelete: KeyAction.cascade)();

  /// QuestionType.jsonName, e.g. "modified_true_false".
  TextColumn get type => text()();
  TextColumn get prompt => text()();
  TextColumn get answer => text()();
  TextColumn get acceptedAnswers =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  TextColumn get choices =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  TextColumn get items =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  TextColumn get underlinedWord => text().nullable()();
  TextColumn get correction => text().nullable()();
  TextColumn get explanation => text()();
  IntColumn get sourcePage => integer()();
  TextColumn get difficulty => text().withDefault(const Constant('medium'))();
}

/// FSRS memory state for each question (mirrors fsrs' Card).
class CardStates extends Table {
  IntColumn get questionId =>
      integer().references(Questions, #id, onDelete: KeyAction.cascade)();

  /// fsrs State value: 1 learning, 2 review, 3 relearning.
  IntColumn get state => integer()();
  IntColumn get step => integer().nullable()();
  RealColumn get stability => real().nullable()();
  RealColumn get difficulty => real().nullable()();
  DateTimeColumn get due => dateTime()();
  DateTimeColumn get lastReview => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {questionId};
}

/// Every answer, for stats and for checking the grader later.
class ReviewLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get questionId =>
      integer().references(Questions, #id, onDelete: KeyAction.cascade)();

  /// fsrs Rating value: 1 again, 2 hard, 3 good, 4 easy.
  IntColumn get rating => integer()();
  BoolColumn get wasCorrect => boolean()();
  TextColumn get answeredText => text().nullable()();
  DateTimeColumn get reviewedAt => dateTime()();
}

@DriftDatabase(tables: [Decks, Questions, CardStates, ReviewLogs])
class AppDatabase extends _$AppDatabase {
  /// Pass an executor in tests (e.g. NativeDatabase.memory()); the app uses
  /// a file in the phone's app storage.
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'study_buddy'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        // v1 is the first version: future versions add steps here, e.g.
        // if (from < 2) await m.addColumn(decks, decks.someNewColumn);
        onUpgrade: (m, from, to) async {},
        beforeOpen: (details) async {
          // SQLite ignores ON DELETE CASCADE unless this is on.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Saves a generated deck, its questions and a new FSRS card for each
  /// question in ONE transaction: either everything is saved or nothing is.
  Future<int> insertDeck({
    required DecksCompanion deck,
    required List<ReviewerItem> items,
    DateTime? now,
  }) {
    return transaction(() async {
      final deckId = await into(decks).insert(deck);
      final dueNow = (now ?? DateTime.now()).toUtc();
      for (final item in items) {
        final questionId = await into(questions).insert(
          QuestionsCompanion.insert(
            deckId: deckId,
            type: item.type.jsonName,
            prompt: item.prompt,
            answer: item.answer,
            acceptedAnswers: Value(item.acceptedAnswers),
            choices: Value(item.choices),
            items: Value(item.items),
            underlinedWord: Value(item.underlinedWord),
            correction: Value(item.correction),
            explanation: item.explanation,
            sourcePage: item.sourcePage,
            difficulty: Value(item.difficulty),
          ),
        );
        final card = fsrs.Card(cardId: questionId, due: dueNow);
        await into(cardStates).insert(cardStateFrom(card));
      }
      return deckId;
    });
  }

  /// Number of questions due at [now] (for Home's "due today").
  Future<int> countDue(DateTime now) async {
    final count = cardStates.questionId.count();
    final query = selectOnly(cardStates)
      ..addColumns([count])
      ..where(cardStates.due.isSmallerOrEqualValue(now.toUtc()));
    return (await query.getSingle()).read(count) ?? 0;
  }

  /// Converts an fsrs Card to a row (insert or replace).
  CardStatesCompanion cardStateFrom(fsrs.Card card) => CardStatesCompanion.insert(
        questionId: Value(card.cardId),
        state: card.state.value,
        step: Value(card.step),
        stability: Value(card.stability),
        difficulty: Value(card.difficulty),
        due: card.due,
        lastReview: Value(card.lastReview),
      );

  /// Converts a row back to an fsrs Card.
  fsrs.Card cardFrom(CardState row) => fsrs.Card(
        cardId: row.questionId,
        state: fsrs.State.fromValue(row.state),
        step: row.step,
        stability: row.stability,
        difficulty: row.difficulty,
        due: row.due.toUtc(),
        lastReview: row.lastReview?.toUtc(),
      );
}
