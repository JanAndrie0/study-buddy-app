import 'package:material_ui/material_ui.dart';

/// Splits text on `**bold**` markers (design feedback #1).
/// Returns (text, isBold) pieces; an unmatched `**` is kept as plain text.
List<(String, bool)> splitBoldTerms(String text) {
  final pieces = <(String, bool)>[];
  var rest = text;
  while (true) {
    final start = rest.indexOf('**');
    final end = start == -1 ? -1 : rest.indexOf('**', start + 2);
    if (start == -1 || end == -1) {
      if (rest.isNotEmpty) pieces.add((rest, false));
      return pieces;
    }
    if (start > 0) pieces.add((rest.substring(0, start), false));
    final bold = rest.substring(start + 2, end);
    if (bold.isNotEmpty) pieces.add((bold, true));
    rest = rest.substring(end + 2);
  }
}

/// Removes the `**` markers, e.g. for search or plain-text checks.
String stripBoldMarkers(String text) => splitBoldTerms(text).map((p) => p.$1).join();

/// Shows text with the important terms in bold.
class RichTerms extends StatelessWidget {
  const RichTerms(this.text, {super.key, this.style, this.textAlign});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (final (piece, bold) in splitBoldTerms(text))
            TextSpan(text: piece, style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null),
        ],
      ),
      textAlign: textAlign,
    );
  }
}
