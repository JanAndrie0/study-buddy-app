import 'package:material_ui/material_ui.dart';

/// Study Buddy's look in one place (design feedback #4): a clean study-app
/// style with our own indigo accent, soft background, white rounded cards,
/// bold headings and pill buttons. Same structure in light and dark.
ThemeData buildAppTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: brightness);
  final light = brightness == Brightness.light;
  final base = ThemeData(colorScheme: scheme);
  final background = light ? const Color(0xFFF5F6FB) : scheme.surface;
  final cardColor = light ? Colors.white : scheme.surfaceContainerHigh;
  final text = base.textTheme;

  return base.copyWith(
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: scheme.onSurface),
    ),
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      // More line height for reading notes and explanations.
      bodyLarge: text.bodyLarge?.copyWith(height: 1.45),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.45),
    ),
    cardTheme: CardThemeData(
      color: cardColor,
      elevation: light ? 1 : 0,
      shadowColor: Colors.black12,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: BorderSide(color: scheme.outlineVariant, width: 1.5),
        textStyle: const TextStyle(fontSize: 16),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(shape: StadiumBorder()),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cardColor,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
    chipTheme: base.chipTheme.copyWith(shape: const StadiumBorder()),
  );
}

// Semantic colours, tuned per theme so text and icons keep ≥ 4.5:1 contrast
// on cards in both light and dark mode (ui-ux-pro-max: colour + dark mode).

bool _isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

/// "Correct" / "Know".
Color successColor(BuildContext context) =>
    _isDark(context) ? const Color(0xFF81C784) : const Color(0xFF2E7D32);

/// "Partly correct" / "Still learning".
Color warningColor(BuildContext context) =>
    _isDark(context) ? const Color(0xFFFFB74D) : const Color(0xFFB45309);

/// Text/icon colour on a filled success or warning button.
Color onSemanticColor(BuildContext context) => _isDark(context) ? Colors.black : Colors.white;

/// Animation length that respects the phone's "remove animations" setting.
Duration motion(BuildContext context, int milliseconds) =>
    MediaQuery.of(context).disableAnimations ? Duration.zero : Duration(milliseconds: milliseconds);
