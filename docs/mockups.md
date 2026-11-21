# Study Buddy — Phase 4 mockups

Text wireframes drawn before building the study screens (process.md, Phase 4).
Material 3, indigo seed colour, big tap targets (≥ 48 dp), dark mode from day one.
Everything on these screens works **offline**.

## Home
```
┌─────────────────────────────────┐
│ Study Buddy                  ⚙  │  ← Settings
├─────────────────────────────────┤
│ ┌─────────────────────────────┐ │
│ │ 📅 12 due today             │ │  ← tap: study all due cards
│ │        [ Mag-review na ]    │ │
│ └─────────────────────────────┘ │
│ ┌─────────────────────────────┐ │
│ │ 🗂 Software Quality Econ.  › │ │
│ │ CIT4303 · 14 questions ·    │ │
│ │ notes                       │ │
│ └─────────────────────────────┘ │
│                  [ + Add lecture ] │
└─────────────────────────────────┘
```

## Deck
```
┌─────────────────────────────────┐
│ ← Reviewer                   🗑 │
│ [ Notes ] [ Questions ]         │
├─────────────────────────────────┤
│ Cost of Quality        page 2   │
│ • Kabuuang gastos para …        │
│ • Apat na categories: …         │
│                                 │
│        [ ▶ Study ]              │  ← floating button
└─────────────────────────────────┘
```

## Study (one question per screen)
Top: progress bar + "3 / 12". Bottom: the answer area for the type.
```
Multiple choice           Identification            Modified true or false
┌──────────────────┐      ┌──────────────────┐      ┌──────────────────┐
│ Which cost cat…? │      │ Costs from defe… │      │ Training is an   │
│ [ Prevention   ] │      │ ┌──────────────┐ │      │ example of       │
│ [ Appraisal    ] │      │ │ type answer  │ │      │ _appraisal_ cost.│
│ [ Internal f.  ] │      │ └──────────────┘ │      │ [ True ][ False ]│
│ [ External f.  ] │      │      [ Check ]   │      │ False → ┌──────┐ │
└──────────────────┘      └──────────────────┘      │  correct│word  │ │
                                                    │         └──────┘ │
Enumeration (one box per item)   True or false      │      [ Check ]   │
┌──────────────────┐      ┌──────────────────┐      └──────────────────┘
│ Enumerate the 4… │      │ Fixing a defect… │
│ 1 [__________]   │      │ [ True ][ False ]│      Flashcard
│ 2 [__________]   │      └──────────────────┘      ┌──────────────────┐
│ 3 [__________]   │                                │  Cost of Quality │
│ 4 [__________]   │                                │  (tap to flip)   │
│      [ Check ]   │                                │ [Again][Hard]    │
└──────────────────┘                                │ [Good] [Easy]    │
                                                    └──────────────────┘
```

## Feedback + explanation sheet (after Check)
```
┌─────────────────────────────────┐
│ ✅ Tama!   (or ❌ Mali — sagot: │
│             Appraisal cost)     │
│ ─────────────────────────────── │
│ Kasi ang testing ay appraisal … │  ← explanation in chosen language
│ 📄 Source: page 3               │
│                    [ Next → ]   │
└─────────────────────────────────┘
```
Enumeration shows "3/4 tama" and the missed items. Modified T/F shows the
underlined word and its correction.

## Session summary
```
┌─────────────────────────────────┐
│ Tapos na! 🎉                     │
│        9 / 12 tama (75%)        │
│ Balikan mo ang mga ito:         │
│ • Internal failure cost …       │
│ • Enumerate the 4 …             │
│                    [ Done ]     │
└─────────────────────────────────┘
```

## Settings
```
┌─────────────────────────────────┐
│ ← Settings                      │
│ Explanation language            │
│ [ Taglish | Filipino | English ]│
│ New cards per day        [ 20 ] │
│ Theme   ( System | Light | Dark)│
└─────────────────────────────────┘
```
