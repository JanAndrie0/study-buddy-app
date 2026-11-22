import 'dart:convert';

import '../config.dart';
import 'reviewer_item.dart';

/// What the student asked for on the Add Lecture screen (ADR-008).
class GenerationOptions {
  const GenerationOptions({
    this.language = AppConfig.defaultLanguage,
    this.quizTypes = defaultQuizTypes,
    this.flashcards = true,
    this.notes = true,
  });

  /// The 5 quiz formats a student can pick (flashcards are a separate choice).
  static const quizChoices = [
    QuestionType.multipleChoice,
    QuestionType.identification,
    QuestionType.modifiedTrueFalse,
    QuestionType.enumeration,
    QuestionType.trueFalse,
  ];

  /// Ticked by default: the formats Filipino students meet most in quizzes.
  static const defaultQuizTypes = {
    QuestionType.multipleChoice,
    QuestionType.identification,
    QuestionType.modifiedTrueFalse,
  };

  /// english / filipino / taglish (explanations and notes).
  final String language;

  /// Empty = the student said "no quiz".
  final Set<QuestionType> quizTypes;
  final bool flashcards;
  final bool notes;

  bool get wantsQuiz => quizTypes.isNotEmpty;

  /// All question types to generate (quiz formats + flashcards).
  Set<QuestionType> get questionTypes => {...quizTypes, if (flashcards) QuestionType.flashcard};

  /// At least one thing must be selected.
  bool get isValid => questionTypes.isNotEmpty || notes;

  /// How many QUIZ questions to ask for: 0 when no quiz was picked.
  /// Flashcards are extra: one per key term (ADR-010).
  int targetQuestions(int pageCount) => wantsQuiz ? AppConfig.targetQuestions(pageCount) : 0;

  /// Keeps only the selected quiz types from [baseMix] and re-scales their
  /// shares so they add up to 1 (e.g. multiple choice only → 100% multiple
  /// choice). Flashcards are never part of the mix (ADR-010).
  Map<QuestionType, double> targetMix(Map<QuestionType, double> baseMix) {
    final picked = {
      for (final entry in baseMix.entries)
        if (quizTypes.contains(entry.key)) entry.key: entry.value,
    };
    final total = picked.values.fold<double>(0, (sum, share) => sum + share);
    if (total == 0) return {};
    return picked.map((type, share) => MapEntry(type, share / total));
  }

  GenerationOptions copyWith({
    String? language,
    Set<QuestionType>? quizTypes,
    bool? flashcards,
    bool? notes,
  }) =>
      GenerationOptions(
        language: language ?? this.language,
        quizTypes: quizTypes ?? this.quizTypes,
        flashcards: flashcards ?? this.flashcards,
        notes: notes ?? this.notes,
      );
}

/// Reads assets/prompts/question_mix.json (shared with the evals, ADR-006).
Map<QuestionType, double> parseQuestionMix(String jsonText) {
  final raw = jsonDecode(jsonText) as Map<String, dynamic>;
  return {
    // `?key` skips entries whose name isn't a question type (e.g. "_comment").
    for (final entry in raw.entries)
      ?QuestionType.fromJsonName(entry.key): (entry.value as num).toDouble(),
  };
}
