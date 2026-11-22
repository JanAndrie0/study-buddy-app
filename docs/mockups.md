# Study Buddy — design ("Calm Notebook")

The design lives in Figma: **[Study Buddy — Redesign](https://www.figma.com/design/uXkNEa4LcKmJWK9A748c51)**.
It replaces the Phase 4 text wireframes that used to be in this file (see Git history).

## Figma pages

| Page | What's there |
|---|---|
| 0 · Directions | The two looks I chose between: A "Kalye Warm" and **B "Calm Notebook" (picked)** |
| 1 · Foundations | Colour tokens in Light and Dark, type scale, spacing, radius, **motion spec** |
| 2 · Components | 22 icons and 16 components (Button, Chip, Tag, Progress bar, Answer option, Feedback banner, Flashcard, Deck card, Mode tile, Due card, Switch, Settings row, Text field, App bar, Tab bar, Empty state) |
| 3 · Screens | 28 screens, 360 × 800: onboarding, Home, Add lecture, Deck tabs, Flashcards, Quiz, Test, Match, Settings, plus dark mode |
| 4 · Logo | **"Card buddies"** (picked), app icon sizes, adaptive-icon foreground, lockup |

## Design → code

| Figma | Flutter |
|---|---|
| Colour variables (Light/Dark) | `AppTokens` in `lib/theme.dart`, read with `context.tokens` |
| Spacing / Radius / Motion variables | `Space`, `Radii`, `Motion` in `lib/theme.dart` |
| Text styles (Fraunces + Inter) | `TextTheme` in `buildAppTheme`; fonts bundled in `assets/fonts/` (OFL) so they work offline |
| Components | `lib/widgets/ui.dart` (IconDisc, TagPill, SectionLabel, EmptyState, ModeTile, AnimatedBar, AnswerOption) and Material components themed in `buildAppTheme` |
| Motion spec | `lib/widgets/motion.dart` (FadeSlideIn, PopIn, Shake) + `FadeSlidePageTransitionsBuilder` |
| Logo | `lib/widgets/logo.dart` (drawn in code); Android icon in `res/drawable/ic_launcher_foreground.xml`; legacy PNGs from `tool/render_launcher_icons.dart` |

## Rules kept from earlier phases

- Tap targets ≥ 48 dp; body text ≥ 16 sp; text contrast ≥ 4.5 : 1 in both modes.
- Right/wrong never relies on colour alone (✓ / ✗ icons, screen-reader labels).
- Key terms in notes and explanations are **bold**.
- Every animation goes through `motion()`, so Android's "Remove animations" turns it off.
