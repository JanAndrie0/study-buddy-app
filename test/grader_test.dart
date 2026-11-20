// Grader tests (Phase 2). Offline only: no Gemini, no network.

import 'package:flutter_test/flutter_test.dart';
import 'package:study_buddy/models/reviewer_item.dart';
import 'package:study_buddy/services/grader.dart';

ReviewerItem identification(String answer, {List<String> accepted = const []}) =>
    ReviewerItem(
      type: QuestionType.identification,
      sourcePage: 1,
      prompt: 'p',
      answer: answer,
      explanation: 'e',
      difficulty: 'easy',
      acceptedAnswers: accepted,
    );

ReviewerItem modifiedTf({required bool isTrue, String correction = ''}) => ReviewerItem(
      type: QuestionType.modifiedTrueFalse,
      sourcePage: 1,
      prompt: 'Training developers is an example of appraisal cost.',
      answer: isTrue ? 'True' : 'False',
      explanation: 'e',
      difficulty: 'hard',
      underlinedWord: 'appraisal',
      correction: isTrue ? 'appraisal' : correction,
    );

ReviewerItem enumeration(List<String> items) => ReviewerItem(
      type: QuestionType.enumeration,
      sourcePage: 1,
      prompt: 'Enumerate',
      answer: items.join('; '),
      explanation: 'e',
      difficulty: 'easy',
      items: items,
    );

void main() {
  group('normalizeAnswer', () {
    test('lowercases and trims', () => expect(normalizeAnswer('  Virtue '), 'virtue'));
    test('removes accents', () => expect(normalizeAnswer('Café Éclair'), 'cafe eclair'));
    test('ñ becomes n', () => expect(normalizeAnswer('Dasmariñas'), 'dasmarinas'));
    test('punctuation becomes spaces', () {
      expect(normalizeAnswer('Cost-of-Quality (CoQ)!'), 'cost of quality coq');
    });
    test('collapses spaces', () => expect(normalizeAnswer('total   cost'), 'total cost'));
    test('drops a leading article', () {
      expect(normalizeAnswer('The Golden Mean'), 'golden mean');
      expect(normalizeAnswer('an intrinsic end'), 'intrinsic end');
    });
    test('keeps a lone article word', () => expect(normalizeAnswer('A'), 'a'));
  });

  group('editDistance', () {
    test('same word is 0', () => expect(editDistance('virtue', 'virtue'), 0));
    test('one replacement', () => expect(editDistance('virtue', 'virtoe'), 1));
    test('one insertion', () => expect(editDistance('vice', 'vices'), 1));
    test('empty strings', () => expect(editDistance('', 'abc'), 3));
  });

  group('identification', () {
    test('exact answer', () {
      expect(gradeIdentification('Aristotle', identification('Aristotle')).isCorrect, isTrue);
    });
    test('case and spacing do not matter', () {
      expect(gradeIdentification('  aristotle ', identification('Aristotle')).isCorrect, isTrue);
    });
    test('one typo in a medium word is forgiven', () {
      expect(gradeIdentification('Aristotel', identification('Aristotle')).isCorrect, isTrue);
    });
    test('two typos in a long phrase are forgiven', () {
      expect(
        gradeIdentification('extrnal failur cost', identification('External failure cost')).isCorrect,
        isTrue,
      );
    });
    test('too many typos are wrong', () {
      expect(gradeIdentification('Aristocrat', identification('Aristotle')).isCorrect, isFalse);
    });
    test('short answers must be exact (DNS is not DNA)', () {
      expect(gradeIdentification('DNS', identification('DNA')).isCorrect, isFalse);
    });
    test('acronym accepted through accepted_answers', () {
      final item = identification('Total Cost of Ownership', accepted: ['TCO']);
      expect(gradeIdentification('tco', item).isCorrect, isTrue);
    });
    test('full form accepted when the answer is the acronym', () {
      final item = identification('TCO', accepted: ['Total Cost of Ownership']);
      expect(gradeIdentification('total cost of ownership', item).isCorrect, isTrue);
    });
    test('Filipino word with ñ typed without it', () {
      expect(gradeIdentification('Pinas', identification('Piñas')).isCorrect, isTrue);
    });
    test('Filipino phrase with accents', () {
      expect(gradeIdentification('kagandahang loob', identification('Kagandahang-loób')).isCorrect, isTrue);
    });
    test('leading "the" is ignored', () {
      expect(gradeIdentification('the rule of right reason', identification('Rule of Right Reason')).isCorrect, isTrue);
    });
    test('missing space is forgiven', () {
      expect(gradeIdentification('portscanning', identification('port scanning')).isCorrect, isTrue);
    });
    test('different number is wrong even if close', () {
      expect(gradeIdentification('1991', identification('1990')).isCorrect, isFalse);
    });
    test('number inside a phrase must match', () {
      expect(gradeIdentification('Phase 2 testing', identification('Phase 3 testing')).isCorrect, isFalse);
    });
    test('empty input is wrong', () {
      expect(gradeIdentification('   ', identification('Virtue')).isCorrect, isFalse);
    });
    test('plural of the answer is forgiven', () {
      expect(gradeIdentification('Appraisal costs', identification('Appraisal cost')).isCorrect, isTrue);
    });
  });

  group('multiple choice and true/false', () {
    final mcq = ReviewerItem(
      type: QuestionType.multipleChoice,
      sourcePage: 1,
      prompt: 'p',
      answer: 'Appraisal cost',
      explanation: 'e',
      difficulty: 'easy',
      choices: const ['Prevention cost', 'Appraisal cost', 'Internal failure cost', 'External failure cost'],
    );
    test('correct option', () => expect(gradeMultipleChoice('Appraisal cost', mcq).isCorrect, isTrue));
    test('wrong option', () => expect(gradeMultipleChoice('Prevention cost', mcq).isCorrect, isFalse));

    final falseStatement = ReviewerItem(
      type: QuestionType.trueFalse,
      sourcePage: 1,
      prompt: 'p',
      answer: 'False',
      explanation: 'e',
      difficulty: 'easy',
    );
    test('picking False on a false statement', () {
      expect(gradeTrueFalse(false, falseStatement).isCorrect, isTrue);
    });
    test('picking True on a false statement', () {
      expect(gradeTrueFalse(true, falseStatement).isCorrect, isFalse);
    });
  });

  group('modified true/false (underline style, ADR-007)', () {
    test('true statement, picked True', () {
      expect(gradeModifiedTrueFalse(modifiedTf(isTrue: true), pickedTrue: true).isCorrect, isTrue);
    });
    test('true statement, picked False', () {
      final r = gradeModifiedTrueFalse(modifiedTf(isTrue: true), pickedTrue: false, correctionInput: 'x');
      expect(r.isCorrect, isFalse);
      expect(r.score, 0.0);
    });
    test('false statement, picked True', () {
      final item = modifiedTf(isTrue: false, correction: 'prevention');
      expect(gradeModifiedTrueFalse(item, pickedTrue: true).score, 0.0);
    });
    test('false statement, picked False with the right correction', () {
      final item = modifiedTf(isTrue: false, correction: 'prevention');
      final r = gradeModifiedTrueFalse(item, pickedTrue: false, correctionInput: 'Prevention');
      expect(r.isCorrect, isTrue);
      expect(r.score, 1.0);
    });
    test('correction with a small typo is accepted', () {
      final item = modifiedTf(isTrue: false, correction: 'prevention');
      expect(
        gradeModifiedTrueFalse(item, pickedTrue: false, correctionInput: 'prevension').isCorrect,
        isTrue,
      );
    });
    test('false statement, picked False but wrong correction = half credit', () {
      final item = modifiedTf(isTrue: false, correction: 'prevention');
      final r = gradeModifiedTrueFalse(item, pickedTrue: false, correctionInput: 'internal failure');
      expect(r.isCorrect, isFalse);
      expect(r.score, 0.5);
    });
    test('false statement, picked False, no correction typed = half credit', () {
      final item = modifiedTf(isTrue: false, correction: 'prevention');
      expect(gradeModifiedTrueFalse(item, pickedTrue: false).score, 0.5);
    });
  });

  group('enumeration', () {
    final costs = enumeration(['Prevention', 'Appraisal', 'Internal failure', 'External failure']);
    test('all items in order', () {
      final r = gradeEnumeration(['Prevention', 'Appraisal', 'Internal failure', 'External failure'], costs);
      expect(r.isCorrect, isTrue);
      expect(r.score, 1.0);
    });
    test('any order is fine', () {
      final r = gradeEnumeration(['external failure', 'prevention', 'internal failure', 'appraisal'], costs);
      expect(r.isCorrect, isTrue);
    });
    test('partial credit for 2 of 4', () {
      final r = gradeEnumeration(['Prevention', 'Appraisal'], costs);
      expect(r.isCorrect, isFalse);
      expect(r.score, 0.5);
    });
    test('the same item typed twice counts once', () {
      expect(gradeEnumeration(['Prevention', 'prevention', 'Prevention'], costs).score, 0.25);
    });
    test('typos inside items are forgiven', () {
      expect(gradeEnumeration(['Prevension', 'Apraisal', 'Internal failur', 'External failure'], costs).isCorrect, isTrue);
    });
    test('wrong items score zero', () {
      expect(gradeEnumeration(['Quality', 'Testing'], costs).score, 0.0);
    });
    test('empty answer list scores zero', () {
      expect(gradeEnumeration([], costs).score, 0.0);
    });
  });
}
