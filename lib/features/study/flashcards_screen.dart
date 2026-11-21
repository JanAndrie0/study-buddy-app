import 'dart:math';

import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' show Rating;
import 'package:material_ui/material_ui.dart';

import '../../theme.dart';
import '../../widgets/rich_terms.dart';
import 'study_controller.dart';

/// Flashcards mode (design feedback #4): every flashcard in the deck, tap to
/// flip, swipe right = Know (FSRS Good), swipe left = Still learning (Again).
class FlashcardsScreen extends ConsumerStatefulWidget {
  const FlashcardsScreen({super.key, required this.deckId});

  final int deckId;

  @override
  ConsumerState<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends ConsumerState<FlashcardsScreen> {
  bool _flipped = false;
  int _round = 1;

  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(studyProvider.notifier).start(deckId: widget.deckId, mode: StudyMode.flashcards));
  }

  Future<void> _rate(Rating rating) async {
    HapticFeedback.selectionClick();
    setState(() => _flipped = false);
    await ref.read(studyProvider.notifier).rateFlashcard(rating);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(studyProvider);
    final theme = Theme.of(context);
    final know = state.answers.where((a) => a.grade.isCorrect).length;
    final learning = state.answers.length - know;

    return Scaffold(
      appBar: AppBar(
        title: Text(_round == 1 ? 'Flashcards' : 'Flashcards · round $_round'),
        actions: [
          if (state.phase == StudyPhase.answering)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Text('${state.index + 1} / ${state.queue.length}')),
            ),
        ],
      ),
      body: switch (state.phase) {
        StudyPhase.loading => const Center(child: CircularProgressIndicator()),
        StudyPhase.done => _RoundEnd(
            know: know,
            learning: learning,
            onReviewLearning: learning == 0
                ? null
                : () {
                    setState(() => _round++);
                    ref.read(studyProvider.notifier).restartWith([
                      for (final a in state.answers)
                        if (!a.grade.isCorrect) a.card.question.id,
                    ]);
                  },
          ),
        _ => SafeArea(
            top: false,
            child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _Counter(label: 'Still learning', count: learning, color: warningColor(context)),
                    _Counter(label: 'Know', count: know, color: successColor(context)),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: state.queue.isEmpty ? 0 : state.answers.length / state.queue.length,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Dismissible(
                    key: ValueKey('${state.current!.question.id}-$_round-${state.index}'),
                    onDismissed: (direction) =>
                        _rate(direction == DismissDirection.startToEnd ? Rating.good : Rating.again),
                    background: _SwipeHint(
                        label: 'Know', icon: Icons.check, color: successColor(context), alignLeft: true),
                    secondaryBackground:
                        _SwipeHint(label: 'Still learning', icon: Icons.replay, color: warningColor(context)),
                    child: Semantics(
                      button: true,
                      label: _flipped ? 'Flashcard, back side. Tap to flip.' : 'Flashcard, front side. Tap to flip.',
                      child: GestureDetector(
                      onTap: () => setState(() => _flipped = !_flipped),
                      child: _FlipCard(
                        flipped: _flipped,
                        front: Text(state.current!.question.prompt,
                            style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                        back: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RichTerms(state.current!.question.answer,
                                style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            RichTerms(state.current!.question.explanation,
                                style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Tap to flip · swipe right if you know it, left if not',
                    style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _rate(Rating.again),
                        icon: const Icon(Icons.close),
                        label: const Text('Still learning'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: successColor(context),
                          foregroundColor: onSemanticColor(context),
                        ),
                        onPressed: () => _rate(Rating.good),
                        icon: const Icon(Icons.check),
                        label: const Text('Know'),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(onPressed: () => _rate(Rating.hard), child: const Text('Hard')),
                    TextButton(onPressed: () => _rate(Rating.easy), child: const Text('Easy')),
                  ],
                ),
              ],
            ),
          ),
          ),
      },
    );
  }
}

/// Front/back card that turns over like a real card.
class _FlipCard extends StatelessWidget {
  const _FlipCard({required this.flipped, required this.front, required this.back});

  final bool flipped;
  final Widget front;
  final Widget back;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: flipped ? pi : 0),
      duration: motion(context, 300),
      curve: Curves.easeInOut,
      builder: (context, angle, _) {
        final showBack = angle > pi / 2;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..rotateY(showBack ? pi : 0),
            child: Card(
              child: SizedBox.expand(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: SingleChildScrollView(child: showBack ? back : front)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SwipeHint extends StatelessWidget {
  const _SwipeHint({required this.label, required this.icon, required this.color, this.alignLeft = false});

  final IconData icon;

  final String label;
  final Color color;
  final bool alignLeft;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      alignment: alignLeft ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 20)),
        ],
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.label, required this.count, required this.color});

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$label  $count', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

class _RoundEnd extends StatelessWidget {
  const _RoundEnd({required this.know, required this.learning, required this.onReviewLearning});

  final int know;
  final int learning;
  final VoidCallback? onReviewLearning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (know + learning == 0) {
      return const Center(child: Text('Walang flashcards sa reviewer na ito.'));
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(learning == 0 ? Icons.emoji_events_outlined : Icons.check_circle_outline,
              size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 8),
          Text(learning == 0 ? 'Alam mo na lahat!' : 'Nice round!',
              style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Counter(label: 'Know', count: know, color: successColor(context)),
              const SizedBox(width: 12),
              _Counter(label: 'Still learning', count: learning, color: warningColor(context)),
            ],
          ),
          const SizedBox(height: 32),
          if (onReviewLearning != null) ...[
            FilledButton(onPressed: onReviewLearning, child: Text('Review the $learning still learning')),
            const SizedBox(height: 8),
          ],
          OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        ],
      ),
    );
  }
}
