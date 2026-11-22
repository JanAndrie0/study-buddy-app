// Home screen widget tests (Phase 3).
//
// Widget tests run on a fake clock, where live database streams never
// resolve, so here Home's providers get fixed values. The database itself is
// covered by database_test.dart. No test calls Gemini (CLAUDE.md).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:study_buddy/data/database.dart';
import 'package:study_buddy/features/add_lecture/add_lecture_controller.dart';
import 'package:study_buddy/features/add_lecture/add_lecture_screen.dart';
import 'package:study_buddy/features/home/home_screen.dart';
import 'package:study_buddy/providers.dart';

void main() {
  Future<void> pumpHome(WidgetTester tester, {required List<DeckSummary> decks, int due = 0}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        deckSummariesProvider.overrideWith((ref) => Stream.value(decks)),
        dueCountProvider.overrideWith((ref) => Stream.value(due)),
        deckProgressProvider.overrideWith((ref) => Stream.value({1: (3, 6)})),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pump(); // let the streams deliver their value
    await tester.pump(); // progress is watched only once the deck list is shown
  }

  testWidgets('empty state invites you to add a lecture', (tester) async {
    await pumpHome(tester, decks: []);
    expect(find.textContaining('Wala pang reviewer'), findsOneWidget);
    // Redesign (Figma "Home · empty"): one call to action, no floating button.
    expect(find.text('Add lecture'), findsOneWidget);
  });

  testWidgets('a saved deck shows with its question count and due count', (tester) async {
    final deck = Deck(
      id: 1,
      title: 'Software Quality Economics',
      subject: 'CIT4303',
      sourceFileName: 'LECT4.pdf',
      fileHash: 'abc',
      pageCount: 7,
      language: 'taglish',
      createdAt: DateTime(2026, 11, 20),
    );
    await pumpHome(tester, decks: [DeckSummary(deck: deck, questionCount: 6, noteCount: 2)], due: 6);
    expect(find.text('Software Quality Economics'), findsOneWidget);
    expect(find.text('CIT4303 · 6 cards · notes'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('cards due today'), findsOneWidget);
    expect(find.text('50% known'), findsOneWidget);
  });

  group('Add Lecture choices (ADR-008)', () {
    Future<void> pumpChoices(WidgetTester tester) async {
      final container = ProviderContainer(overrides: [
        settingsProvider.overrideWith((ref) => Stream.value(const AppSetting(
              id: 1,
              language: 'taglish',
              newCardsPerDay: 20,
              themeMode: 'system',
              onboardingDone: true,
            ))),
      ]);
      addTearDown(container.dispose);
      // Put the screen in the "ready" step without a real file picker.
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AddLectureScreen()),
      ));
      await tester.pump();
      container.read(addLectureProvider.notifier).debugSetReady();
      await tester.pump();
    }

    testWidgets('quiz switch shows and hides the quiz-type chips', (tester) async {
      await pumpChoices(tester);
      expect(find.text('Gusto mo ba ng quiz?'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Identification'), findsOneWidget);
      await tester.tap(find.text('Gusto mo ba ng quiz?'));
      await tester.pump();
      expect(find.widgetWithText(FilterChip, 'Identification'), findsNothing);
    });

    testWidgets('generate button is disabled when nothing is chosen', (tester) async {
      await pumpChoices(tester);
      await tester.tap(find.text('Gusto mo ba ng quiz?'));
      await tester.pump();
      await tester.tap(find.text('Flashcards'));
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Notes'), 200);
      await tester.tap(find.text('Notes'));
      await tester.pump();
      await tester.scrollUntilVisible(find.textContaining('Pumili ng kahit isa'), 200);
      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Gumawa ng reviewer'));
      expect(button.onPressed, isNull);
    });
  });
}
