// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:study_buddy/data/database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';

import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    // These simple tests verify all possible schema updates with a simple (no
    // data) migration. This is a quick way to ensure that written database
    // migrations properly alter the schema.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = AppDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  // A real v1 deck (like the one already on my phone) must survive the
  // upgrade to v2 unchanged. Dates are stored as Unix seconds, lists as JSON.
  test('migration from v1 to v2 does not corrupt data', () async {
    const created = 1795600000; // 2026-11-20
    final oldDecksData = <v1.DecksData>[
      const v1.DecksData(
        id: 1,
        title: 'Software Quality Economics',
        subject: 'CIT4303',
        sourceFileName: 'LECT4.pdf',
        fileHash: 'abc123',
        pageCount: 7,
        language: 'taglish',
        createdAt: created,
      ),
    ];
    final expectedNewDecksData = <v2.DecksData>[
      const v2.DecksData(
        id: 1,
        title: 'Software Quality Economics',
        subject: 'CIT4303',
        sourceFileName: 'LECT4.pdf',
        fileHash: 'abc123',
        pageCount: 7,
        language: 'taglish',
        createdAt: created,
      ),
    ];

    final oldQuestionsData = <v1.QuestionsData>[
      const v1.QuestionsData(
        id: 1,
        deckId: 1,
        type: 'multiple_choice',
        prompt: 'Which cost category includes testing?',
        answer: 'Appraisal cost',
        acceptedAnswers: '[]',
        choices: '["Prevention cost","Appraisal cost","Internal failure cost","External failure cost"]',
        items: '[]',
        correction: '',
        explanation: 'Testing is appraisal.',
        sourcePage: 3,
        difficulty: 'medium',
      ),
    ];
    final expectedNewQuestionsData = <v2.QuestionsData>[
      const v2.QuestionsData(
        id: 1,
        deckId: 1,
        type: 'multiple_choice',
        prompt: 'Which cost category includes testing?',
        answer: 'Appraisal cost',
        acceptedAnswers: '[]',
        choices: '["Prevention cost","Appraisal cost","Internal failure cost","External failure cost"]',
        items: '[]',
        correction: '',
        explanation: 'Testing is appraisal.',
        sourcePage: 3,
        difficulty: 'medium',
      ),
    ];

    final oldCardStatesData = <v1.CardStatesData>[
      const v1.CardStatesData(questionId: 1, state: 1, step: 0, due: created),
    ];
    final expectedNewCardStatesData = <v2.CardStatesData>[
      const v2.CardStatesData(questionId: 1, state: 1, step: 0, due: created),
    ];

    final oldReviewLogsData = <v1.ReviewLogsData>[];
    final expectedNewReviewLogsData = <v2.ReviewLogsData>[];

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.decks, oldDecksData);
        batch.insertAll(oldDb.questions, oldQuestionsData);
        batch.insertAll(oldDb.cardStates, oldCardStatesData);
        batch.insertAll(oldDb.reviewLogs, oldReviewLogsData);
      },
      validateItems: (newDb) async {
        expect(expectedNewDecksData, await newDb.select(newDb.decks).get());
        expect(
          expectedNewQuestionsData,
          await newDb.select(newDb.questions).get(),
        );
        expect(
          expectedNewCardStatesData,
          await newDb.select(newDb.cardStates).get(),
        );
        expect(
          expectedNewReviewLogsData,
          await newDb.select(newDb.reviewLogs).get(),
        );
        // The new table exists and starts empty for old decks.
        expect(await newDb.select(newDb.noteSections).get(), isEmpty);
      },
    );
  });

  // ADR-009: the old Taglish default becomes English; other settings stay.
  test('migration from v3 to v4 switches the default language to English', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 3,
      newVersion: 4,
      createOld: v3.DatabaseAtV3.new,
      createNew: v4.DatabaseAtV4.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(
          oldDb.appSettings,
          const v3.AppSettingsData(
            id: 1,
            language: 'taglish',
            newCardsPerDay: 10,
            themeMode: 'dark',
            onboardingDone: 0,
          ),
        );
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.appSettings).get(), [
          const v4.AppSettingsData(
            id: 1,
            language: 'english',
            newCardsPerDay: 10,
            themeMode: 'dark',
            onboardingDone: 0,
          ),
        ]);
      },
    );
  });
}
