import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../models/reviewer_item.dart';
import '../../theme.dart';
import '../../widgets/motion.dart';
import '../../widgets/rich_terms.dart';
import '../../widgets/ui.dart';
import '../decks/deck_screen.dart' show questionTypeLabels;
import 'question_views.dart';
import 'study_controller.dart';

/// Quiz / review session: one question per screen, a feedback banner that
/// slides up from the bottom, then a summary. Works in airplane mode.
/// [deckId] null = all due cards from every deck. Figma: "Quiz" row.
class StudyScreen extends ConsumerStatefulWidget {
  const StudyScreen({super.key, this.deckId, this.mode = StudyMode.review});

  final int? deckId;
  final StudyMode mode;

  @override
  ConsumerState<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends ConsumerState<StudyScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(studyProvider.notifier).start(deckId: widget.deckId, mode: widget.mode));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(studyProvider);
    final controller = ref.read(studyProvider.notifier);
    final total = state.queue.length;
    final answering = state.phase == StudyPhase.answering || state.phase == StudyPhase.feedback;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mode == StudyMode.quiz ? 'Quiz' : 'Review'),
        actions: [
          if (answering) _Counter('${state.index + 1} / $total'),
        ],
        bottom: answering ? SegmentedProgress(done: state.answers.length, total: total) : null,
      ),
      bottomSheet: state.phase == StudyPhase.feedback
          ? FeedbackBanner(answer: state.lastAnswer!, onContinue: controller.next)
          : null,
      body: switch (state.phase) {
        StudyPhase.loading => const Center(child: CircularProgressIndicator()),
        StudyPhase.done => SessionSummary(
            state: state,
            onStudyAnyway: () =>
                controller.start(deckId: widget.deckId, mode: widget.mode, ignoreNewLimit: true),
          ),
        _ => ListView(
            // Room at the bottom so the feedback banner never hides the question.
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 300),
            children: [
              QuestionTypeTag(item: state.item!),
              const SizedBox(height: Space.md),
              QuestionView(
                key: ValueKey(state.current!.question.id),
                item: state.item!,
                locked: state.phase == StudyPhase.feedback,
                onGraded: (grade, text) {
                  // Feel the result before you read it (touch feedback).
                  grade.isCorrect ? HapticFeedback.lightImpact() : HapticFeedback.mediumImpact();
                  controller.submit(grade, answeredText: text);
                },
                onRate: controller.rateFlashcard,
              ),
            ],
          ),
      },
    );
  }
}

/// "4 / 10" in the app bar.
class _Counter extends StatelessWidget {
  const _Counter(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: Space.lg),
        child: Center(child: Text(text, style: Theme.of(context).textTheme.labelMedium)),
      );
}

/// "Multiple choice", "Identification"… above the question (Figma "Tag").
class QuestionTypeTag extends StatelessWidget {
  const QuestionTypeTag({super.key, required this.item});
  final ReviewerItem item;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: TagPill(questionTypeLabels[item.type.jsonName] ?? item.type.jsonName),
      );
}

/// A row of small bars: filled = answered. Each bar fills in as you answer.
class SegmentedProgress extends StatelessWidget implements PreferredSizeWidget {
  const SegmentedProgress({super.key, required this.done, required this.total});

  final int done;
  final int total;

  @override
  Size get preferredSize => const Size.fromHeight(12);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (total == 0) return const SizedBox(height: 12);
    // Many questions: one continuous bar is easier to read than tiny segments.
    if (total > 25) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, 6),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: done / total),
          duration: motion(context, Motion.medium),
          curve: Motion.standard,
          builder: (context, v, _) => LinearProgressIndicator(value: v, borderRadius: BorderRadius.circular(3)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, 6),
      child: Row(
        children: [
          for (var i = 0; i < total; i++)
            Expanded(
              child: AnimatedContainer(
                duration: motion(context, Motion.medium),
                curve: Motion.standard,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: i < done ? t.primary : t.track,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String correctAnswerText(ReviewerItem item) => switch (item.type) {
      QuestionType.enumeration => item.items.join(', '),
      QuestionType.modifiedTrueFalse => item.isTrue
          ? 'True (tama ang "${item.underlinedWord}")'
          : 'False → "${item.underlinedWord}" dapat "${item.correction}"',
      _ => item.answer,
    };

/// Slides up after an answer (Figma "Feedback banner"): icon + title + colour
/// show the result, then the correct answer, the explanation (bold key
/// terms), the source page and Continue.
class FeedbackBanner extends StatelessWidget {
  const FeedbackBanner({super.key, required this.answer, required this.onContinue});

  final StudyAnswer answer;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.tokens;
    final item = answer.card.question.toItem();
    final grade = answer.grade;
    final partial = !grade.isCorrect && grade.score > 0;
    final (color, icon, buttonBg, buttonFg) = grade.isCorrect
        ? (t.success, Icons.check_circle, t.success, t.onStatus)
        : partial
            ? (t.warning, Icons.error_outline, t.primary, t.onPrimary)
            : (t.error, Icons.cancel, t.error, t.onStatus);
    final title = grade.isCorrect
        ? 'Tama! Great job'
        : partial
            ? (item.type == QuestionType.enumeration
                ? 'Halos! ${(grade.score * item.items.length).round()}/${item.items.length} tama'
                : 'Halos! Kalahati ang tama')
            : 'Not quite';

    return TweenAnimationBuilder<Offset>(
      tween: Tween(begin: const Offset(0, 1), end: Offset.zero),
      duration: motion(context, Motion.medium),
      curve: Motion.standard,
      builder: (context, offset, child) => FractionalTranslation(translation: offset, child: child),
      child: Material(
        color: t.surface,
        elevation: 12,
        shadowColor: Colors.black38,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.xl)),
          side: BorderSide(color: t.border),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  PopIn(child: Icon(icon, color: color, size: 26)),
                  const SizedBox(width: Space.sm),
                  Expanded(child: Text(title, style: theme.textTheme.titleLarge!.copyWith(color: color))),
                ]),
                if (!grade.isCorrect) ...[
                  const SizedBox(height: Space.sm),
                  Text('Correct answer', style: theme.textTheme.labelSmall),
                  Text(correctAnswerText(item), style: theme.textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: Space.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 140),
                  child: SingleChildScrollView(child: RichTerms(item.explanation)),
                ),
                const SizedBox(height: Space.sm),
                Row(children: [
                  Icon(Icons.description_outlined, size: 16, color: t.textSecondary),
                  const SizedBox(width: Space.xs),
                  Text('Source: page ${item.sourcePage}', style: theme.textTheme.bodySmall),
                ]),
                const SizedBox(height: Space.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: buttonBg, foregroundColor: buttonFg),
                    onPressed: onContinue,
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Score ring and the questions to look at again.
class SessionSummary extends StatelessWidget {
  const SessionSummary({super.key, required this.state, this.onRetake, this.onStudyAnyway, this.emptyMessage});

  final StudyState state;
  final VoidCallback? onRetake;

  /// Shown when today's new-card limit held cards back (bug B3).
  final VoidCallback? onStudyAnyway;

  /// What to say when there was nothing to answer (defaults to "nothing due").
  /// The first line is the title, the rest the body.
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.tokens;
    if (state.answers.isEmpty) {
      if (state.heldBackNew > 0) {
        return EmptyState(
          icon: Icons.hourglass_bottom,
          title: "You've reached today's new-card limit.",
          body: '${state.heldBackNew} new cards are waiting. You can change the limit in Settings.',
          action: onStudyAnyway == null
              ? null
              : FilledButton(onPressed: onStudyAnyway, child: const Text('Study anyway')),
        );
      }
      final lines = (emptyMessage ?? 'Walang due ngayon.\nCome back later, or try Flashcards or Test.').split('\n');
      return EmptyState(
        icon: Icons.check_circle_outline,
        title: lines.first,
        body: lines.length > 1 ? lines.skip(1).join('\n') : null,
        action: onRetake == null ? null : OutlinedButton(onPressed: onRetake, child: const Text('Retake')),
      );
    }
    final total = state.answers.length;
    final correct = state.correctCount;
    final missed = state.answers.where((a) => !a.grade.isCorrect).toList();
    return ListView(
      padding: const EdgeInsets.all(Space.xxl),
      children: [
        Center(child: ScoreRing(correct: correct, total: total)),
        const SizedBox(height: Space.lg),
        Text(correct == total ? 'Perfect!' : 'Tapos na!',
            style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
        if (missed.isNotEmpty) ...[
          const SizedBox(height: Space.xxl),
          Text('Balikan mo ang mga ito:', style: theme.textTheme.titleLarge),
          const SizedBox(height: Space.sm),
          for (final (i, answer) in missed.indexed)
            FadeSlideIn(
              index: i,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(Space.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(answer.card.question.prompt, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 6),
                      _MarkRow(
                        icon: Icons.check,
                        color: t.success,
                        text: 'Answer: ${correctAnswerText(answer.card.question.toItem())}',
                        bold: true,
                      ),
                      if (answer.answeredText != null && answer.answeredText!.isNotEmpty)
                        _MarkRow(icon: Icons.close, color: t.error, text: 'You: ${answer.answeredText}'),
                      const SizedBox(height: 6),
                      RichTerms(answer.card.question.explanation, style: theme.textTheme.bodyMedium),
                      Text('page ${answer.card.question.sourcePage}', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
        ],
        const SizedBox(height: Space.xxl),
        if (onRetake != null) ...[
          OutlinedButton(onPressed: onRetake, child: const Text('Retake')),
          const SizedBox(height: Space.sm),
        ],
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ],
    );
  }
}

/// ✓ Answer: … / ✗ You: … line in the summary.
class _MarkRow extends StatelessWidget {
  const _MarkRow({required this.icon, required this.color, required this.text, this.bold = false});

  final IconData icon;
  final Color color;
  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 16, color: color)),
        const SizedBox(width: Space.xs),
        Expanded(
          child: Text(text, style: bold ? style.copyWith(color: color, fontWeight: FontWeight.w700) : style),
        ),
      ],
    );
  }
}

/// Big circular score: the ring fills and the % counts up from 0, e.g. 80%
/// with "8 / 10" under it. Green ≥ 75 %, amber ≥ 50 %, otherwise red.
class ScoreRing extends StatelessWidget {
  const ScoreRing({super.key, required this.correct, required this.total});

  final int correct;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.tokens;
    final value = total == 0 ? 0.0 : correct / total;
    final color = value >= 0.75 ? t.success : (value >= 0.5 ? t.warning : t.error);
    return Semantics(
      label: 'Score ${(value * 100).round()} percent, $correct of $total correct',
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: motion(context, Motion.celebrate),
        curve: Motion.standard,
        builder: (context, v, _) => SizedBox(
          width: 140,
          height: 140,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: v,
                strokeWidth: 12,
                backgroundColor: t.track,
                color: color,
                strokeCap: StrokeCap.round,
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${(v * 100).round()}%', style: theme.textTheme.headlineMedium),
                    Text('$correct / $total', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
