import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../providers.dart';
import '../add_lecture/add_lecture_screen.dart';
import '../decks/deck_screen.dart';
import '../settings/settings_screen.dart';
import '../study/study_screen.dart';

/// Home: what's due today and your saved reviewers. Works offline.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decks = ref.watch(deckSummariesProvider);
    final due = ref.watch(dueCountProvider).value ?? 0;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Study Buddy'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AddLectureScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add lecture'),
      ),
      body: decks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.menu_book_outlined, size: 72, color: theme.colorScheme.primary),
                    const SizedBox(height: 16),
                    Text('Wala pang reviewer', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text(
                      'Turn a lecture PDF into flashcards, notes and a quiz you can study offline.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AddLectureScreen()),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Add lecture'),
                    ),
                  ],
                ),
              ),
            );
          }
          final progress = ref.watch(deckProgressProvider).value ?? const {};
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              // Hero card: what to review today.
              Card(
                color: theme.colorScheme.primary,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$due', style: theme.textTheme.headlineMedium?.copyWith(color: theme.colorScheme.onPrimary)),
                            Text(due == 1 ? 'card due today' : 'cards due today',
                                style: TextStyle(color: theme.colorScheme.onPrimary)),
                          ],
                        ),
                      ),
                      if (due > 0)
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.onPrimary,
                            foregroundColor: theme.colorScheme.primary,
                          ),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const StudyScreen()),
                          ),
                          child: const Text('Mag-review na'),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Your reviewers', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              for (final summary in list)
                Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => DeckScreen(deckId: summary.deck.id)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(summary.deck.title, style: theme.textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text([
                            if (summary.deck.subject.isNotEmpty) summary.deck.subject,
                            if (summary.questionCount > 0) '${summary.questionCount} cards',
                            if (summary.noteCount > 0) 'notes',
                          ].join(' · '), style: theme.textTheme.bodySmall),
                          if (progress[summary.deck.id] case (final known, final total) when total > 0) ...[
                            const SizedBox(height: 10),
                            LinearProgressIndicator(
                              value: known / total,
                              minHeight: 6,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            const SizedBox(height: 4),
                            Text('${(100 * known / total).round()}% known', style: theme.textTheme.bodySmall),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
