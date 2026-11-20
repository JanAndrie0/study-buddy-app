// Parser tests (Phase 2): bad model output must never crash the app.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:study_buddy/models/reviewer_item.dart';
import 'package:study_buddy/services/reviewer_parser.dart';

/// Builds a deck JSON with the given questions.
String deckJson(List<Map<String, dynamic>> questions) => jsonEncode({
      'deck_title': 'Test deck',
      'subject': 'CIT4303',
      'explanation_language': 'taglish',
      'questions': questions,
    });

/// A valid question of [type]; [overrides] change single fields.
Map<String, dynamic> question(String type, [Map<String, dynamic> overrides = const {}]) => {
      'type': type,
      'source_page': 2,
      'prompt': 'Costs of checking quality, like testing.',
      'answer': 'Appraisal cost',
      'correction': '',
      'explanation': 'Kasi testing yan.',
      'difficulty': 'medium',
      ...overrides,
    };

void main() {
  test('parses the sample deck with all 6 types', () {
    final text = File('test/fixtures/sample_reviewer.json').readAsStringSync();
    final result = ReviewerParser.parse(text, pageCount: 10);
    expect(result.error, isNull);
    expect(result.dropped, isEmpty);
    expect(result.items, hasLength(6));
    expect(result.items.map((i) => i.type).toSet(), QuestionType.values.toSet());
    expect(result.deckTitle, 'Software Quality Economics');
    final modified = result.items.firstWhere((i) => i.type == QuestionType.modifiedTrueFalse);
    expect(modified.underlinedWord, 'appraisal');
    expect(modified.correction, 'prevention');
  });

  test('not JSON at all gives an error, not a crash', () {
    final result = ReviewerParser.parse('Sorry, I cannot help with that.', pageCount: 5);
    expect(result.error, isNotNull);
    expect(result.isUsable, isFalse);
  });

  test('cut-off JSON (output limit hit) gives an error', () {
    final text = deckJson([question('identification')]);
    expect(ReviewerParser.parse(text.substring(0, text.length - 20), pageCount: 5).error, isNotNull);
  });

  test('a JSON list instead of an object gives an error', () {
    expect(ReviewerParser.parse('[1, 2, 3]', pageCount: 5).error, isNotNull);
  });

  test('missing questions list gives an error', () {
    expect(ReviewerParser.parse('{"deck_title": "x"}', pageCount: 5).error, isNotNull);
  });

  test('keeps good items and drops broken ones with a reason', () {
    final result = ReviewerParser.parse(
      deckJson([
        question('identification'),
        question('multiple_choice', {'choices': ['A', 'B', 'C'], 'answer': 'A'}),
      ]),
      pageCount: 5,
    );
    expect(result.items, hasLength(1));
    expect(result.dropped.single, contains('3 choices'));
  });

  test('drops a multiple choice whose answer is not one of the choices', () {
    final result = ReviewerParser.parse(
      deckJson([question('multiple_choice', {'choices': ['A', 'B', 'C', 'D'], 'answer': 'E'})]),
      pageCount: 5,
    );
    expect(result.dropped.single, contains('answer not in choices'));
  });

  test('drops an unknown type', () {
    final result = ReviewerParser.parse(deckJson([question('essay')]), pageCount: 5);
    expect(result.dropped.single, contains('unknown type'));
  });

  test('drops a source_page beyond the PDF', () {
    final result = ReviewerParser.parse(deckJson([question('flashcard', {'source_page': 9})]), pageCount: 5);
    expect(result.dropped.single, contains('source_page'));
  });

  test('drops an empty explanation', () {
    final result = ReviewerParser.parse(deckJson([question('flashcard', {'explanation': '  '})]), pageCount: 5);
    expect(result.dropped.single, contains('empty explanation'));
  });

  test('drops identification when the answer is inside the prompt', () {
    final result = ReviewerParser.parse(
      deckJson([question('identification', {'prompt': 'What is appraisal cost?'})]),
      pageCount: 5,
    );
    expect(result.dropped.single, contains('answer appears in prompt'));
  });

  test('drops enumeration with fewer than 2 items', () {
    final result = ReviewerParser.parse(
      deckJson([question('enumeration', {'items': ['Only one']})]),
      pageCount: 5,
    );
    expect(result.dropped.single, contains('fewer than 2 items'));
  });

  group('modified true/false (ADR-007)', () {
    Map<String, dynamic> modified(Map<String, dynamic> overrides) => question('modified_true_false', {
          'prompt': 'Training developers is an example of appraisal cost.',
          'underlined_word': 'appraisal',
          'answer': 'False',
          'correction': 'prevention',
          ...overrides,
        });

    test('keeps a valid False item', () {
      expect(ReviewerParser.parse(deckJson([modified({})]), pageCount: 5).items, hasLength(1));
    });
    test('drops False with an empty correction', () {
      final result = ReviewerParser.parse(deckJson([modified({'correction': ''})]), pageCount: 5);
      expect(result.dropped.single, contains('no correction'));
    });
    test('drops an underline that is not in the statement', () {
      final result = ReviewerParser.parse(deckJson([modified({'underlined_word': 'testing'})]), pageCount: 5);
      expect(result.dropped.single, contains('underlined_word not in prompt'));
    });
    test('underline match ignores case', () {
      final result = ReviewerParser.parse(deckJson([modified({'underlined_word': 'Appraisal'})]), pageCount: 5);
      expect(result.items, hasLength(1));
    });
    test('drops a correction identical to the underlined word', () {
      final result = ReviewerParser.parse(deckJson([modified({'correction': 'Appraisal'})]), pageCount: 5);
      expect(result.dropped.single, contains('same as underlined_word'));
    });
    test('drops an answer that is not True/False', () {
      final result = ReviewerParser.parse(deckJson([modified({'answer': 'Mali'})]), pageCount: 5);
      expect(result.dropped.single, contains('True/False'));
    });
  });

  test('drops a duplicate prompt', () {
    final result = ReviewerParser.parse(
      deckJson([question('flashcard'), question('flashcard', {'answer': 'Other'})]),
      pageCount: 5,
    );
    expect(result.items, hasLength(1));
    expect(result.dropped.single, contains('duplicate'));
  });

  test('caps the deck at 60 items', () {
    final many = List.generate(65, (i) => question('flashcard', {'prompt': 'Term number $i'}));
    final result = ReviewerParser.parse(deckJson(many), pageCount: 5);
    expect(result.items, hasLength(60));
    expect(result.dropped, hasLength(5));
  });

  test('unknown difficulty and language fall back to defaults', () {
    final text = jsonEncode({
      'deck_title': 'x',
      'subject': 'y',
      'explanation_language': 'klingon',
      'questions': [question('flashcard', {'difficulty': 'insane'})],
    });
    final result = ReviewerParser.parse(text, pageCount: 5);
    expect(result.explanationLanguage, 'taglish');
    expect(result.items.single.difficulty, 'medium');
  });
}
