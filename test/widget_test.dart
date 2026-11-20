// Widget test for the Phase 0 hello-world screen.
//
// CLAUDE.md: tests MUST NOT call Gemini. GeneratorService creates its model
// lazily, so building the screen here never touches Firebase or the network.

import 'package:flutter_test/flutter_test.dart';

import 'package:study_buddy/main.dart';
import 'package:study_buddy/services/generator_service.dart';

void main() {
  testWidgets('Hello screen shows the pick-PDF button', (tester) async {
    await tester.pumpWidget(StudyBuddyApp(generator: GeneratorService()));

    expect(find.text('Study Buddy · Hello Gemini'), findsOneWidget);
    expect(find.text('Pick a lecture PDF'), findsOneWidget);
  });
}
