import 'dart:math';

import 'package:fsrs/fsrs.dart' show Rating;
import 'package:material_ui/material_ui.dart';

import '../../models/reviewer_item.dart';
import '../../services/grader.dart';
import '../../theme.dart';
import '../../widgets/rich_terms.dart';
import '../../widgets/ui.dart';

/// Called when the student checks an answer.
typedef OnGraded = void Function(GradeResult grade, String? answeredText);

/// Picks the right answer widget for the question type.
class QuestionView extends StatelessWidget {
  const QuestionView({
    super.key,
    required this.item,
    required this.locked,
    required this.onGraded,
    required this.onRate,
  });

  final ReviewerItem item;

  /// True after answering, so the student can't change the answer.
  final bool locked;
  final OnGraded onGraded;
  final void Function(Rating rating) onRate;

  @override
  Widget build(BuildContext context) => switch (item.type) {
        QuestionType.flashcard => FlashcardView(item: item, onRate: onRate),
        QuestionType.multipleChoice => MultipleChoiceView(item: item, locked: locked, onGraded: onGraded),
        QuestionType.identification => IdentificationView(item: item, locked: locked, onGraded: onGraded),
        QuestionType.enumeration => EnumerationView(item: item, locked: locked, onGraded: onGraded),
        QuestionType.trueFalse => TrueFalseView(item: item, locked: locked, onGraded: onGraded),
        QuestionType.modifiedTrueFalse => ModifiedTrueFalseView(item: item, locked: locked, onGraded: onGraded),
      };
}

TextStyle? _promptStyle(BuildContext context) => questionStyle(context);

/// Flashcard: tap to flip, then rate yourself (Again / Hard / Good / Easy).
class FlashcardView extends StatefulWidget {
  const FlashcardView({super.key, required this.item, required this.onRate});
  final ReviewerItem item;
  final void Function(Rating rating) onRate;

  @override
  State<FlashcardView> createState() => _FlashcardViewState();
}

class _FlashcardViewState extends State<FlashcardView> {
  bool _flipped = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () => setState(() => _flipped = !_flipped),
          child: Card(
            color: _flipped ? theme.colorScheme.secondaryContainer : null,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  RichTerms(_flipped ? widget.item.answer : widget.item.prompt,
                      style: _promptStyle(context), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  RichTerms(_flipped ? widget.item.explanation : '(Tap to flip)',
                      style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_flipped) ...[
          Text('Gaano mo naalala?', style: theme.textTheme.titleSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              for (final (rating, label) in [
                (Rating.again, 'Again'),
                (Rating.hard, 'Hard'),
                (Rating.good, 'Good'),
                (Rating.easy, 'Easy'),
              ])
                FilledButton.tonal(onPressed: () => widget.onRate(rating), child: Text(label)),
            ],
          ),
        ] else
          FilledButton(onPressed: () => setState(() => _flipped = true), child: const Text('Show answer')),
      ],
    );
  }
}

/// Multiple choice: tap one of 4 options (shuffled once per question).
class MultipleChoiceView extends StatefulWidget {
  const MultipleChoiceView({super.key, required this.item, required this.locked, required this.onGraded});
  final ReviewerItem item;
  final bool locked;
  final OnGraded onGraded;

  @override
  State<MultipleChoiceView> createState() => _MultipleChoiceViewState();
}

class _MultipleChoiceViewState extends State<MultipleChoiceView> {
  late final List<String> _choices = [...widget.item.choices]..shuffle(Random());
  String? _picked;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.item.prompt, style: _promptStyle(context)),
        const SizedBox(height: 16),
        // Bug B4 still holds: options use the main text colour, also after
        // answering. Not colour alone: ✓ marks the right option, ✗ your pick.
        for (final (i, choice) in _choices.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AnswerOption(
              letter: String.fromCharCode(65 + i), // A, B, C, D
              text: choice,
              state: !widget.locked
                  ? (choice == _picked ? AnswerState.selected : AnswerState.idle)
                  : choice == widget.item.answer
                      ? AnswerState.correct
                      : choice == _picked
                          ? AnswerState.wrong
                          : AnswerState.idle,
              onTap: widget.locked
                  ? null
                  : () {
                      setState(() => _picked = choice);
                      widget.onGraded(gradeMultipleChoice(choice, widget.item), choice);
                    },
            ),
          ),
      ],
    );
  }
}

/// Identification: type the term.
class IdentificationView extends StatefulWidget {
  const IdentificationView({super.key, required this.item, required this.locked, required this.onGraded});
  final ReviewerItem item;
  final bool locked;
  final OnGraded onGraded;

  @override
  State<IdentificationView> createState() => _IdentificationViewState();
}

class _IdentificationViewState extends State<IdentificationView> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _check() {
    if (_controller.text.trim().isEmpty) return;
    widget.onGraded(gradeIdentification(_controller.text, widget.item), _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.item.prompt, style: _promptStyle(context)),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          enabled: !widget.locked,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _check(),
          decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Sagot'),
        ),
        const SizedBox(height: 12),
        if (!widget.locked) FilledButton(onPressed: _check, child: const Text('Check')),
      ],
    );
  }
}

/// Enumeration: one box per expected item, any order.
class EnumerationView extends StatefulWidget {
  const EnumerationView({super.key, required this.item, required this.locked, required this.onGraded});
  final ReviewerItem item;
  final bool locked;
  final OnGraded onGraded;

  @override
  State<EnumerationView> createState() => _EnumerationViewState();
}

class _EnumerationViewState extends State<EnumerationView> {
  late final List<TextEditingController> _controllers =
      List.generate(widget.item.items.length, (_) => TextEditingController());

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _check() {
    final inputs = _controllers.map((c) => c.text).where((t) => t.trim().isNotEmpty).toList();
    widget.onGraded(gradeEnumeration(inputs, widget.item), inputs.join('; '));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.item.prompt, style: _promptStyle(context)),
        const SizedBox(height: 16),
        for (var i = 0; i < _controllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: _controllers[i],
              enabled: !widget.locked,
              textInputAction: i == _controllers.length - 1 ? TextInputAction.done : TextInputAction.next,
              decoration: InputDecoration(border: const OutlineInputBorder(), labelText: 'Item ${i + 1}'),
            ),
          ),
        if (!widget.locked) FilledButton(onPressed: _check, child: const Text('Check')),
      ],
    );
  }
}

/// True or false: two big buttons.
class TrueFalseView extends StatelessWidget {
  const TrueFalseView({super.key, required this.item, required this.locked, required this.onGraded});
  final ReviewerItem item;
  final bool locked;
  final OnGraded onGraded;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(item.prompt, style: _promptStyle(context)),
        const SizedBox(height: 16),
        _TrueFalseButtons(
          enabled: !locked,
          onPick: (pickedTrue) => onGraded(gradeTrueFalse(pickedTrue, item), pickedTrue ? 'True' : 'False'),
        ),
      ],
    );
  }
}

class _TrueFalseButtons extends StatelessWidget {
  const _TrueFalseButtons({required this.enabled, required this.onPick, this.selected});
  final bool enabled;
  final void Function(bool pickedTrue) onPick;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    Widget button(bool value, String label) => Expanded(
          child: (selected == value ? FilledButton.new : FilledButton.tonal)(
            onPressed: enabled ? () => onPick(value) : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(label),
          ),
        );
    return Row(children: [button(true, 'True'), const SizedBox(width: 12), button(false, 'False')]);
  }
}

/// Builds the statement with [underlined] underlined (case-insensitive match).
TextSpan underlinedStatement(String statement, String underlined, TextStyle? style) {
  final start = underlined.isEmpty ? -1 : statement.toLowerCase().indexOf(underlined.toLowerCase());
  if (start == -1) return TextSpan(text: statement, style: style);
  final end = start + underlined.length;
  return TextSpan(style: style, children: [
    TextSpan(text: statement.substring(0, start)),
    TextSpan(
      text: statement.substring(start, end),
      style: const TextStyle(decoration: TextDecoration.underline, decorationThickness: 2, fontWeight: FontWeight.bold),
    ),
    TextSpan(text: statement.substring(end)),
  ]);
}

/// Modified true or false (ADR-007): judge the underlined word; if False,
/// type the word that makes the statement true.
class ModifiedTrueFalseView extends StatefulWidget {
  const ModifiedTrueFalseView({super.key, required this.item, required this.locked, required this.onGraded});
  final ReviewerItem item;
  final bool locked;
  final OnGraded onGraded;

  @override
  State<ModifiedTrueFalseView> createState() => _ModifiedTrueFalseViewState();
}

class _ModifiedTrueFalseViewState extends State<ModifiedTrueFalseView> {
  final _controller = TextEditingController();
  bool? _pickedTrue;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _pick(bool pickedTrue) {
    setState(() => _pickedTrue = pickedTrue);
    if (pickedTrue) {
      widget.onGraded(gradeModifiedTrueFalse(widget.item, pickedTrue: true), 'True');
    }
  }

  void _checkCorrection() {
    widget.onGraded(
      gradeModifiedTrueFalse(widget.item, pickedTrue: false, correctionInput: _controller.text),
      'False: ${_controller.text}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Tama ba ang naka-underline?', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Text.rich(underlinedStatement(widget.item.prompt, widget.item.underlinedWord ?? '', _promptStyle(context))),
        const SizedBox(height: 16),
        _TrueFalseButtons(enabled: !widget.locked, onPick: _pick, selected: _pickedTrue),
        if (_pickedTrue == false) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            enabled: !widget.locked,
            autofocus: true,
            onSubmitted: (_) => _checkCorrection(),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'Ano ang tamang kapalit ng "${widget.item.underlinedWord}"?',
            ),
          ),
          const SizedBox(height: 12),
          if (!widget.locked) FilledButton(onPressed: _checkCorrection, child: const Text('Check')),
        ],
      ],
    );
  }
}
