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

  test('the shared mix file has all 6 types and adds up to 1', () {
    expect(baseMix.keys.toSet(), QuestionType.values.toSet());
    expect(baseMix.values.fold<double>(0, (a, b) => a + b), closeTo(1.0, 1e-9));
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
    expect(mix.keys.toSet(), const GenerationOptions().questionTypes);
    expect(mix.values.fold<double>(0, (a, b) => a + b), closeTo(1.0, 1e-9));
    // identification 25 / (25 + 20 + 15 + 15) = 1/3
    expect(mix[QuestionType.identification], closeTo(1 / 3, 1e-9));
  });

  test('notes only: valid, zero questions, empty mix', () {
    const options = GenerationOptions(quizTypes: {}, flashcards: false, notes: true);
    expect(options.isValid, isTrue);
    expect(options.targetQuestions(20), 0);
    expect(options.targetMix(baseMix), isEmpty);
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

    test('notes only asks for 0 questions', () {
      final prompt = fill(const GenerationOptions(quizTypes: {}, flashcards: false));
      expect(prompt, contains('Target number of questions: **0**'));
      expect(prompt, contains('(No questions requested.)'));
    });

    test('language fills explanations and notes', () {
      final prompt = fill(const GenerationOptions(language: 'filipino'));
      expect(prompt, contains('Explanation language: **filipino**'));
      expect(prompt, isNot(contains('{{explanation_language}}')));
    });
  });
}
