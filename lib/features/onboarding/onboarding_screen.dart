import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../../theme.dart';

/// Three short intro screens, shown once on first launch (Phase 5).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;

  static const _slides = [
    (
      Icons.picture_as_pdf_outlined,
      'Your lectures, your reviewer',
      'Add a lecture PDF and get flashcards, notes and a Filipino-style quiz: identification, enumeration, modified true or false and more.',
    ),
    (
      Icons.wifi_off_outlined,
      'Study anywhere, even offline',
      'Internet is only needed to make a reviewer. After that, everything works on the jeep, in class or in airplane mode.',
    ),
    (
      Icons.event_repeat_outlined,
      'Review at the right time',
      'Study Buddy remembers what you know and brings cards back just before you forget them. Check "due today" on Home.',
    ),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish() =>
      ref.read(databaseProvider).updateSettings(const AppSettingsCompanion(onboardingDone: Value(true)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _page == _slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _finish, child: const Text('Skip')),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  for (final (icon, title, text) in _slides)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, size: 96, color: theme.colorScheme.primary),
                          const SizedBox(height: 32),
                          Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          Text(text, style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            // Page dots.
            Semantics(
              label: 'Page ${_page + 1} of ${_slides.length}',
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _slides.length; i++)
                    AnimatedContainer(
                      duration: motion(context, 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _page ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: last
                      ? _finish
                      : () => _pages.nextPage(duration: motion(context, 250), curve: Curves.easeOut),
                  child: Text(last ? 'Get started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
