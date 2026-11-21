import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config.dart';
import '../../data/database.dart';
import '../../models/generation_options.dart';
import '../../models/reviewer_item.dart';
import '../../providers.dart';
import '../../services/generator_service.dart';
import '../../services/pdf_inspector.dart';
import '../../services/reviewer_parser.dart';

/// Where the Add Lecture flow is.
enum AddStep { pickFile, checking, ready, generating, saving, done, failed }

class AddLectureState {
  const AddLectureState({
    this.step = AddStep.pickFile,
    this.fileName,
    this.info,
    this.warnings = const [],
    this.options = const GenerationOptions(),
    this.error,
    this.canRetry = false,
    this.deckId,
    this.savedCount = 0,
    this.noteCount = 0,
    this.droppedCount = 0,
    this.output,
  });

  final AddStep step;
  final String? fileName;
  final PdfInfo? info;
  final List<String> warnings;

  /// Language, quiz types, flashcards, notes (ADR-008).
  final GenerationOptions options;
  final String? error;
  final bool canRetry;
  final int? deckId;
  final int savedCount;
  final int noteCount;
  final int droppedCount;
  final GenerationOutput? output;

  AddLectureState copyWith({
    AddStep? step,
    String? fileName,
    PdfInfo? info,
    List<String>? warnings,
    GenerationOptions? options,
    String? error,
    bool? canRetry,
    int? deckId,
    int? savedCount,
    int? noteCount,
    int? droppedCount,
    GenerationOutput? output,
  }) =>
      AddLectureState(
        step: step ?? this.step,
        fileName: fileName ?? this.fileName,
        info: info ?? this.info,
        warnings: warnings ?? this.warnings,
        options: options ?? this.options,
        error: error, // cleared unless given
        canRetry: canRetry ?? false,
        deckId: deckId ?? this.deckId,
        savedCount: savedCount ?? this.savedCount,
        noteCount: noteCount ?? this.noteCount,
        droppedCount: droppedCount ?? this.droppedCount,
        output: output ?? this.output,
      );
}

/// Runs the Add Lecture steps: check PDF → choose → generate → parse → save.
/// Only `generate()` needs the internet; everything after it is offline.
class AddLectureController extends Notifier<AddLectureState> {
  Uint8List? _bytes;

  /// Quiz types to bring back if the student turns the quiz off and on again.
  Set<QuestionType> _lastQuizTypes = GenerationOptions.defaultQuizTypes;

  @override
  AddLectureState build() => const AddLectureState();

  void reset() {
    _bytes = null;
    _lastQuizTypes = GenerationOptions.defaultQuizTypes;
    // Start from the language picked in Settings (if loaded).
    final language = ref.read(settingsProvider).value?.language ?? AppConfig.defaultLanguage;
    state = AddLectureState(options: GenerationOptions(language: language));
  }

  // ---- the student's choices (shown after the file check) ----

  void _setOptions(GenerationOptions options) =>
      state = state.copyWith(options: options, error: state.error, canRetry: state.canRetry);

  void setLanguage(String language) => _setOptions(state.options.copyWith(language: language));

  /// "Gusto mo ba ng quiz?"
  void setQuizEnabled(bool enabled) {
    if (!enabled && state.options.wantsQuiz) _lastQuizTypes = state.options.quizTypes;
    _setOptions(state.options.copyWith(quizTypes: enabled ? _lastQuizTypes : const {}));
  }

  void toggleQuizType(QuestionType type) {
    final types = {...state.options.quizTypes};
    if (!types.remove(type)) types.add(type);
    _setOptions(state.options.copyWith(quizTypes: types));
  }

  void setFlashcards(bool value) => _setOptions(state.options.copyWith(flashcards: value));

  void setNotes(bool value) => _setOptions(state.options.copyWith(notes: value));

  /// Widget tests only: jump to "file checked" without the real file picker.
  @visibleForTesting
  void debugSetReady() => state = state.copyWith(
        step: AddStep.ready,
        fileName: 'test.pdf',
        info: const PdfInfo(pageCount: 10, textOpsPerPage: 40, sha256: 'test'),
      );

  // ---- step 1: check the picked file locally, before spending anything ----

  Future<void> loadFile(String fileName, Uint8List bytes) async {
    _bytes = null;
    state = AddLectureState(step: AddStep.checking, fileName: fileName, options: state.options);

    if (bytes.length > AppConfig.maxPdfBytes) {
      final mb = (bytes.length / 1024 / 1024).toStringAsFixed(1);
      state = state.copyWith(
        step: AddStep.failed,
        error: 'Masyadong malaki ang file ($mb MB). Max is ${AppConfig.maxPdfBytes ~/ 1024 ~/ 1024} MB.',
      );
      return;
    }

    final PdfInfo info;
    try {
      info = await ref.read(pdfInspectorProvider).inspect(bytes);
    } on PdfReadException catch (e) {
      state = state.copyWith(step: AddStep.failed, error: e.message);
      return;
    }

    final warnings = <String>[
      if (info.looksScanned)
        'Mukhang scanned o puro images ang PDF. Gagana pa rin, pero mas mahal at mas mahina ang questions.',
      if (info.pageCount > AppConfig.longPdfPages)
        'Mahaba ang PDF (${info.pageCount} pages). Baka hindi ma-cover lahat; mas maganda kung hatiin.',
    ];
    final existing = await ref.read(databaseProvider).findDeckByHash(info.sha256);
    if (existing != null) {
      warnings.add('Nagawa mo na ng reviewer ang file na ito ("${existing.title}"). Gagawa ulit ng bago.');
    }

    _bytes = bytes;
    state = state.copyWith(step: AddStep.ready, info: info, warnings: warnings);
  }

  // ---- steps 2–4: ask Gemini, validate offline, save in one transaction ----

  Future<void> generate() async {
    final bytes = _bytes;
    final info = state.info;
    final options = state.options;
    if (bytes == null || info == null || !options.isValid) return;

    state = state.copyWith(step: AddStep.generating);
    final GenerationOutput output;
    try {
      output = await ref.read(generatorProvider).generate(GenerationRequest(
            pdfBytes: bytes,
            pageCount: info.pageCount,
            fileHash: info.sha256,
            options: options,
          ));
    } on GenerationException catch (e) {
      state = state.copyWith(step: AddStep.failed, error: e.message, canRetry: e.canRetry);
      return;
    }

    final parsed = ReviewerParser.parse(
      output.jsonText,
      pageCount: info.pageCount,
      allowedTypes: options.questionTypes,
    );
    // Notes are kept only if asked for; the prompt already says so, this is
    // a safety net.
    final notes = options.notes ? parsed.notes : const <NoteSection>[];
    if (parsed.error != null || (parsed.items.isEmpty && notes.isEmpty)) {
      state = state.copyWith(
        step: AddStep.failed,
        error: 'Hindi magamit ang sagot ni Gemini (${parsed.error ?? 'walang valid na laman'}). Try again.',
        canRetry: true,
      );
      return;
    }

    state = state.copyWith(step: AddStep.saving, output: output);
    final deckId = await ref.read(databaseProvider).insertDeck(
          deck: DecksCompanion.insert(
            title: parsed.deckTitle.isEmpty ? (state.fileName ?? 'Reviewer') : parsed.deckTitle,
            subject: Value(parsed.subject),
            sourceFileName: state.fileName ?? 'lecture.pdf',
            fileHash: info.sha256,
            pageCount: info.pageCount,
            language: options.language,
          ),
          items: parsed.items,
          notes: notes,
        );
    state = state.copyWith(
      step: AddStep.done,
      deckId: deckId,
      savedCount: parsed.items.length,
      noteCount: notes.length,
      droppedCount: parsed.dropped.length,
    );
  }
}

final addLectureProvider =
    NotifierProvider<AddLectureController, AddLectureState>(AddLectureController.new);
