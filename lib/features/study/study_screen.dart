import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../models/reviewer_item.dart';
import '../../theme.dart';
import '../../widgets/rich_terms.dart';
import 'question_views.dart';
import 'study_controller.dart';

/// Quiz / review session: one question per screen, a feedback banner that
/// slides up from the bottom, then a summary. Works in airplane mode.
/// [deckId] null = all due cards from every deck.
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
          if (answering)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Text('${state.index + 1} / $total')),
            ),
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 280),
            children: [
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

/// A row of small bars: filled = answered.
class SegmentedProgress extends StatelessWidget implements PreferredSizeWidget {
  const SegmentedProgress({super.key, required this.done, required this.total});

  final int done;
  final int total;

  @override
  Size get preferredSize => const Size.fromHeight(10);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (total == 0) return const SizedBox(height: 10);
    // Many questions: one continuous bar is easier to read than tiny segments.
    if (total > 25) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: done / total, minHeight: 6),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(
        children: [
          for (var i = 0; i < total; i++)
            Expanded(
              child: Container(
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: i < done ? scheme.primary : scheme.surfaceContainerHighest,
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

/// Slides up after an answer: green when right, red with the answer when
/// wrong, then the explanation (bold key terms), source page and Continue.
class FeedbackBanner extends StatelessWidget {
  const FeedbackBanner({super.key, required this.answer, required this.onContinue});

  final StudyAnswer answer;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = answer.card.question.toItem();
    final grade = answer.grade;
    final partial = !grade.isCorrect && grade.score > 0;
    final color = grade.isCorrect
        ? successColor(context)
        : (partial ? warningColor(context) : theme.colorScheme.error);
    final title = grade.isCorrect
        ? 'Tama! Great job'
        : partial
            ? (item.type == QuestionType.enumeration
                ? 'Halos! ${(grade.score * item.items.length).round()}/${item.items.length} tama'
                : 'Halos! Kalahati ang tama')
            : 'Not quite';

    return TweenAnimationBuilder<Offset>(
      tween: Tween(begin: const Offset(0, 1), end: Offset.zero),
      duration: motion(context, 250),
      curve: Curves.easeOutCubic,
      builder: (context, offset, child) => FractionalTranslation(translation: offset, child: child),
      child: Material(
        color: theme.cardTheme.color,
        elevation: 12,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(grade.isCorrect ? Icons.check_circle : Icons.cancel, color: color),
                  const SizedBox(width: 8),
                  Text(title, style: theme.textTheme.titleLarge?.copyWith(color: color)),
                ]),
                if (!grade.isCorrect) ...[
                  const SizedBox(height: 8),
                  Text('Correct answer', style: theme.textTheme.labelMedium),
                  Text(correctAnswerText(item), style: theme.textTheme.titleMedium),
                ],
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 140),
                  child: SingleChildScrollView(child: RichTerms(item.explanation)),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.description_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('Source: page ${item.sourcePage}', style: theme.textTheme.bodySmall),
                ]),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: grade.isCorrect || partial ? onSemanticColor(context) : theme.colorScheme.onError,
                    ),
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
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (state.answers.isEmpty) {
      final limited = state.heldBackNew > 0;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(limited ? Icons.hourglass_bottom : Icons.check_circle_outline,
                  size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                limited
                    ? "You've reached today's new-card limit.\n${state.heldBackNew} new cards are waiting."
                    : emptyMessage ?? 'Walang due ngayon.\nCome back later, or try Flashcards or Test.',
                textAlign: TextAlign.center,
              ),
              if (limited && onStudyAnyway != null) ...[
                const SizedBox(height: 20),
                FilledButton(onPressed: onStudyAnyway, child: const Text('Study anyway')),
                const SizedBox(height: 4),
                Text('You can change the limit in Settings.', style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      );
    }
    final total = state.answers.length;
    final correct = state.correctCount;
    final missed = state.answers.where((a) => !a.grade.isCorrect).toList();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(child: ScoreRing(correct: correct, total: total)),
        const SizedBox(height: 16),
        Text(correct == total ? 'Perfect!' : 'Tapos na!',
            style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
        if (missed.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Balikan mo ang mga ito:', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final answer in missed)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(answer.card.question.prompt, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text('Answer: ${correctAnswerText(answer.card.question.toItem())}',
                        style: TextStyle(color: successColor(context), fontWeight: FontWeight.w600)),
                    if (answer.answeredText != null && answer.answeredText!.isNotEmpty)
                      Text('You: ${answer.answeredText}', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 6),
                    RichTerms(answer.card.question.explanation, style: theme.textTheme.bodyMedium),
                    Text('page ${answer.card.question.sourcePage}', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 24),
        if (onRetake != null) ...[
          OutlinedButton(onPressed: onRetake, child: const Text('Retake')),
          const SizedBox(height: 8),
        ],
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ],
    );
  }
}

/// Big circular score, e.g. 80% with "8 / 10" under it.
class ScoreRing extends StatelessWidget {
  const ScoreRing({super.key, required this.correct, required this.total});

  final int correct;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = total == 0 ? 0.0 : correct / total;
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: value,
            strokeWidth: 12,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            color: value >= 0.75
                ? successColor(context)
                : (value >= 0.5 ? warningColor(context) : theme.colorScheme.error),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${(value * 100).round()}%', style: theme.textTheme.headlineMedium),
                Text('$correct / $total', style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
