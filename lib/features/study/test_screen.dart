import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../add_lecture/add_lecture_screen.dart' show quizTypeLabels;
import '../../models/reviewer_item.dart';
import 'question_views.dart';
import 'study_controller.dart';
import 'study_screen.dart' show QuestionTypeTag, SegmentedProgress, SessionSummary;

/// Test (design feedback #4): a practice exam. Pick the question types and
/// how many, answer them all without feedback, then see a score ring and
/// what you missed. Practice only: nothing changes in FSRS.
class TestScreen extends ConsumerStatefulWidget {
  const TestScreen({super.key, required this.deckId, required this.availableTypes});

  final int deckId;

  /// Quiz types this deck actually has.
  final Set<QuestionType> availableTypes;

  @override
  ConsumerState<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends ConsumerState<TestScreen> {
  late final Set<QuestionType> _types = {...widget.availableTypes};
  int? _count = 10; // null = all
  bool _started = false;

  Future<void> _start() async {
    setState(() => _started = true);
    await ref.read(studyProvider.notifier).start(
          deckId: widget.deckId,
          mode: StudyMode.test,
          types: _types.map((t) => t.jsonName).toSet(),
          limit: _count,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Watch the session from the start (bug B2): the provider is auto-disposed
    // while nobody watches it, so watching only after "Start" let start()
    // fill a session that was thrown away, leaving the screen on "loading".
    final state = ref.watch(studyProvider);
    if (!_started) {
      return Scaffold(
        appBar: AppBar(title: const Text('Test')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Practice exam', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('No hints until the end. Your review schedule is not affected.',
                style: theme.textTheme.bodyLarge!.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            Text('Question types', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final type in widget.availableTypes)
                  FilterChip(
                    label: Text(quizTypeLabels[type] ?? type.jsonName),
                    selected: _types.contains(type),
                    onSelected: (on) => setState(() => on ? _types.add(type) : _types.remove(type)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text('How many questions?', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<int?>(
              segments: const [
                ButtonSegment(value: 5, label: Text('5')),
                ButtonSegment(value: 10, label: Text('10')),
                ButtonSegment(value: 20, label: Text('20')),
                ButtonSegment(value: null, label: Text('All')),
              ],
              selected: {_count},
              onSelectionChanged: (s) => setState(() => _count = s.first),
            ),
            const SizedBox(height: 32),
            FilledButton(onPressed: _types.isEmpty ? null : _start, child: const Text('Start test')),
          ],
        ),
      );
    }

    final controller = ref.read(studyProvider.notifier);
    final answering = state.phase == StudyPhase.answering;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test'),
        actions: [
          if (answering)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Text('${state.index + 1} / ${state.queue.length}')),
            ),
        ],
        bottom: answering ? SegmentedProgress(done: state.answers.length, total: state.queue.length) : null,
      ),
      body: switch (state.phase) {
        StudyPhase.loading => const Center(child: CircularProgressIndicator()),
        StudyPhase.done => SessionSummary(
            state: state,
            onRetake: () => setState(() => _started = false),
            emptyMessage: 'No questions of those types in this reviewer.\nTap Retake to pick other types.',
          ),
        _ => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              QuestionTypeTag(item: state.item!),
              const SizedBox(height: 12),
              QuestionView(
                key: ValueKey('${state.current!.question.id}-${state.index}'),
                item: state.item!,
                locked: false,
                onGraded: (grade, text) => controller.submit(grade, answeredText: text),
                onRate: (_) {},
              ),
            ],
          ),
      },
    );
  }
}
