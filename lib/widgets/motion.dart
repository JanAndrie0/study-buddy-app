import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// List-item entrance from the motion spec: fades up 8 px, one item after
/// another (40 ms apart). Only plays on first build; instant when the phone's
/// "remove animations" setting is on.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.index, required this.child});

  /// Position in the list; later items start a little later (capped at 8).
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delay = Motion.stagger * index.clamp(0, 8);
    final total = motion(context, Motion.medium + delay);
    if (total == Duration.zero) return child;
    final start = delay / (Motion.medium + delay); // our slot, as a fraction
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      child: child,
      builder: (context, value, child) {
        final t = Motion.standard.transform(((value - start) / (1 - start)).clamp(0.0, 1.0));
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
        );
      },
    );
  }
}

/// The ✓ / ✗ "pop": grows from 60 % to full size with a small overshoot.
class PopIn extends StatelessWidget {
  const PopIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: motion(context, Motion.medium),
      curve: Curves.easeOutBack,
      child: child,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
    );
  }
}

/// One short side-to-side shake (6 px) when [active] turns true: a wrong
/// answer or a wrong Match pair.
class Shake extends StatefulWidget {
  const Shake({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.forward();
  }

  @override
  void didUpdateWidget(Shake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final v = _controller.value;
        return Transform.translate(offset: Offset(sin(v * pi * 4) * 6 * (1 - v), 0), child: child);
      },
    );
  }
}
