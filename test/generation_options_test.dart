// Generation options + prompt filling (ADR-008). Uses the real asset files.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:study_buddy/models/generation_options.dart';
import 'package:study_buddy/models/reviewer_item.dart';
import 'package:study_buddy/services/generator_service.dart';

void main() {
  final mixJson = File('assets/prompts/question_mix.json').readAsStringSync();
  final template = File('assets/prompts/generate_reviewer.md').readAsStringSync();
  final baseMix = parseQuestionMix(mixJson);

  test('the shared mix file has the 5 quiz types (no flashcards, ADR-010)', () {
    expect(baseMix.keys.toSet(), GenerationOptions.quizChoices.toSet());
    expect(baseMix.containsKey(QuestionType.flashcard), isFalse);
    // Shares are re-scaled to the picked types anyway; this just catches typos.
    expect(baseMix.values.fold<double>(0, (a, b) => a + b), closeTo(0.85, 1e-9));
  });

  test('defaults: 3 quiz types + flashcards + notes, English (ADR-009)', () {
    const options = GenerationOptions();
    expect(options.language, 'english');
    expect(options.questionTypes, {
      QuestionType.multipleChoice,
      QuestionType.identification,
      QuestionType.modifiedTrueFalse,
      QuestionType.flashcard,
    });
    expect(options.notes, isTrue);
    expect(options.isValid, isTrue);
  });

  test('mix keeps only selected types and re-scales to 1', () {
    const options = GenerationOptions(quizTypes: {QuestionType.multipleChoice}, flashcards: false);
    expect(options.targetMix(baseMix), {QuestionType.multipleChoice: 1.0});

    final mix = const GenerationOptions().targetMix(baseMix);
    // Flashcards are on by default but never part of the quiz mix (ADR-010).
    expect(mix.keys.toSet(), GenerationOptions.defaultQuizTypes);
    expect(mix.values.fold<double>(0, (a, b) => a + b), closeTo(1.0, 1e-9));
    // identification 25 / (25 + 20 + 15) = 5/12
    expect(mix[QuestionType.identification], closeTo(5 / 12, 1e-9));
  });

  test('notes only: valid, zero questions, empty mix', () {
    const options = GenerationOptions(quizTypes: {}, flashcards: false, notes: true);
    expect(options.isValid, isTrue);
    expect(options.targetQuestions(20), 0);
    expect(options.targetMix(baseMix), isEmpty);
  });

  test('flashcards only: no quiz questions, flashcards come per key term (ADR-010)', () {
    const options = GenerationOptions(quizTypes: {}, flashcards: true, notes: false);
    expect(options.isValid, isTrue);
    expect(options.targetQuestions(20), 0);
    expect(options.targetMix(baseMix), isEmpty);
  });

  test('the quiz count does not shrink when flashcards are on', () {
    const withCards = GenerationOptions(flashcards: true);
    const withoutCards = GenerationOptions(flashcards: false);
    expect(withCards.targetQuestions(30), withoutCards.targetQuestions(30));
  });

  test('nothing selected is not valid', () {
    const options = GenerationOptions(quizTypes: {}, flashcards: false, notes: false);
    expect(options.isValid, isFalse);
  });

  group('fillPromptTemplate', () {
    String fill(GenerationOptions options, {int pages = 10}) => fillPromptTemplate(
          template: template,
          mixJson: mixJson,
          options: options,
          pageCount: pages,
        );

    test('replaces every placeholder', () {
      expect(fill(const GenerationOptions()), isNot(contains('{{')));
    });

    test('lists only the chosen types with their shares', () {
      final prompt = fill(const GenerationOptions(quizTypes: {QuestionType.multipleChoice}, flashcards: false));
      expect(prompt, contains('| multiple_choice | 100% |'));
      expect(prompt, isNot(contains('| identification |')));
    });

    test('notes on and off', () {
      expect(fill(const GenerationOptions(notes: true)), contains('Notes: requested'));
      expect(fill(const GenerationOptions(notes: false)), contains('Notes: not requested'));
    });

    test('notes only asks for 0 questions and no flashcards', () {
      final prompt = fill(const GenerationOptions(quizTypes: {}, flashcards: false));
      expect(prompt, contains('Quiz questions: **0**'));
      expect(prompt, contains('(No quiz questions requested.)'));
      expect(prompt, contains('Flashcards: not requested'));
    });

    test('flashcards on asks for one card per key term, outside the mix (ADR-010)', () {
      final prompt = fill(const GenerationOptions());
      expect(prompt, contains('Flashcards: requested'));
      expect(prompt, contains('every key term'));
      expect(prompt, isNot(contains('| flashcard |')));
    });

    test('language fills explanations and notes', () {
      final prompt = fill(const GenerationOptions(language: 'filipino'));
      expect(prompt, contains('Explanation language: **filipino**'));
      expect(prompt, isNot(contains('{{explanation_language}}')));
    });
  });
}
