// Question widgets (Phase 4): each type reports the right grade.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:study_buddy/features/study/question_views.dart';
import 'package:study_buddy/models/reviewer_item.dart';
import 'package:study_buddy/services/grader.dart';

ReviewerItem item(QuestionType type, {String answer = 'Appraisal cost', Map<String, Object?> extra = const {}}) =>
    ReviewerItem(
      type: type,
      sourcePage: 3,
      prompt: extra['prompt'] as String? ?? 'Training developers is an example of appraisal cost.',
      answer: answer,
      explanation: 'Kasi…',
      difficulty: 'easy',
      choices: (extra['choices'] as List<String>?) ?? const [],
      items: (extra['items'] as List<String>?) ?? const [],
      underlinedWord: extra['underlined'] as String?,
      correction: extra['correction'] as String?,
    );

void main() {
  late GradeResult? graded;
  late String? text;
  void onGraded(GradeResult g, String? t) {
    graded = g;
    text = t;
  }

  setUp(() {
    graded = null;
    text = null;
  });

  Future<void> pump(WidgetTester tester, ReviewerItem i) => tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuestionView(item: i, locked: false, onGraded: onGraded, onRate: (_) {}),
          ),
        ),
      ));

  testWidgets('multiple choice: tapping the answer is correct', (tester) async {
    await pump(tester, item(QuestionType.multipleChoice,
        extra: {'choices': ['Prevention cost', 'Appraisal cost', 'Internal failure cost', 'External failure cost']}));
    await tester.tap(find.text('Appraisal cost'));
    expect(graded!.isCorrect, isTrue);
    expect(text, 'Appraisal cost');
  });

  testWidgets('identification: typed answer with a typo still counts', (tester) async {
    await pump(tester, item(QuestionType.identification, extra: {'prompt': 'Costs of checking quality.'}));
    await tester.enterText(find.byType(TextField), 'apraisal cost');
    await tester.tap(find.text('Check'));
    expect(graded!.isCorrect, isTrue);
  });

  testWidgets('enumeration: one box per item, partial credit', (tester) async {
    await pump(tester, item(QuestionType.enumeration,
        answer: 'Prevention; Appraisal', extra: {'prompt': 'Enumerate the 2…', 'items': ['Prevention', 'Appraisal']}));
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.enterText(find.byType(TextField).first, 'appraisal');
    await tester.tap(find.text('Check'));
    expect(graded!.score, 0.5);
  });

  testWidgets('modified T/F: underline shown; False asks for the correction', (tester) async {
    await pump(tester, item(QuestionType.modifiedTrueFalse,
        answer: 'False', extra: {'underlined': 'appraisal', 'correction': 'prevention'}));

    final rich = tester.widget<RichText>(find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains('Training developers')));
    // Text.rich wraps our span in another one, so search every nested span.
    final underlinedTexts = <String>[];
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.style?.decoration == TextDecoration.underline) {
        underlinedTexts.add(span.text ?? '');
      }
      return true;
    });
    expect(underlinedTexts, ['appraisal']);

    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('False'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Prevention');
    await tester.tap(find.text('Check'));
    expect(graded!.isCorrect, isTrue);
  });

  testWidgets('modified T/F: True on a false statement is wrong right away', (tester) async {
    await pump(tester, item(QuestionType.modifiedTrueFalse,
        answer: 'False', extra: {'underlined': 'appraisal', 'correction': 'prevention'}));
    await tester.tap(find.text('True'));
    expect(graded!.isCorrect, isFalse);
  });

  test('underline match ignores case', () {
    final span = underlinedStatement('Spur is a projection.', 'spur', null);
    final parts = span.children!.cast<TextSpan>();
    expect(parts[1].text, 'Spur');
  });
}
