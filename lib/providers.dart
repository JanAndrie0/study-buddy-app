import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database.dart';
import 'services/generator_service.dart';
import 'services/pdf_inspector.dart';
import 'services/scheduler.dart';

// App-wide services. Tests replace them with `overrideWith` (e.g. an
// in-memory database or a fake generator), so no test touches Gemini.

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final generatorProvider = Provider<ReviewerGenerator>((ref) => GeneratorService());

final pdfInspectorProvider = Provider<PdfInspector>((ref) => DartPdfInspector());

/// Decks for the Home list, updated live from the database.
final deckSummariesProvider = StreamProvider<List<DeckSummary>>(
  (ref) => ref.watch(databaseProvider).watchDeckSummaries(),
);

/// Spaced repetition (fsrs wrapper).
final reviewSchedulerProvider = Provider<ReviewScheduler>((ref) => ReviewScheduler());

/// The clock, swappable in tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// App settings (language, new cards per day, theme, onboarding).
final settingsProvider = StreamProvider<AppSetting>(
  (ref) => ref.watch(databaseProvider).watchSettings(),
);

/// Known / total cards per deck, for Home's progress bars.
final deckProgressProvider = StreamProvider<Map<int, (int, int)>>(
  (ref) => ref.watch(databaseProvider).watchDeckProgress(),
);

/// "Due today" count for Home.
final dueCountProvider = StreamProvider<int>(
  (ref) => ref.watch(databaseProvider).watchDueCount(DateTime.now()),
);
