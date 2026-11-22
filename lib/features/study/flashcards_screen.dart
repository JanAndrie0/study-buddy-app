import 'dart:math';

import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' show Rating;
import 'package:material_ui/material_ui.dart';

import '../../theme.dart';
import '../../widgets/rich_terms.dart';
import '../../widgets/ui.dart';
import 'study_controller.dart';

/// Flashcards mode (design feedback #4, Figma "Flashcards" row): every
/// flashcard in the deck, tap to flip, swipe right = Know (FSRS Good), swipe
/// left = Still learning (Again).
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
    final t = context.tokens;
    final know = state.answers.where((a) => a.grade.isCorrect).length;
    final learning = state.answers.length - know;

    return Scaffold(
      appBar: AppBar(
        title: Text(_round == 1 ? 'Flashcards' : 'Flashcards · round $_round'),
        actions: [
          if (state.phase == StudyPhase.answering)
            Padding(
              padding: const EdgeInsets.only(right: Space.lg),
              child: Center(
                child: Text('${state.index + 1} / ${state.queue.length}', style: theme.textTheme.labelMedium),
              ),
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
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.lg, Space.sm),
              child: Column(
                children: [
                  AnimatedBar(value: state.queue.isEmpty ? 0 : state.answers.length / state.queue.length),
                  const SizedBox(height: Space.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _Counter(label: 'Still learning', count: learning, color: t.error, background: t.errorSoft),
                      _Counter(label: 'Know', count: know, color: t.success, background: t.successSoft),
                    ],
                  ),
                  const SizedBox(height: Space.lg),
                  Expanded(
                    child: Dismissible(
                      key: ValueKey('${state.current!.question.id}-$_round-${state.index}'),
                      onDismissed: (direction) =>
                          _rate(direction == DismissDirection.startToEnd ? Rating.good : Rating.again),
                      background: _SwipeHint(
                          label: 'Know', icon: Icons.check, color: t.success, background: t.successSoft, alignLeft: true),
                      secondaryBackground: _SwipeHint(
                          label: 'Still learning', icon: Icons.replay, color: t.error, background: t.errorSoft),
                      child: Semantics(
                        button: true,
                        label: _flipped ? 'Flashcard, back side. Tap to flip.' : 'Flashcard, front side. Tap to flip.',
                        child: GestureDetector(
                          onTap: () => setState(() => _flipped = !_flipped),
                          child: _FlipCard(
                            flipped: _flipped,
                            front: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SectionLabel('Term', color: t.textAccent),
                                const SizedBox(height: Space.md),
                                RichTerms(state.current!.question.prompt,
                                    style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
                              ],
                            ),
                            back: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SectionLabel('Definition', color: t.textAccent),
                                const SizedBox(height: Space.md),
                                RichTerms(state.current!.question.answer,
                                    style: questionStyle(context), textAlign: TextAlign.center),
                                // Cards made from the notes (ADR-010) have no separate explanation.
                                if (state.current!.question.explanation.isNotEmpty) ...[
                                  const SizedBox(height: Space.lg),
                                  RichTerms(state.current!.question.explanation,
                                      style: theme.textTheme.bodyMedium!.copyWith(color: t.textSecondary),
                                      textAlign: TextAlign.center),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.md),
                  Text('Tap to flip · swipe right if you know it, left if not',
                      style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                  const SizedBox(height: Space.md),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _rate(Rating.again),
                          icon: const Icon(Icons.close),
                          label: const Text('Still learning'),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: t.success, foregroundColor: t.onStatus),
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

/// Front/back card that turns over like a real card (motion spec: 3D turn on
/// Y, 400 ms; the content swaps at 90°).
class _FlipCard extends StatelessWidget {
  const _FlipCard({required this.flipped, required this.front, required this.back});

  final bool flipped;
  final Widget front;
  final Widget back;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: flipped ? pi : 0),
      duration: motion(context, Motion.long),
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
            child: Container(
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(Radii.xl),
                border: Border.all(color: t.border),
                boxShadow: const [BoxShadow(color: Color(0x141B1F2A), blurRadius: 20, offset: Offset(0, 6))],
              ),
              child: SizedBox.expand(
                child: Padding(
                  padding: const EdgeInsets.all(Space.xxl),
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
  const _SwipeHint({
    required this.label,
    required this.icon,
    required this.color,
    required this.background,
    this.alignLeft = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;
  final bool alignLeft;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(Radii.xl)),
      alignment: alignLeft ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: Space.sm),
          Text(label, style: Theme.of(context).textTheme.titleLarge!.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// "Know · 5" pill (Figma "Counter").
class _Counter extends StatelessWidget {
  const _Counter({required this.label, required this.count, required this.color, required this.background});

  final String label;
  final int count;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 6),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(99)),
      child: Text('$label · $count', style: Theme.of(context).textTheme.labelMedium!.copyWith(color: color)),
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
    final t = context.tokens;
    if (know + learning == 0) {
      return const EmptyState(icon: Icons.style_outlined, title: 'Walang flashcards sa reviewer na ito.');
    }
    Widget stat(int n, String label, Color color, Color background) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: Space.lg),
            decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(Radii.lg)),
            child: Column(
              children: [
                Text('$n', style: theme.textTheme.headlineMedium!.copyWith(color: color)),
                Text(label, style: theme.textTheme.labelMedium!.copyWith(color: color)),
              ],
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.all(Space.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: IconDisc(icon: learning == 0 ? Icons.emoji_events_outlined : Icons.local_fire_department_outlined),
          ),
          const SizedBox(height: Space.lg),
          Text(learning == 0 ? 'Alam mo na lahat!' : 'Nice round!',
              style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
          const SizedBox(height: Space.sm),
          Text('Cards you know come back later, right before you would forget them.',
              style: theme.textTheme.bodyLarge!.copyWith(color: t.textSecondary), textAlign: TextAlign.center),
          const SizedBox(height: Space.xl),
          Row(
            children: [
              stat(know, 'Know', t.success, t.successSoft),
              const SizedBox(width: Space.sm),
              stat(learning, 'Still learning', t.error, t.errorSoft),
            ],
          ),
          const SizedBox(height: Space.xxxl),
          if (onReviewLearning != null) ...[
            FilledButton(onPressed: onReviewLearning, child: Text('Review the $learning still learning')),
            const SizedBox(height: Space.sm),
          ],
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        ],
      ),
    );
  }
}
