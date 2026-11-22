import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/generation_options.dart';
import '../../models/reviewer_item.dart';
import '../../theme.dart';
import '../../widgets/motion.dart';
import '../../widgets/ui.dart';
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

/// A card with a switch; tapping anywhere on it toggles (Figma "Add lecture · options").
class _ToggleCard extends StatelessWidget {
  const _ToggleCard({required this.title, required this.subtitle, required this.value, required this.onChanged});

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: Space.sm),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.xs),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

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
        _ToggleCard(
          title: 'Gusto mo ba ng quiz?',
          subtitle: 'Practice questions with instant checking',
          value: options.wantsQuiz,
          onChanged: controller.setQuizEnabled,
        ),
        if (options.wantsQuiz) ...[
          const SizedBox(height: Space.sm),
          Text('Anong klaseng quiz?', style: theme.textTheme.titleMedium),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
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
        const SizedBox(height: Space.xl),
        Text('Isama rin:', style: theme.textTheme.titleMedium),
        const SizedBox(height: Space.sm),
        _ToggleCard(
          title: 'Flashcards',
          subtitle: 'Term sa harap, meaning sa likod',
          value: options.flashcards,
          onChanged: controller.setFlashcards,
        ),
        _ToggleCard(
          title: 'Notes',
          subtitle: 'Key points by topic, para basahin bago mag-quiz',
          value: options.notes,
          onChanged: controller.setNotes,
        ),
      ],
    );
  }
}

/// Pick a lecture PDF → check it → generate the reviewer → open the deck.
/// Figma: "Add lecture · pick / options / generating / done / error".
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
    final t = context.tokens;
    final busy = state.step == AddStep.checking ||
        state.step == AddStep.generating ||
        state.step == AddStep.saving;

    return Scaffold(
      appBar: AppBar(title: const Text('Add lecture')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xxxl),
        children: [
          if (state.fileName == null && !busy) ...[
            _PickZone(onTap: _pickPdf),
            const SizedBox(height: Space.lg),
            FilledButton.icon(
              onPressed: _pickPdf,
              icon: const Icon(Icons.upload_file),
              label: const Text('Pick a lecture PDF'),
            ),
            const SizedBox(height: Space.lg),
            _Note(
              icon: Icons.auto_awesome_outlined,
              text: 'Internet is only needed now, while the reviewer is made. Studying works offline.',
              background: t.accentSoft,
              iconColor: t.textAccent,
            ),
          ],
          if (state.fileName != null) _FileCard(state: state, busy: busy, onPickAnother: _pickPdf),
          for (final warning in state.warnings)
            _Note(icon: Icons.warning_amber, text: warning, background: t.warningSoft, iconColor: t.warning),
          if (state.step == AddStep.ready || (state.step == AddStep.failed && state.canRetry)) ...[
            const SizedBox(height: Space.lg),
            Text('Explanation language', style: theme.textTheme.titleMedium),
            const SizedBox(height: Space.sm),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'english', label: Text('English')),
                  ButtonSegment(value: 'taglish', label: Text('Taglish')),
                  ButtonSegment(value: 'filipino', label: Text('Filipino')),
                ],
                selected: {state.options.language},
                onSelectionChanged: (s) => ref.read(addLectureProvider.notifier).setLanguage(s.first),
              ),
            ),
            const SizedBox(height: Space.lg),
            _ContentChoices(options: state.options),
            const SizedBox(height: Space.lg),
            FilledButton.icon(
              onPressed: state.options.isValid ? _generate : null,
              icon: const Icon(Icons.auto_awesome),
              label: Text(state.step == AddStep.failed ? 'Try again' : 'Gumawa ng reviewer'),
            ),
            if (!state.options.isValid)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Text(
                  'Pumili ng kahit isa: quiz, flashcards o notes.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall!.copyWith(color: t.error),
                ),
              ),
          ],
          if (busy) _Generating(step: state.step, seconds: _stopwatch.elapsed.inSeconds),
          if (state.error != null) ...[
            const SizedBox(height: Space.lg),
            _Note(icon: Icons.error_outline, text: state.error!, background: t.errorSoft, iconColor: t.error),
          ],
          if (state.step == AddStep.done) _Done(state: state),
        ],
      ),
    );
  }
}

/// Dashed drop zone shown before a file is picked; tapping it opens the picker.
class _PickZone extends StatelessWidget {
  const _PickZone({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.tokens;
    return CustomPaint(
      painter: _DashedBorderPainter(color: t.borderStrong, radius: Radii.xl),
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(Radii.xl),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.xl),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xxl, vertical: Space.xxxl),
            child: Column(
              children: [
                const IconDisc(icon: Icons.upload_file, size: 80),
                const SizedBox(height: Space.md),
                Text('Pick a lecture PDF', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: Space.sm),
                Text('Slides or notes from class. Text-based PDFs give the best questions.',
                    style: theme.textTheme.bodyLarge!.copyWith(color: t.textSecondary), textAlign: TextAlign.center),
                const SizedBox(height: Space.md),
                const TagPill('PDF · up to 15 MB'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 12) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}

/// The picked file: name, pages, and "Pick another PDF".
class _FileCard extends StatelessWidget {
  const _FileCard({required this.state, required this.busy, required this.onPickAnother});

  final AddLectureState state;
  final bool busy;
  final VoidCallback onPickAnother;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.tokens;
    final details = state.info == null
        ? 'Checking…'
        : '${state.info!.pageCount} pages'
            '${state.options.questionTypes.isEmpty ? '' : ' · about ${state.options.targetQuestions(state.info!.pageCount)} questions'}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: t.accentSoft, borderRadius: BorderRadius.circular(Radii.md)),
              child: Icon(Icons.description_outlined, color: t.textAccent),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(state.fileName!, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(details, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (state.step != AddStep.done)
              TextButton(onPressed: busy ? null : onPickAnother, child: const Text('Pick another PDF')),
          ],
        ),
      ),
    );
  }
}

/// Coloured note with an icon: tips, warnings, errors.
class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, required this.background, required this.iconColor});

  final IconData icon;
  final String text;
  final Color background;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: Space.sm),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(Radii.lg)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(color: context.tokens.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// Progress ring + the three steps, each ticked off when done.
class _Generating extends StatelessWidget {
  const _Generating({required this.step, required this.seconds});

  final AddStep step;
  final int seconds;

  static const _steps = [
    (AddStep.checking, 'Binabasa ang PDF…'),
    (AddStep.generating, 'Gumagawa ng flashcards at questions'),
    (AddStep.saving, 'Sine-save ang reviewer…'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.tokens;
    final current = _steps.indexWhere((s) => s.$1 == step);
    return Padding(
      padding: const EdgeInsets.only(top: Space.xxxl),
      child: Column(
        children: [
          SizedBox(
            width: 112,
            height: 112,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(strokeWidth: 8, backgroundColor: t.track, strokeCap: StrokeCap.round),
                Icon(Icons.auto_awesome, size: 40, color: t.textAccent),
              ],
            ),
          ),
          const SizedBox(height: Space.xl),
          Text(
            switch (step) {
              AddStep.checking => 'Binabasa ang PDF…',
              AddStep.saving => 'Sine-save ang reviewer…',
              _ => 'Ginagawa na ang reviewer mo… ${seconds}s',
            },
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          if (step == AddStep.generating) ...[
            const SizedBox(height: Space.sm),
            Text('Usually 10–60 seconds. Keep the app open.',
                style: theme.textTheme.bodyLarge!.copyWith(color: t.textSecondary), textAlign: TextAlign.center),
          ],
          const SizedBox(height: Space.xl),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Column(
                children: [
                  for (final (i, (_, label)) in _steps.indexed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: i < current
                                ? PopIn(child: Icon(Icons.check, color: t.success, semanticLabel: 'Done'))
                                : i == current
                                    ? Padding(
                                        padding: const EdgeInsets.all(3),
                                        child: CircularProgressIndicator(strokeWidth: 2.5, color: t.textAccent),
                                      )
                                    : Icon(Icons.schedule, color: t.textSecondary, size: 20),
                          ),
                          const SizedBox(width: Space.md),
                          Expanded(
                            child: Text(
                              label,
                              style: i == current
                                  ? theme.textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w700)
                                  : theme.textTheme.bodyLarge!
                                      .copyWith(color: i < current ? t.textPrimary : t.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Ready na ang reviewer!" with counts and Open reviewer.
class _Done extends StatelessWidget {
  const _Done({required this.state});

  final AddLectureState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.tokens;
    Widget stat(int n, String label) => Expanded(
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.lg),
              child: Column(children: [
                Text('$n', style: theme.textTheme.headlineMedium),
                Text(label, style: theme.textTheme.labelSmall),
              ]),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: Space.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: PopIn(child: IconDisc(icon: Icons.check, background: t.successSoft, foreground: t.success, size: 96)),
          ),
          const SizedBox(height: Space.lg),
          Text('Ready na ang reviewer!', style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
          const SizedBox(height: Space.xl),
          Row(
            children: [
              if (state.savedCount > 0) stat(state.savedCount, 'Questions'),
              if (state.savedCount > 0 && state.noteCount > 0) const SizedBox(width: Space.sm),
              if (state.noteCount > 0) stat(state.noteCount, 'Note topics'),
            ],
          ),
          if (state.droppedCount > 0) ...[
            const SizedBox(height: Space.sm),
            Text('(${state.droppedCount} broken item(s) skipped)',
                style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
          ],
          if (state.output != null) ...[
            const SizedBox(height: Space.xs),
            Text(
              state.output!.fromCache
                  ? 'From dev cache · no API call'
                  : 'Tokens: ${state.output!.inputTokens} in · '
                      '${state.output!.outputTokens + state.output!.thinkingTokens} out',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: Space.xl),
          FilledButton(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => DeckScreen(deckId: state.deckId!)),
            ),
            child: const Text('Open reviewer'),
          ),
        ],
      ),
    );
  }
}
