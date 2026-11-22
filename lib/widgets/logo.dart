import 'dart:math';

import 'package:material_ui/material_ui.dart';

/// The "Card buddies" logo (Figma page "4 · Logo"): two flashcards, the front
/// one smiling, on ink navy. Drawn in code so it stays sharp at any size and
/// needs no image file. Brand colours stay the same in dark mode.
class StudyBuddyLogo extends StatelessWidget {
  const StudyBuddyLogo({super.key, this.size = 96, this.withBackground = true});

  final double size;

  /// False = only the two cards (for use on the navy hero or a tile).
  final bool withBackground;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Study Buddy logo',
        image: true,
        child: CustomPaint(size: Size.square(size), painter: _LogoPainter(withBackground)),
      );
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.withBackground);

  final bool withBackground;

  static const _navy = Color(0xFF1E2A4A);
  static const _mint = Color(0xFF7FD6AE);
  static const _paper = Color(0xFFFFFDF8);

  @override
  void paint(Canvas canvas, Size size) {
    // Same coordinates as the 512 × 512 SVG in Figma.
    canvas.scale(size.width / 512);
    if (withBackground) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 512, 512), const Radius.circular(112)),
        Paint()..color = _navy,
      );
    }
    void rotated(double degrees, Offset center, void Function() draw) {
      canvas
        ..save()
        ..translate(center.dx, center.dy)
        ..rotate(degrees * pi / 180)
        ..translate(-center.dx, -center.dy);
      draw();
      canvas.restore();
    }

    rotated(10, const Offset(300, 250), () {
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(196, 112, 200, 262), const Radius.circular(30)),
        Paint()..color = _mint,
      );
    });
    rotated(-8, const Offset(225, 275), () {
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(118, 140, 212, 272), const Radius.circular(30)),
        Paint()..color = _paper,
      );
      final ink = Paint()..color = _navy;
      canvas
        ..drawCircle(const Offset(190, 252), 15, ink)
        ..drawCircle(const Offset(258, 252), 15, ink)
        ..drawPath(
          Path()
            ..moveTo(186, 302)
            ..quadraticBezierTo(224, 334, 262, 302),
          Paint()
            ..color = _navy
            ..style = PaintingStyle.stroke
            ..strokeWidth = 15
            ..strokeCap = StrokeCap.round,
        );
    });
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => oldDelegate.withBackground != withBackground;
}
