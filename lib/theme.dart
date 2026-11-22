import 'package:material_ui/material_ui.dart';

/// "Calm Notebook" design tokens, the same names and values as the Figma
/// variables (Study Buddy — Redesign, page "1 · Foundations"). Colours come in
/// Light/Dark pairs; widgets read them with `context.tokens`.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.bgApp,
    required this.surface,
    required this.surfaceAlt,
    required this.accentSoft,
    required this.primary,
    required this.hero,
    required this.heroButton,
    required this.track,
    required this.success,
    required this.successSoft,
    required this.error,
    required this.errorSoft,
    required this.warning,
    required this.warningSoft,
    required this.textPrimary,
    required this.textSecondary,
    required this.textAccent,
    required this.onPrimary,
    required this.onHero,
    required this.heroAccent,
    required this.onHeroButton,
    required this.onStatus,
    required this.border,
    required this.borderStrong,
  });

  final Color bgApp, surface, surfaceAlt, accentSoft, primary, hero, heroButton, track;
  final Color success, successSoft, error, errorSoft, warning, warningSoft;
  final Color textPrimary, textSecondary, textAccent, onPrimary, onHero, heroAccent, onHeroButton, onStatus;
  final Color border, borderStrong;

  static const light = AppTokens(
    bgApp: Color(0xFFF5F1E8), // paper/100
    surface: Color(0xFFFFFDF8), // paper/50
    surfaceAlt: Color(0xFFEAE4D6),
    accentSoft: Color(0xFFE4EFE8), // mint/100
    primary: Color(0xFF1E2A4A), // ink navy
    hero: Color(0xFF1E2A4A),
    heroButton: Color(0xFF7FD6AE), // mint
    track: Color(0xFFE0D8C6),
    success: Color(0xFF1F7A55),
    successSoft: Color(0xFFDDF2E7),
    error: Color(0xFFB4232C),
    errorSoft: Color(0xFFF8E1E0),
    warning: Color(0xFFA15C07),
    warningSoft: Color(0xFFFBEBD0),
    textPrimary: Color(0xFF1B1F2A),
    textSecondary: Color(0xFF5E6472),
    textAccent: Color(0xFF1E2A4A),
    onPrimary: Color(0xFFFFFFFF),
    onHero: Color(0xFFFFFDF8),
    heroAccent: Color(0xFF7FD6AE),
    onHeroButton: Color(0xFF1E2A4A),
    onStatus: Color(0xFFFFFFFF),
    border: Color(0xFFE0D8C6),
    borderStrong: Color(0xFF5E6472),
  );

  static const dark = AppTokens(
    bgApp: Color(0xFF11151F),
    surface: Color(0xFF171C28),
    surfaceAlt: Color(0xFF20283A),
    accentSoft: Color(0xFF173528),
    primary: Color(0xFF7FD6AE), // mint buttons with navy text in dark mode
    hero: Color(0xFF20283A),
    heroButton: Color(0xFF7FD6AE),
    track: Color(0xFF2E3850),
    success: Color(0xFF6FCF9F),
    successSoft: Color(0xFF173528),
    error: Color(0xFFF2A3A3),
    errorSoft: Color(0xFF3A1A1C),
    warning: Color(0xFFF5C26B),
    warningSoft: Color(0xFF3A2A10),
    textPrimary: Color(0xFFE8E4DA),
    textSecondary: Color(0xFF9AA3B6),
    textAccent: Color(0xFF7FD6AE),
    onPrimary: Color(0xFF141C33),
    onHero: Color(0xFFE8E4DA),
    heroAccent: Color(0xFF7FD6AE),
    onHeroButton: Color(0xFF141C33),
    onStatus: Color(0xFF141C33),
    border: Color(0xFF2E3850),
    borderStrong: Color(0xFF9AA3B6),
  );

  @override
  AppTokens copyWith() => this;

  // Light ↔ dark switches instantly; there is no in-between theme to animate.
  @override
  AppTokens lerp(AppTokens? other, double t) => t < 0.5 || other == null ? this : other;
}

extension AppTokensContext on BuildContext {
  /// The current tokens. Falls back to the defaults when a widget is shown
  /// without the app theme (e.g. in widget tests).
  AppTokens get tokens {
    final theme = Theme.of(this);
    return theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark ? AppTokens.dark : AppTokens.light);
  }
}

/// Spacing scale (Figma "Spacing" variables).
abstract final class Space {
  static const xs = 4.0, sm = 8.0, md = 12.0, lg = 16.0, xl = 20.0, xxl = 24.0, xxxl = 32.0;
}

/// Corner radius scale (Figma "Radius" variables).
abstract final class Radii {
  static const sm = 8.0, md = 12.0, lg = 16.0, xl = 24.0;
}

/// Motion tokens (Figma "Motion" variables + spec): quick, soft, never bouncy for long.
abstract final class Motion {
  static const short = 150, medium = 250, long = 400, celebrate = 800, stagger = 40;
  static const standard = Curves.easeOutCubic;
}

/// Animation length that respects the phone's "remove animations" setting.
Duration motion(BuildContext context, int milliseconds) =>
    MediaQuery.of(context).disableAnimations ? Duration.zero : Duration(milliseconds: milliseconds);

const _serif = 'Fraunces'; // headings (bundled in assets/fonts, works offline)
const _sans = 'Inter'; // everything else

/// Text for quiz questions (Figma "Body/Large").
TextStyle questionStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 17, fontWeight: FontWeight.w500, height: 1.4);

/// Small caps label above a section (Figma "Overline").
TextStyle overlineStyle(Color color) =>
    TextStyle(fontFamily: _sans, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: color);

ThemeData buildAppTheme(Brightness brightness) {
  final t = brightness == Brightness.light ? AppTokens.light : AppTokens.dark;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: t.primary,
    onPrimary: t.onPrimary,
    primaryContainer: t.accentSoft,
    onPrimaryContainer: t.textAccent,
    secondary: t.heroButton,
    onSecondary: t.onHeroButton,
    secondaryContainer: t.accentSoft,
    onSecondaryContainer: t.textPrimary,
    tertiary: t.warning,
    onTertiary: t.onStatus,
    tertiaryContainer: t.warningSoft,
    onTertiaryContainer: t.textPrimary,
    error: t.error,
    onError: t.onStatus,
    errorContainer: t.errorSoft,
    onErrorContainer: t.textPrimary,
    surface: t.bgApp,
    onSurface: t.textPrimary,
    onSurfaceVariant: t.textSecondary,
    surfaceContainerLowest: t.surface,
    surfaceContainerLow: t.surface,
    surfaceContainer: t.surface,
    surfaceContainerHigh: t.surfaceAlt,
    surfaceContainerHighest: t.track,
    outline: t.borderStrong,
    outlineVariant: t.border,
    inverseSurface: t.textPrimary,
    onInverseSurface: t.bgApp,
    inversePrimary: t.heroButton,
    shadow: Colors.black,
  );

  TextStyle serif(double size, double height) =>
      TextStyle(fontFamily: _serif, fontSize: size, height: height, fontWeight: FontWeight.w600, color: t.textPrimary);
  TextStyle sans(double size, FontWeight weight, double height, [Color? color]) =>
      TextStyle(fontFamily: _sans, fontSize: size, fontWeight: weight, height: height, color: color ?? t.textPrimary);

  // Figma text styles → Material roles.
  final text = TextTheme(
    displaySmall: serif(34, 1.2), // Display/Large
    headlineMedium: serif(28, 1.25), // Heading/H1
    headlineSmall: serif(22, 1.3), // Heading/H2
    titleLarge: serif(18, 1.35), // Heading/H3
    titleMedium: sans(15, FontWeight.w600, 1.3), // Label/Large
    titleSmall: sans(13, FontWeight.w600, 1.3), // Label/Default
    bodyLarge: sans(16, FontWeight.w400, 1.45), // Body/Default
    bodyMedium: sans(16, FontWeight.w400, 1.45),
    bodySmall: sans(13, FontWeight.w400, 1.45, t.textSecondary), // Body/Small
    labelLarge: sans(15, FontWeight.w600, 1.3),
    labelMedium: sans(13, FontWeight.w600, 1.3),
    labelSmall: sans(12, FontWeight.w600, 1.3, t.textSecondary),
  );

  final rMd = BorderRadius.circular(Radii.md);
  WidgetStateProperty<T> states<T>(T selected, T normal) =>
      WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? selected : normal);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: _sans,
    textTheme: text,
    scaffoldBackgroundColor: t.bgApp,
    extensions: [t],
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeSlidePageTransitionsBuilder(),
      TargetPlatform.iOS: FadeSlidePageTransitionsBuilder(),
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: t.bgApp,
      foregroundColor: t.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 4,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: t.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: t.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.primary,
        foregroundColor: t.onPrimary,
        disabledBackgroundColor: t.track,
        disabledForegroundColor: t.textSecondary,
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(horizontal: Space.xl),
        shape: RoundedRectangleBorder(borderRadius: rMd),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.textPrimary,
        backgroundColor: t.surface,
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(horizontal: Space.xl),
        shape: RoundedRectangleBorder(borderRadius: rMd),
        side: BorderSide(color: t.border),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.textAccent,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: rMd),
        textStyle: text.labelLarge,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: t.primary,
      foregroundColor: t.onPrimary,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: rMd),
      extendedTextStyle: text.labelLarge,
    ),
    chipTheme: ChipThemeData(
      color: states(t.primary, t.surface),
      side: WidgetStateBorderSide.resolveWith(
        (s) => s.contains(WidgetState.selected) ? BorderSide(color: t.primary) : BorderSide(color: t.border),
      ),
      shape: const StadiumBorder(),
      checkmarkColor: t.onPrimary,
      labelStyle: text.labelMedium!.copyWith(
        color: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.selected) ? t.onPrimary : t.textPrimary),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.sm),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: states(t.primary, t.surface),
        foregroundColor: states(t.onPrimary, t.textPrimary),
        iconColor: states(t.onPrimary, t.textPrimary),
        side: WidgetStatePropertyAll(BorderSide(color: t.borderStrong)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: rMd)),
        textStyle: WidgetStatePropertyAll(text.labelMedium),
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: states(t.onPrimary, t.borderStrong),
      trackColor: states(t.primary, t.track),
      trackOutlineColor: states(t.primary, t.borderStrong),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: states(t.primary, Colors.transparent),
      checkColor: WidgetStatePropertyAll(t.onPrimary),
      side: BorderSide(color: t.borderStrong, width: 2),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: 14),
      labelStyle: text.bodyLarge!.copyWith(color: t.textSecondary),
      floatingLabelStyle: text.labelMedium!.copyWith(color: t.textAccent),
      border: OutlineInputBorder(borderRadius: rMd, borderSide: BorderSide(color: t.border)),
      enabledBorder: OutlineInputBorder(borderRadius: rMd, borderSide: BorderSide(color: t.border)),
      disabledBorder: OutlineInputBorder(borderRadius: rMd, borderSide: BorderSide(color: t.border)),
      focusedBorder: OutlineInputBorder(borderRadius: rMd, borderSide: BorderSide(color: t.primary, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: rMd, borderSide: BorderSide(color: t.error, width: 2)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: t.textPrimary,
      unselectedLabelColor: t.textSecondary,
      labelStyle: text.titleMedium,
      unselectedLabelStyle: text.titleMedium,
      indicatorColor: t.primary,
      indicatorSize: TabBarIndicatorSize.label,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: t.primary, width: 3),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
      ),
      dividerColor: t.border,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.primary,
      linearTrackColor: t.track,
      circularTrackColor: t.track,
      linearMinHeight: 6,
    ),
    dividerTheme: DividerThemeData(color: t.border, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: t.textSecondary,
      titleTextStyle: text.bodyLarge,
      subtitleTextStyle: text.bodySmall,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl)),
      titleTextStyle: text.headlineSmall,
      contentTextStyle: text.bodyLarge,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: t.textPrimary,
      contentTextStyle: text.bodyMedium!.copyWith(color: t.bgApp),
      shape: RoundedRectangleBorder(borderRadius: rMd),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      iconColor: t.textSecondary,
      collapsedIconColor: t.textSecondary,
      shape: const Border(),
      collapsedShape: const Border(),
    ),
  );
}

/// Screen change from the motion spec: fade in while sliding 24 px in from
/// the right; the old screen dims a little underneath. Instant when
/// animations are turned off.
class FadeSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeSlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.of(context).disableAnimations) return child;
    final enter = CurvedAnimation(parent: animation, curve: Motion.standard, reverseCurve: Curves.easeInCubic);
    final leave = CurvedAnimation(parent: secondaryAnimation, curve: Motion.standard);
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.6).animate(leave),
      child: FadeTransition(
        opacity: enter,
        child: SlideTransition(
          position: Tween(begin: const Offset(24 / 360, 0), end: Offset.zero).animate(enter),
          child: child,
        ),
      ),
    );
  }
}
