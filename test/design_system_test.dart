// "Calm Notebook" design system (Figma redesign): tokens, theme and the
// shared answer option. No test calls Gemini (CLAUDE.md).

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:study_buddy/theme.dart';
import 'package:study_buddy/widgets/ui.dart';

void main() {
  Widget wrap(Widget child, {Brightness brightness = Brightness.light}) => MaterialApp(
        theme: buildAppTheme(brightness),
        home: Scaffold(body: child),
      );

  group('theme', () {
    test('light and dark use the Figma tokens', () {
      final light = buildAppTheme(Brightness.light);
      final dark = buildAppTheme(Brightness.dark);
      expect(light.extension<AppTokens>(), AppTokens.light);
      expect(dark.extension<AppTokens>(), AppTokens.dark);
      expect(light.scaffoldBackgroundColor, const Color(0xFFF5F1E8)); // paper
      expect(light.colorScheme.primary, const Color(0xFF1E2A4A)); // ink navy
      expect(dark.colorScheme.primary, const Color(0xFF7FD6AE)); // mint in dark mode
    });

    test('headings are Fraunces, body text is Inter (bundled fonts)', () {
      final text = buildAppTheme(Brightness.light).textTheme;
      expect(text.headlineMedium!.fontFamily, 'Fraunces');
      expect(text.titleLarge!.fontFamily, 'Fraunces');
      expect(text.bodyLarge!.fontFamily, 'Inter');
      expect(text.bodyLarge!.fontSize, greaterThanOrEqualTo(16)); // readable body text
    });

    testWidgets('tokens fall back to defaults without the app theme', (tester) async {
      late AppTokens tokens;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        tokens = context.tokens;
        return const SizedBox();
      })));
      expect(tokens, AppTokens.light);
    });
  });

  group('AnswerOption', () {
    testWidgets('correct and wrong show an icon, not colour alone', (tester) async {
      await tester.pumpWidget(wrap(const Column(children: [
        AnswerOption(letter: 'A', text: 'Queue', state: AnswerState.wrong),
        AnswerOption(letter: 'B', text: 'Stack', state: AnswerState.correct),
        AnswerOption(letter: 'C', text: 'Linked list', state: AnswerState.idle),
      ])));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      // Screen readers hear the result too (merged into the option's label).
      expect(find.bySemanticsLabel(RegExp('Correct answer')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Your answer, wrong')), findsOneWidget);
    });

    testWidgets('tapping the text calls onTap; a locked option ignores taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(Column(children: [
        AnswerOption(letter: 'A', text: 'Stack', state: AnswerState.idle, onTap: () => taps++),
        const AnswerOption(letter: 'B', text: 'Queue', state: AnswerState.idle),
      ])));
      await tester.tap(find.text('Stack'));
      await tester.tap(find.text('Queue'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('works in dark mode and with animations turned off', (tester) async {
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: wrap(const AnswerOption(letter: 'A', text: 'Stack', state: AnswerState.wrong),
            brightness: Brightness.dark),
      ));
      await tester.pump(); // no animation to wait for
      expect(find.byIcon(Icons.close), findsOneWidget);
    });
  });
}
