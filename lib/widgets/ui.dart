import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import 'motion.dart';

/// Shared building blocks that match the Figma components (page
/// "2 · Components"). Colours always come from `context.tokens`.

/// Icon in a soft circle (onboarding, empty states, done/error screens).
class IconDisc extends StatelessWidget {
  const IconDisc({super.key, required this.icon, this.background, this.foreground, this.size = 88});

  final IconData icon;
  final Color? background;
  final Color? foreground;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background ?? t.accentSoft, shape: BoxShape.circle),
      child: Icon(icon, size: size * 0.45, color: foreground ?? t.textAccent),
    );
  }
}

/// Small non-interactive pill: question type, counts, "page 4" (Figma "Tag").
class TagPill extends StatelessWidget {
  const TagPill(this.label, {super.key, this.background, this.foreground});

  final String label;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs),
      decoration: BoxDecoration(color: background ?? t.accentSoft, borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall!.copyWith(color: foreground ?? t.textAccent)),
    );
  }
}

/// "APPEARANCE", "TODAY"… small caps label above a section.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      Text(label.toUpperCase(), style: overlineStyle(color ?? context.tokens.textSecondary));
}

/// Nothing-here-yet screen with one clear next step (Figma "Empty state").
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.body, this.action});

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: Space.xxl, vertical: Space.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconDisc(icon: icon, size: 80),
            const SizedBox(height: Space.lg),
            Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
            if (body != null) ...[
              const SizedBox(height: Space.sm),
              Text(body!, style: theme.textTheme.bodyLarge!.copyWith(color: context.tokens.textSecondary),
                  textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: Space.xxl), action!],
          ],
        ),
      ),
    );
  }
}

/// Study-mode entry on the deck page (Figma "Mode tile").
class ModeTile extends StatelessWidget {
  const ModeTile({super.key, required this.icon, required this.label, required this.caption, required this.onTap});

  final IconData icon;
  final String label;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);
    return Material(
      color: t.accentSoft,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: t.textAccent),
              const SizedBox(height: Space.sm),
              Text(label, style: theme.textTheme.titleMedium),
              Text(caption, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

/// Progress bar that fills in when it first appears or the value changes.
class AnimatedBar extends StatelessWidget {
  const AnimatedBar({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: motion(context, Motion.medium * 2),
      curve: Motion.standard,
      builder: (context, v, _) => LinearProgressIndicator(value: v, borderRadius: BorderRadius.circular(3)),
    );
  }
}

enum AnswerState { idle, selected, correct, wrong }

/// One multiple-choice option (Figma "Answer option"). Correct and wrong add a
/// ✓ / ✗ icon so the result never depends on colour alone; the colours
/// cross-fade, the icon pops and a wrong pick shakes once.
class AnswerOption extends StatefulWidget {
  const AnswerOption({super.key, required this.letter, required this.text, required this.state, this.onTap});

  final String letter;
  final String text;
  final AnswerState state;

  /// Null once the question is answered.
  final VoidCallback? onTap;

  @override
  State<AnswerOption> createState() => _AnswerOptionState();
}

class _AnswerOptionState extends State<AnswerOption> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (bg, border, width, badgeBg, badgeFg, icon, iconColor, iconLabel) = switch (widget.state) {
      AnswerState.idle => (t.surface, t.border, 1.0, t.accentSoft, t.textAccent, null, null, null),
      AnswerState.selected => (t.accentSoft, t.primary, 2.0, t.primary, t.onPrimary, null, null, null),
      AnswerState.correct => (t.successSoft, t.success, 2.0, t.success, t.onStatus, Icons.check, t.success, 'Correct answer'),
      AnswerState.wrong => (t.errorSoft, t.error, 2.0, t.error, t.onStatus, Icons.close, t.error, 'Your answer, wrong'),
    };
    final duration = motion(context, Motion.medium);
    final radius = BorderRadius.circular(Radii.md);

    return Shake(
      active: widget.state == AnswerState.wrong,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: motion(context, Motion.short),
        child: AnimatedContainer(
          duration: duration,
          curve: Motion.standard,
          decoration: BoxDecoration(color: bg, borderRadius: radius, border: Border.all(color: border, width: width)),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onTap: widget.onTap,
              onHighlightChanged: (down) => setState(() => _pressed = down),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.md),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: duration,
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: badgeBg, shape: BoxShape.circle),
                        child: Text(widget.letter,
                            style: Theme.of(context).textTheme.labelMedium!.copyWith(color: badgeFg)),
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Text(widget.text,
                            style: questionStyle(context).copyWith(fontSize: 16, color: t.textPrimary)),
                      ),
                      if (icon != null) PopIn(child: Icon(icon, color: iconColor, semanticLabel: iconLabel)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
