import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

import '../models/reviewer_item.dart';
import 'database.steps.dart';

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

/// Lecture notes: key points by topic (added in schema v2, ADR-008).
/// The row class is NoteSectionRow so it doesn't clash with the model
/// class NoteSection in reviewer_item.dart.
@DataClassName('NoteSectionRow')
class NoteSections extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get deckId => integer().references(Decks, #id, onDelete: KeyAction.cascade)();

  /// Order in the lecture (0, 1, 2…).
  IntColumn get position => integer()();
  TextColumn get heading => text()();
  TextColumn get points => text().map(const StringListConverter())();
  IntColumn get sourcePage => integer()();
}

/// App settings: one row (id = 1). Added in schema v3 (Phase 4).
class AppSettings extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();

  /// Default explanation language for new decks (ADR-009: English).
  TextColumn get language => text().withDefault(const Constant('english'))();

  /// Max brand-new cards introduced per day (reviews are not limited).
  IntColumn get newCardsPerDay => integer().withDefault(const Constant(20))();

  /// "system", "light" or "dark".
  TextColumn get themeMode => text().withDefault(const Constant('system'))();

  /// Set after the 3 onboarding screens (Phase 5).
  BoolColumn get onboardingDone => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Turns a saved question row back into the model the grader uses.
extension QuestionToItem on Question {
  ReviewerItem toItem() => ReviewerItem(
        type: QuestionType.fromJsonName(type) ?? QuestionType.flashcard,
        sourcePage: sourcePage,
        prompt: prompt,
        answer: answer,
        explanation: explanation,
        difficulty: difficulty,
        choices: choices,
        acceptedAnswers: acceptedAnswers,
        items: items,
        underlinedWord: underlinedWord,
        correction: correction,
      );
}

/// A question with its FSRS state, ready to study.
class StudyCard {
  const StudyCard({required this.question, required this.state});
  final Question question;
  final CardState state;

  /// Never reviewed yet.
  bool get isNew => state.lastReview == null;
}

/// A deck plus how many questions and note sections it has (for Home).
class DeckSummary {
  const DeckSummary({required this.deck, required this.questionCount, this.noteCount = 0});
  final Deck deck;
  final int questionCount;
  final int noteCount;
}

@DriftDatabase(tables: [Decks, Questions, CardStates, ReviewLogs, NoteSections, AppSettings])
class AppDatabase extends _$AppDatabase {
  /// Pass an executor in tests (e.g. NativeDatabase.memory()); the app uses
  /// a file in the phone's app storage.
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'study_buddy'));

  /// v1: decks, questions, card_states, review_logs (Phase 2).
  /// v2: + note_sections (Phase 3, ADR-008).
  /// v3: + app_settings (Phase 4).
  /// v4: app_settings.language defaults to English (ADR-009).
  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        // One step per version, each using that version's frozen schema from
        // database.steps.dart (generated by `dart run drift_dev make-migrations`
        // from drift_schemas/). Tested by test/drift/.
        onUpgrade: stepByStep(
          from1To2: (m, schema) => m.createTable(schema.noteSections),
          from2To3: (m, schema) => m.createTable(schema.appSettings),
          from3To4: (m, schema) async {
            // SQLite can't change a column default in place, so Drift rebuilds
            // the table (keeping the row). Then switch the old default to
            // English (ADR-009); nobody had picked Taglish on purpose yet.
            await m.alterTable(TableMigration(schema.appSettings));
            await customStatement("UPDATE app_settings SET language = 'english' WHERE language = 'taglish'");
          },
        ),
        beforeOpen: (details) async {
          // SQLite ignores ON DELETE CASCADE unless this is on.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Saves a generated deck, its notes, its questions and a new FSRS card for
  /// each question in ONE transaction: either everything is saved or nothing is.
  Future<int> insertDeck({
    required DecksCompanion deck,
    required List<ReviewerItem> items,
    List<NoteSection> notes = const [],
    DateTime? now,
  }) {
    return transaction(() async {
      final deckId = await into(decks).insert(deck);
      for (var i = 0; i < notes.length; i++) {
        await into(noteSections).insert(NoteSectionsCompanion.insert(
          deckId: deckId,
          position: i,
          heading: notes[i].heading,
          points: notes[i].points,
          sourcePage: notes[i].sourcePage,
        ));
      }
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

  /// Live count of due questions; Home rebuilds when it changes.
  Stream<int> watchDueCount(DateTime now) {
    final count = cardStates.questionId.count();
    final query = selectOnly(cardStates)
      ..addColumns([count])
      ..where(cardStates.due.isSmallerOrEqualValue(now.toUtc()));
    return query.watchSingle().map((row) => row.read(count) ?? 0);
  }

  /// Every deck, newest first, with its number of questions.
  Stream<List<DeckSummary>> watchDeckSummaries() {
    // distinct: joining questions AND notes would otherwise multiply the counts.
    final questionCount = questions.id.count(distinct: true);
    final noteCount = noteSections.id.count(distinct: true);
    final query = select(decks).join([
      leftOuterJoin(questions, questions.deckId.equalsExp(decks.id), useColumns: false),
      leftOuterJoin(noteSections, noteSections.deckId.equalsExp(decks.id), useColumns: false),
    ])
      ..addColumns([questionCount, noteCount])
      ..groupBy([decks.id])
      ..orderBy([OrderingTerm.desc(decks.createdAt), OrderingTerm.desc(decks.id)]);
    return query.watch().map(
          (rows) => rows
              .map((row) => DeckSummary(
                    deck: row.readTable(decks),
                    questionCount: row.read(questionCount) ?? 0,
                    noteCount: row.read(noteCount) ?? 0,
                  ))
              .toList(),
        );
  }

  /// The questions of one deck, in the order Gemini wrote them.
  Stream<List<Question>> watchQuestions(int deckId) =>
      (select(questions)..where((q) => q.deckId.equals(deckId))..orderBy([(q) => OrderingTerm.asc(q.id)]))
          .watch();

  /// The note sections of one deck, in lecture order.
  Stream<List<NoteSectionRow>> watchNotes(int deckId) => (select(noteSections)
        ..where((n) => n.deckId.equals(deckId))
        ..orderBy([(n) => OrderingTerm.asc(n.position)]))
      .watch();

  /// A deck generated earlier from the same file, if any.
  Future<Deck?> findDeckByHash(String fileHash) =>
      (select(decks)..where((d) => d.fileHash.equals(fileHash))..limit(1)).getSingleOrNull();

  // ---------------------------------------------------------------- settings

  /// The settings row, created with defaults the first time.
  Future<AppSetting> getSettings() async {
    await into(appSettings).insert(const AppSettingsCompanion(), mode: InsertMode.insertOrIgnore);
    return (select(appSettings)..where((s) => s.id.equals(1))).getSingle();
  }

  Stream<AppSetting> watchSettings() async* {
    await getSettings(); // make sure the row exists
    yield* (select(appSettings)..where((s) => s.id.equals(1))).watchSingle();
  }

  Future<void> updateSettings(AppSettingsCompanion changes) async {
    await getSettings();
    await (update(appSettings)..where((s) => s.id.equals(1))).write(changes);
  }

  // ---------------------------------------------------------------- studying

  /// Cards to study now, for one deck or (deckId null) every deck:
  /// all due reviews first (oldest due first), then up to today's remaining
  /// allowance of brand-new cards, in the order Gemini wrote them.
  Future<List<StudyCard>> loadStudyQueue({
    int? deckId,
    required DateTime now,
    required int newCardsPerDay,
    Set<String>? types,
  }) async {
    final query = select(questions).join([
      innerJoin(cardStates, cardStates.questionId.equalsExp(questions.id)),
    ])
      ..where(cardStates.due.isSmallerOrEqualValue(now.toUtc()))
      ..orderBy([OrderingTerm.asc(cardStates.due), OrderingTerm.asc(questions.id)]);
    if (deckId != null) query.where(questions.deckId.equals(deckId));
    if (types != null) query.where(questions.type.isIn(types));

    final due = (await query.get())
        .map((row) => StudyCard(question: row.readTable(questions), state: row.readTable(cardStates)))
        .toList();
    final reviews = due.where((c) => !c.isNew).toList();
    final fresh = due.where((c) => c.isNew).toList()..sort((a, b) => a.question.id.compareTo(b.question.id));

    final allowance = (newCardsPerDay - await countNewStartedOn(now)).clamp(0, newCardsPerDay);
    return [...reviews, ...fresh.take(allowance)];
  }

  /// Every card of a deck (optionally only some types), due or not, in the
  /// order Gemini wrote them. For Flashcards, Test and Match.
  Future<List<StudyCard>> loadDeckCards(int deckId, {Set<String>? types}) async {
    final query = select(questions).join([
      innerJoin(cardStates, cardStates.questionId.equalsExp(questions.id)),
    ])
      ..where(questions.deckId.equals(deckId))
      ..orderBy([OrderingTerm.asc(questions.id)]);
    if (types != null) query.where(questions.type.isIn(types));
    return (await query.get())
        .map((row) => StudyCard(question: row.readTable(questions), state: row.readTable(cardStates)))
        .toList();
  }

  /// Fresh copies of specific cards (e.g. to re-study the "still learning" ones).
  Future<List<StudyCard>> loadCardsByIds(List<int> questionIds) async {
    final query = select(questions).join([
      innerJoin(cardStates, cardStates.questionId.equalsExp(questions.id)),
    ])..where(questions.id.isIn(questionIds));
    final byId = {
      for (final row in await query.get())
        row.readTable(questions).id:
            StudyCard(question: row.readTable(questions), state: row.readTable(cardStates)),
    };
    return [for (final id in questionIds) ?byId[id]];
  }

  /// Per deck: (cards in the "review" state = known, all cards), live.
  Stream<Map<int, (int, int)>> watchDeckProgress() {
    return customSelect(
      'SELECT q.deck_id AS deck, SUM(CASE WHEN c.state = 2 THEN 1 ELSE 0 END) AS known, '
      'COUNT(*) AS total FROM questions q JOIN card_states c ON c.question_id = q.id GROUP BY q.deck_id',
      readsFrom: {questions, cardStates},
    ).watch().map((rows) => {
          for (final row in rows) row.read<int>('deck'): (row.read<int>('known'), row.read<int>('total')),
        });
  }

  /// How many brand-new cards were studied for the first time on [now]'s day
  /// (phone's local day), for the daily new-card limit.
  Future<int> countNewStartedOn(DateTime now) async {
    final local = now.toLocal();
    final startOfDay = DateTime(local.year, local.month, local.day);
    final row = await customSelect(
      'SELECT COUNT(*) AS n FROM (SELECT question_id, MIN(reviewed_at) AS first '
      'FROM review_logs GROUP BY question_id) WHERE first >= ?',
      variables: [Variable.withDateTime(startOfDay)],
      readsFrom: {reviewLogs},
    ).getSingle();
    return row.read<int>('n');
  }

  /// Saves one answer: the new FSRS state and a log row, together.
  Future<void> recordReview({
    required fsrs.Card card,
    required int rating,
    required bool wasCorrect,
    String? answeredText,
    required DateTime reviewedAt,
  }) =>
      transaction(() async {
        await into(cardStates).insertOnConflictUpdate(cardStateFrom(card));
        await into(reviewLogs).insert(ReviewLogsCompanion.insert(
          questionId: card.cardId,
          rating: rating,
          wasCorrect: wasCorrect,
          answeredText: Value(answeredText),
          reviewedAt: reviewedAt,
        ));
      });

  /// Deletes a deck; its questions, cards and logs go with it (cascade).
  Future<void> deleteDeck(int deckId) => (delete(decks)..where((d) => d.id.equals(deckId))).go();

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
