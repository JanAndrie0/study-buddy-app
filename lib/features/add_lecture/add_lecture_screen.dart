import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/generation_options.dart';
import '../../models/reviewer_item.dart';
import '../decks/deck_screen.dart';
import 'add_lecture_controller.dart';

/// Labels for the quiz-type chips.
const quizTypeLabels = {
  QuestionType.multipleChoice: 'Multiple choice',
  QuestionType.identification: 'Identification',
  QuestionType.modifiedTrueFalse: 'Modified true or false',
  QuestionType.enumeration: 'Enumeration',
  QuestionType.trueFalse: 'True or false',
};

/// "Gusto mo ba ng quiz?" + quiz types, then Flashcards / Notes (ADR-008).
class _ContentChoices extends ConsumerWidget {
  const _ContentChoices({required this.options});

  final GenerationOptions options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(addLectureProvider.notifier);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Gusto mo ba ng quiz?'),
          subtitle: const Text('Practice questions with instant checking'),
          value: options.wantsQuiz,
          onChanged: controller.setQuizEnabled,
        ),
        if (options.wantsQuiz) ...[
          Text('Anong klaseng quiz?', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final type in GenerationOptions.quizChoices)
                FilterChip(
                  label: Text(quizTypeLabels[type]!),
                  selected: options.quizTypes.contains(type),
                  onSelected: (_) => controller.toggleQuizType(type),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Text('Isama rin:', style: theme.textTheme.titleSmall),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Flashcards'),
          subtitle: const Text('Term sa harap, meaning sa likod'),
          value: options.flashcards,
          onChanged: (v) => controller.setFlashcards(v ?? false),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Notes'),
          subtitle: const Text('Key points by topic, para basahin bago mag-quiz'),
          value: options.notes,
          onChanged: (v) => controller.setNotes(v ?? false),
        ),
      ],
    );
  }
}

/// Pick a lecture PDF → check it → generate the reviewer → open the deck.
class AddLectureScreen extends ConsumerStatefulWidget {
  const AddLectureScreen({super.key});

  @override
  ConsumerState<AddLectureScreen> createState() => _AddLectureScreenState();
}

class _AddLectureScreenState extends ConsumerState<AddLectureScreen> {
  final _stopwatch = Stopwatch();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Start fresh every time the screen opens.
    Future.microtask(() => ref.read(addLectureProvider.notifier).reset());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf']);
    if (file == null) return; // cancelled
    final bytes = await file.xFile.readAsBytes();
    await ref.read(addLectureProvider.notifier).loadFile(file.name, bytes);
  }

  Future<void> _generate() async {
    _stopwatch
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    await ref.read(addLectureProvider.notifier).generate();
    _ticker?.cancel();
    _stopwatch.stop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(addLectureProvider);
    final theme = Theme.of(context);
    final busy = state.step == AddStep.checking ||
        state.step == AddStep.generating ||
        state.step == AddStep.saving;

    return Scaffold(
      appBar: AppBar(title: const Text('Add lecture')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.tonalIcon(
            onPressed: busy ? null : _pickPdf,
            icon: const Icon(Icons.picture_as_pdf),
            label: Text(state.fileName == null ? 'Pick a lecture PDF' : 'Pick another PDF'),
          ),
          if (state.fileName != null) ...[
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.description),
                title: Text(state.fileName!),
                subtitle: state.info == null
                    ? const Text('Checking…')
                    : Text('${state.info!.pageCount} pages'
                        '${state.options.questionTypes.isEmpty ? '' : ' · about ${state.options.targetQuestions(state.info!.pageCount)} questions'}'),
              ),
            ),
          ],
          for (final warning in state.warnings)
            Card(
              color: theme.colorScheme.tertiaryContainer,
              child: ListTile(
                leading: const Icon(Icons.warning_amber),
                title: Text(warning, style: theme.textTheme.bodyMedium),
              ),
            ),
          if (state.step == AddStep.ready || (state.step == AddStep.failed && state.canRetry)) ...[
            const SizedBox(height: 16),
            Text('Explanation language', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'english', label: Text('English')),
                ButtonSegment(value: 'taglish', label: Text('Taglish')),
                ButtonSegment(value: 'filipino', label: Text('Filipino')),
              ],
              selected: {state.options.language},
              onSelectionChanged: (s) => ref.read(addLectureProvider.notifier).setLanguage(s.first),
            ),
            const SizedBox(height: 8),
            _ContentChoices(options: state.options),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: state.options.isValid ? _generate : null,
              icon: const Icon(Icons.auto_awesome),
              label: Text(state.step == AddStep.failed ? 'Try again' : 'Gumawa ng reviewer'),
            ),
            if (!state.options.isValid)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Pumili ng kahit isa: quiz, flashcards o notes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ],
          if (busy) ...[
            const SizedBox(height: 32),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 12),
            Center(
              child: Text(switch (state.step) {
                AddStep.checking => 'Binabasa ang PDF…',
                AddStep.saving => 'Sine-save ang reviewer…',
                _ => 'Ginagawa na ang reviewer mo… ${_stopwatch.elapsed.inSeconds}s',
              }),
            ),
            if (state.step == AddStep.generating)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Center(child: Text('Usually 10–60 seconds. Keep the app open.')),
              ),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 16),
            Card(
              color: theme.colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(state.error!),
              ),
            ),
          ],
          if (state.step == AddStep.done) ...[
            const SizedBox(height: 24),
            Icon(Icons.check_circle, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '${[
                  if (state.savedCount > 0) '${state.savedCount} questions',
                  if (state.noteCount > 0) '${state.noteCount} note topics',
                ].join(' · ')} ready!',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
            ),
            if (state.droppedCount > 0)
              Center(child: Text('(${state.droppedCount} broken item(s) skipped)')),
            if (state.output != null)
              Center(
                child: Text(
                  state.output!.fromCache
                      ? 'From dev cache · no API call'
                      : 'Tokens: ${state.output!.inputTokens} in · '
                          '${state.output!.outputTokens + state.output!.thinkingTokens} out',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => DeckScreen(deckId: state.deckId!)),
              ),
              child: const Text('Open reviewer'),
            ),
          ],
        ],
      ),
    );
  }
}
