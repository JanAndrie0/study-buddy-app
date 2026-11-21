// Add Lecture flow tests (Phase 3) with a fake PDF reader and a fake Gemini.
// Nothing here touches the network.

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_buddy/config.dart';
import 'package:study_buddy/data/database.dart';
import 'package:study_buddy/features/add_lecture/add_lecture_controller.dart';
import 'package:study_buddy/models/reviewer_item.dart';
import 'package:study_buddy/providers.dart';
import 'package:study_buddy/services/generator_service.dart';
import 'package:study_buddy/services/pdf_inspector.dart';

class FakeInspector implements PdfInspector {
  FakeInspector({this.info, this.error});
  final PdfInfo? info;
  final PdfReadException? error;

  @override
  Future<PdfInfo> inspect(Uint8List bytes) async {
    if (error != null) throw error!;
    return info!;
  }
}

class FakeGenerator implements ReviewerGenerator {
  FakeGenerator({this.jsonText, this.error});
  final String? jsonText;
  final GenerationException? error;
  GenerationRequest? lastRequest;
  int calls = 0;

  @override
  Future<GenerationOutput> generate(GenerationRequest request) async {
    calls++;
    lastRequest = request;
    if (error != null) throw error!;
    return GenerationOutput(jsonText: jsonText!, inputTokens: 1000, outputTokens: 500);
  }
}

void main() {
  final sampleJson = File('test/fixtures/sample_reviewer.json').readAsStringSync();
  const textPdf = PdfInfo(pageCount: 10, textOpsPerPage: 40, sha256: 'hash-1');
  final pdfBytes = Uint8List.fromList(List.filled(100, 1));

  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  ProviderContainer makeContainer({required PdfInspector inspector, required ReviewerGenerator generator}) {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) => db),
      pdfInspectorProvider.overrideWith((ref) => inspector),
      generatorProvider.overrideWith((ref) => generator),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('happy path: check → generate → parse → save', () async {
    final generator = FakeGenerator(jsonText: sampleJson);
    final container = makeContainer(inspector: FakeInspector(info: textPdf), generator: generator);
    final controller = container.read(addLectureProvider.notifier);

    await controller.loadFile('LECT4.pdf', pdfBytes);
    expect(container.read(addLectureProvider).step, AddStep.ready);
    expect(container.read(addLectureProvider).warnings, isEmpty);

    controller.setLanguage('filipino');
    // Tick the two quiz types that aren't on by default → all 6 types wanted.
    controller.toggleQuizType(QuestionType.enumeration);
    controller.toggleQuizType(QuestionType.trueFalse);
    await controller.generate();

    final state = container.read(addLectureProvider);
    expect(state.step, AddStep.done);
    expect(state.savedCount, 6);
    expect(state.noteCount, 2);
    expect(state.droppedCount, 0);
    expect(generator.lastRequest!.options.language, 'filipino');
    expect(generator.lastRequest!.pageCount, 10);

    final decks = await db.select(db.decks).get();
    expect(decks.single.title, 'Software Quality Economics');
    expect(decks.single.language, 'filipino');
    expect(decks.single.fileHash, 'hash-1');
    expect(await db.select(db.questions).get(), hasLength(6));
    expect(await db.select(db.cardStates).get(), hasLength(6));
    expect(await db.select(db.noteSections).get(), hasLength(2));
  });

  test('defaults keep only MCQ, identification, modified T/F and flashcards', () async {
    final container = makeContainer(
      inspector: FakeInspector(info: textPdf),
      generator: FakeGenerator(jsonText: sampleJson),
    );
    final controller = container.read(addLectureProvider.notifier);
    await controller.loadFile('LECT4.pdf', pdfBytes);
    await controller.generate();

    final types = (await db.select(db.questions).get()).map((q) => q.type).toSet();
    expect(types, {'multiple_choice', 'identification', 'modified_true_false', 'flashcard'});
    expect(container.read(addLectureProvider).droppedCount, 2); // enumeration + true/false
  });

  test('no quiz + no flashcards + notes only saves just the notes', () async {
    final container = makeContainer(
      inspector: FakeInspector(info: textPdf),
      generator: FakeGenerator(jsonText: sampleJson),
    );
    final controller = container.read(addLectureProvider.notifier);
    await controller.loadFile('LECT4.pdf', pdfBytes);
    controller.setQuizEnabled(false);
    controller.setFlashcards(false);
    await controller.generate();

    expect(container.read(addLectureProvider).step, AddStep.done);
    expect(await db.select(db.questions).get(), isEmpty);
    expect(await db.select(db.noteSections).get(), hasLength(2));
  });

  test('unticking notes keeps notes out even if Gemini sends them', () async {
    final container = makeContainer(
      inspector: FakeInspector(info: textPdf),
      generator: FakeGenerator(jsonText: sampleJson),
    );
    final controller = container.read(addLectureProvider.notifier);
    await controller.loadFile('LECT4.pdf', pdfBytes);
    controller.setNotes(false);
    await controller.generate();
    expect(await db.select(db.noteSections).get(), isEmpty);
  });

  test('nothing selected: generate does nothing and Gemini is not called', () async {
    final generator = FakeGenerator(jsonText: sampleJson);
    final container = makeContainer(inspector: FakeInspector(info: textPdf), generator: generator);
    final controller = container.read(addLectureProvider.notifier);
    await controller.loadFile('LECT4.pdf', pdfBytes);
    controller.setQuizEnabled(false);
    controller.setFlashcards(false);
    controller.setNotes(false);
    expect(container.read(addLectureProvider).options.isValid, isFalse);
    await controller.generate();
    expect(generator.calls, 0);
    expect(container.read(addLectureProvider).step, AddStep.ready);
  });

  test('turning the quiz off and on brings back the chosen types', () async {
    final container = makeContainer(
      inspector: FakeInspector(info: textPdf),
      generator: FakeGenerator(jsonText: sampleJson),
    );
    final controller = container.read(addLectureProvider.notifier);
    controller.toggleQuizType(QuestionType.identification); // untick
    controller.setQuizEnabled(false);
    expect(container.read(addLectureProvider).options.wantsQuiz, isFalse);
    controller.setQuizEnabled(true);
    expect(container.read(addLectureProvider).options.quizTypes,
        {QuestionType.multipleChoice, QuestionType.modifiedTrueFalse});
  });

  test('a file over the size limit is refused before anything else', () async {
    final generator = FakeGenerator(jsonText: sampleJson);
    final container = makeContainer(inspector: FakeInspector(info: textPdf), generator: generator);
    await container.read(addLectureProvider.notifier)
        .loadFile('big.pdf', Uint8List(AppConfig.maxPdfBytes + 1));
    final state = container.read(addLectureProvider);
    expect(state.step, AddStep.failed);
    expect(state.error, contains('Masyadong malaki'));
    expect(generator.calls, 0);
  });

  test('a PDF that cannot be opened shows the reader message', () async {
    final container = makeContainer(
      inspector: FakeInspector(error: const PdfReadException('May password ang PDF.')),
      generator: FakeGenerator(jsonText: sampleJson),
    );
    await container.read(addLectureProvider.notifier).loadFile('locked.pdf', pdfBytes);
    expect(container.read(addLectureProvider).error, 'May password ang PDF.');
  });

  test('image-only PDFs get a warning but can still be generated', () async {
    final container = makeContainer(
      inspector: FakeInspector(info: const PdfInfo(pageCount: 24, textOpsPerPage: 0, sha256: 'scan')),
      generator: FakeGenerator(jsonText: sampleJson),
    );
    await container.read(addLectureProvider.notifier).loadFile('scan.pdf', pdfBytes);
    final state = container.read(addLectureProvider);
    expect(state.step, AddStep.ready);
    expect(state.warnings.single, contains('scanned'));
  });

  test('uploading the same file again shows a warning', () async {
    final container = makeContainer(
      inspector: FakeInspector(info: textPdf),
      generator: FakeGenerator(jsonText: sampleJson),
    );
    final controller = container.read(addLectureProvider.notifier);
    await controller.loadFile('LECT4.pdf', pdfBytes);
    await controller.generate();
    await controller.loadFile('LECT4.pdf', pdfBytes);
    expect(container.read(addLectureProvider).warnings.single, contains('Nagawa mo na'));
  });

  test('a Gemini error is shown with Retry and nothing is saved', () async {
    final container = makeContainer(
      inspector: FakeInspector(info: textPdf),
      generator: FakeGenerator(error: const GenerationException('Walang internet.')),
    );
    final controller = container.read(addLectureProvider.notifier);
    await controller.loadFile('LECT4.pdf', pdfBytes);
    await controller.generate();
    final state = container.read(addLectureProvider);
    expect(state.step, AddStep.failed);
    expect(state.error, 'Walang internet.');
    expect(state.canRetry, isTrue);
    expect(await db.select(db.decks).get(), isEmpty);
  });

  test('unusable JSON from Gemini fails cleanly and saves nothing', () async {
    final container = makeContainer(
      inspector: FakeInspector(info: textPdf),
      generator: FakeGenerator(jsonText: '{"questions": [{"type": "flashcard"'),
    );
    final controller = container.read(addLectureProvider.notifier);
    await controller.loadFile('LECT4.pdf', pdfBytes);
    await controller.generate();
    expect(container.read(addLectureProvider).step, AddStep.failed);
    expect(container.read(addLectureProvider).canRetry, isTrue);
    expect(await db.select(db.decks).get(), isEmpty);
  });

  test('target question count follows page count (matches the evals)', () {
    expect(AppConfig.targetQuestions(6), 10); // min
    expect(AppConfig.targetQuestions(19), 15);
    expect(AppConfig.targetQuestions(39), 31);
    expect(AppConfig.targetQuestions(200), 40); // max
  });
}
