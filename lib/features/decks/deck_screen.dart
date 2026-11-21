import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../models/reviewer_item.dart';
import '../../providers.dart';
import '../../theme.dart';
import '../../widgets/rich_terms.dart';
import '../study/flashcards_screen.dart';
import '../study/match_screen.dart';
import '../study/study_controller.dart';
import '../study/study_screen.dart';
import '../study/test_screen.dart';

final deckProvider = StreamProvider.family<Deck?, int>((ref, deckId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.decks)..where((d) => d.id.equals(deckId))).watchSingleOrNull();
});

final deckQuestionsProvider = StreamProvider.family<List<Question>, int>(
  (ref, deckId) => ref.watch(databaseProvider).watchQuestions(deckId),
);

final deckNotesProvider = StreamProvider.family<List<NoteSectionRow>, int>(
  (ref, deckId) => ref.watch(databaseProvider).watchNotes(deckId),
);

const questionTypeLabels = {
  'flashcard': 'Flashcard',
  'multiple_choice': 'Multiple choice',
  'identification': 'Identification',
  'enumeration': 'Enumeration',
  'true_false': 'True or false',
  'modified_true_false': 'Modified true or false',
};

/// A saved reviewer (design feedback #2 + #4): header, flashcard preview,
/// study-mode tiles, then tabs Flashcards · Notes · Questions. Offline.
class DeckScreen extends ConsumerWidget {
  const DeckScreen({super.key, required this.deckId});

  final int deckId;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this reviewer?'),
        content: const Text('Its flashcards, notes, questions and review progress will be deleted too.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(databaseProvider).deleteDeck(deckId);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deck = ref.watch(deckProvider(deckId)).value;
    final questions = ref.watch(deckQuestionsProvider(deckId)).value;
    final notes = ref.watch(deckNotesProvider(deckId)).value;
    if (deck == null || questions == null || notes == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }

    final flashcards = questions.where((q) => q.type == 'flashcard').toList();
    final quiz = questions.where((q) => q.type != 'flashcard').toList();
    final quizTypes = {for (final q in quiz) ?QuestionType.fromJsonName(q.type)};

    // Tab order from design feedback #2: Flashcards · Notes · Questions.
    final tabs = <(String, Widget)>[
      if (flashcards.isNotEmpty) ('Flashcards', FlashcardList(cards: flashcards)),
      if (notes.isNotEmpty) ('Notes', NotesList(notes: notes)),
      if (quiz.isNotEmpty) ('Questions', QuestionList(questions: quiz)),
    ];

    final modes = <(IconData, String, String, VoidCallback)>[
      if (flashcards.isNotEmpty)
        (Icons.style, 'Flashcards', '${flashcards.length} cards',
            () => _open(context, FlashcardsScreen(deckId: deckId))),
      if (quiz.isNotEmpty)
        (Icons.quiz, 'Quiz', 'Spaced review',
            () => _open(context, StudyScreen(deckId: deckId, mode: StudyMode.quiz))),
      if (quiz.isNotEmpty)
        (Icons.assignment, 'Test', 'Practice exam',
            () => _open(context, TestScreen(deckId: deckId, availableTypes: quizTypes))),
      if (flashcards.length >= 2)
        (Icons.extension, 'Match', 'Beat the clock', () => _open(context, MatchScreen(deckId: deckId))),
    ];

    return DefaultTabController(
      length: tabs.isEmpty ? 1 : tabs.length,
      child: Scaffold(
        floatingActionButton: tabs.isEmpty
            ? null
            : _TabActionButton(
                tabNames: [for (final t in tabs) t.$1],
                onStudyFlashcards: () => _open(context, FlashcardsScreen(deckId: deckId)),
                onTakeQuiz: () => _open(context, StudyScreen(deckId: deckId, mode: StudyMode.quiz)),
              ),
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverAppBar(
              pinned: true,
              title: Text(deck.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  tooltip: 'Delete reviewer',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context, ref),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: _DeckHeader(deck: deck, flashcards: flashcards, quizCount: quiz.length, hasNotes: notes.isNotEmpty),
            ),
            if (flashcards.isNotEmpty) SliverToBoxAdapter(child: FlashcardCarousel(cards: flashcards)),
            if (modes.isNotEmpty) SliverToBoxAdapter(child: _ModeTiles(modes: modes)),
            if (tabs.isNotEmpty)
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarHeader(TabBar(tabs: [for (final t in tabs) Tab(text: t.$1)]),
                    Theme.of(context).scaffoldBackgroundColor),
              ),
          ],
          body: tabs.isEmpty
              ? const Center(child: Text('Walang laman ang reviewer na ito.'))
              : TabBarView(children: [for (final t in tabs) t.$2]),
        ),
      ),
    );
  }
}

class _DeckHeader extends StatelessWidget {
  const _DeckHeader({required this.deck, required this.flashcards, required this.quizCount, required this.hasNotes});

  final Deck deck;
  final List<Question> flashcards;
  final int quizCount;
  final bool hasNotes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = [
      if (flashcards.isNotEmpty) '${flashcards.length} flashcards',
      if (quizCount > 0) '$quizCount questions',
      if (hasNotes) 'notes',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (deck.subject.isNotEmpty) Text(deck.subject, style: theme.textTheme.labelLarge),
          Text(counts, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Swipeable flashcard preview at the top; tap a card to flip it.
class FlashcardCarousel extends StatelessWidget {
  const FlashcardCarousel({super.key, required this.cards});

  final List<Question> cards;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.88),
        itemCount: cards.length,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: _PreviewCard(card: cards[i]),
        ),
      ),
    );
  }
}

class _PreviewCard extends StatefulWidget {
  const _PreviewCard({required this.card});
  final Question card;

  @override
  State<_PreviewCard> createState() => _PreviewCardState();
}

class _PreviewCardState extends State<_PreviewCard> {
  bool _back = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _back = !_back),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: AnimatedSwitcher(
              duration: motion(context, 200),
              child: SingleChildScrollView(
                key: ValueKey(_back),
                child: RichTerms(
                  _back ? widget.card.answer : widget.card.prompt,
                  style: _back ? theme.textTheme.bodyLarge : theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeTiles extends StatelessWidget {
  const _ModeTiles({required this.modes});

  final List<(IconData, String, String, VoidCallback)> modes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.4,
        children: [
          for (final (icon, title, subtitle, onTap) in modes)
            Card(
              margin: EdgeInsets.zero,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Icon(icon, color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: theme.textTheme.titleMedium),
                            Text(subtitle, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The floating button follows the tab (design feedback #2).
class _TabActionButton extends StatelessWidget {
  const _TabActionButton({required this.tabNames, required this.onStudyFlashcards, required this.onTakeQuiz});

  final List<String> tabNames;
  final VoidCallback onStudyFlashcards;
  final VoidCallback onTakeQuiz;

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => switch (tabNames[controller.index]) {
        'Flashcards' => FloatingActionButton.extended(
            onPressed: onStudyFlashcards,
            icon: const Icon(Icons.style),
            label: const Text('Study flashcards'),
          ),
        'Questions' => FloatingActionButton.extended(
            onPressed: onTakeQuiz,
            icon: const Icon(Icons.quiz),
            label: const Text('Take quiz'),
          ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

class _TabBarHeader extends SliverPersistentHeaderDelegate {
  _TabBarHeader(this.tabBar, this.background);
  final TabBar tabBar;
  final Color background;

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      ColoredBox(color: background, child: tabBar);

  @override
  bool shouldRebuild(_TabBarHeader oldDelegate) => oldDelegate.tabBar != tabBar;
}

/// Room at the bottom so the floating button never covers the last item.
const _listPadding = EdgeInsets.fromLTRB(16, 12, 16, 96);

/// Every flashcard: term and meaning.
class FlashcardList extends StatelessWidget {
  const FlashcardList({super.key, required this.cards});

  final List<Question> cards;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.builder(
      padding: _listPadding,
      itemCount: cards.length,
      itemBuilder: (context, i) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichTerms(cards[i].prompt, style: theme.textTheme.titleMedium),
              const Divider(height: 20),
              RichTerms(cards[i].answer),
            ],
          ),
        ),
      ),
    );
  }
}

/// Key points by topic, with bold key terms (design feedback #1).
class NotesList extends StatelessWidget {
  const NotesList({super.key, required this.notes});

  final List<NoteSectionRow> notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.builder(
      padding: _listPadding,
      itemCount: notes.length,
      itemBuilder: (context, i) {
        final section = notes[i];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(section.heading, style: theme.textTheme.titleMedium)),
                    const SizedBox(width: 8),
                    Text('page ${section.sourcePage}', style: theme.textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 8),
                for (final point in section.points)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  '),
                        Expanded(child: RichTerms(point)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Quiz questions (no flashcards) with answers.
class QuestionList extends StatelessWidget {
  const QuestionList({super.key, required this.questions});

  final List<Question> questions;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: _listPadding,
      itemCount: questions.length,
      itemBuilder: (context, i) {
        final q = questions[i];
        return Card(
          child: ExpansionTile(
            shape: const Border(),
            title: Text(q.prompt),
            subtitle: Text('${questionTypeLabels[q.type] ?? q.type} · page ${q.sourcePage}'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (q.choices.isNotEmpty) Text('Choices: ${q.choices.join(' · ')}'),
              if (q.underlinedWord != null) Text('Underlined: ${q.underlinedWord}'),
              Text('Answer: ${q.answer}', style: const TextStyle(fontWeight: FontWeight.bold)),
              if (q.type == 'modified_true_false' && q.answer == 'False') Text('Correction: ${q.correction}'),
              const SizedBox(height: 8),
              RichTerms(q.explanation),
            ],
          ),
        );
      },
    );
  }
}
