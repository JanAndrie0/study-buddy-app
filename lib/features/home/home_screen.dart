import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../../theme.dart';
import '../../widgets/motion.dart';
import '../../widgets/ui.dart';
import '../add_lecture/add_lecture_screen.dart';
import '../decks/deck_screen.dart';
import '../settings/settings_screen.dart';
import '../study/study_screen.dart';

/// Home: what's due today and your saved reviewers. Works offline.
/// Figma: "3 · Screens" → Home / Home · empty.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decks = ref.watch(deckSummariesProvider);
    final due = ref.watch(dueCountProvider).value ?? 0;
    final theme = Theme.of(context);

    void open(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: Space.xl,
        title: Text('Study Buddy', style: theme.textTheme.headlineMedium),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => open(const SettingsScreen()),
          ),
          const SizedBox(width: Space.sm),
        ],
      ),
      // The empty state has its own "Add lecture" button, so no floating one there.
      floatingActionButton: (decks.value?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(
              onPressed: () => open(const AddLectureScreen()),
              icon: const Icon(Icons.add),
              label: const Text('Add lecture'),
            )
          : null,
      body: decks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.description_outlined,
              title: 'Wala pang reviewer',
              body: 'Turn a lecture PDF into flashcards, notes and a quiz you can study offline.',
              action: FilledButton.icon(
                onPressed: () => open(const AddLectureScreen()),
                icon: const Icon(Icons.add),
                label: const Text('Add lecture'),
              ),
            );
          }
          final progress = ref.watch(deckProgressProvider).value ?? const {};
          return ListView(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 96),
            children: [
              FadeSlideIn(index: 0, child: _DueCard(due: due, onReview: () => open(const StudyScreen()))),
              const SizedBox(height: Space.xxl),
              Row(
                children: [
                  Expanded(child: Text('Your reviewers', style: theme.textTheme.titleLarge)),
                  Text('${list.length}', style: theme.textTheme.labelSmall),
                ],
              ),
              const SizedBox(height: Space.sm),
              for (final (i, summary) in list.indexed)
                FadeSlideIn(
                  index: i + 1,
                  child: _DeckCard(
                    summary: summary,
                    progress: progress[summary.deck.id],
                    onTap: () => open(DeckScreen(deckId: summary.deck.id)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Navy hero: today's due count across all decks (Figma "Due card").
class _DueCard extends StatelessWidget {
  const _DueCard({required this.due, required this.onReview});

  final int due;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(color: t.hero, borderRadius: BorderRadius.circular(Radii.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('Today', color: t.heroAccent),
          const SizedBox(height: Space.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$due', style: theme.textTheme.displaySmall!.copyWith(color: t.onHero)),
              const SizedBox(width: Space.sm),
              Flexible(
                child: Text(due == 1 ? 'card due today' : 'cards due today',
                    style: theme.textTheme.headlineSmall!.copyWith(color: t.onHero)),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          if (due > 0)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: t.heroButton, foregroundColor: t.onHeroButton),
              onPressed: onReview,
              child: const Text('Mag-review na'),
            )
          else
            Text('Walang due ngayon. Open a reviewer to study ahead.',
                style: theme.textTheme.bodySmall!.copyWith(color: t.heroAccent)),
        ],
      ),
    );
  }
}

/// One reviewer in the list (Figma "Deck card").
class _DeckCard extends StatelessWidget {
  const _DeckCard({required this.summary, required this.progress, required this.onTap});

  final DeckSummary summary;
  final (int, int)? progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      if (summary.deck.subject.isNotEmpty) summary.deck.subject,
      if (summary.questionCount > 0) '${summary.questionCount} cards',
      if (summary.noteCount > 0) 'notes',
    ].join(' · ');
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(summary.deck.title, style: theme.textTheme.titleLarge)),
                  Icon(Icons.chevron_right, color: context.tokens.textSecondary),
                ],
              ),
              const SizedBox(height: 2),
              Text(meta, style: theme.textTheme.bodySmall),
              if (progress case (final known, final total) when total > 0) ...[
                const SizedBox(height: Space.md),
                Row(
                  children: [
                    Expanded(child: AnimatedBar(value: known / total)),
                    const SizedBox(width: Space.sm),
                    Text('${(100 * known / total).round()}% known', style: theme.textTheme.labelSmall),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
