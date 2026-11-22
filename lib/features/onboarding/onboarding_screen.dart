import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../../theme.dart';
import '../../widgets/logo.dart';
import '../../widgets/ui.dart';

/// Three short intro screens, shown once on first launch (Phase 5).
/// Figma: "Onboarding 1–3".
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;

  // (icon, tag, title, text). The first slide shows the logo instead of an icon.
  static const _slides = [
    (
      null,
      'PDF → reviewer',
      'Your lectures, your reviewer',
      'Add a lecture PDF and get flashcards, notes and a Filipino-style quiz: identification, enumeration, modified true or false and more.',
    ),
    (
      Icons.wifi_off_outlined,
      'Works offline',
      'Study anywhere, even offline',
      'Internet is only needed to make a reviewer. After that, everything works on the jeep, in class or in airplane mode.',
    ),
    (
      Icons.event_repeat_outlined,
      'Spaced review',
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
    final t = context.tokens;
    final last = _page == _slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.sm, 0),
              child: Row(
                children: [
                  Expanded(child: Text('Page ${_page + 1} of ${_slides.length}', style: theme.textTheme.bodySmall)),
                  // Hidden (not removed) on the last page so the layout doesn't jump.
                  Visibility.maintain(
                    visible: !last,
                    child: TextButton(onPressed: _finish, child: const Text('Skip')),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  for (final (icon, tag, title, text) in _slides)
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(Space.xxl),
                      child: Column(
                        children: [
                          const SizedBox(height: Space.xxl),
                          Container(
                            width: 280,
                            height: 220,
                            decoration: BoxDecoration(color: t.accentSoft, borderRadius: BorderRadius.circular(Radii.xl)),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (icon == null)
                                  const StudyBuddyLogo(size: 112)
                                else
                                  IconDisc(icon: icon, background: t.surface, size: 104),
                                const SizedBox(height: Space.lg),
                                TagPill(tag, background: t.surface),
                              ],
                            ),
                          ),
                          const SizedBox(height: Space.xxl),
                          Text(title, style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
                          const SizedBox(height: Space.md),
                          Text(text,
                              style: theme.textTheme.bodyLarge!.copyWith(color: t.textSecondary),
                              textAlign: TextAlign.center),
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
                      duration: motion(context, Motion.medium),
                      curve: Motion.standard,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page ? t.primary : t.track,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.xl, Space.lg, Space.xxl),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: last
                      ? _finish
                      : () => _pages.nextPage(duration: motion(context, Motion.long), curve: Motion.standard),
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
