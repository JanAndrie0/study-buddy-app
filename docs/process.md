# Study Buddy — Build Plan & Process Log

> Started 2026-11-20 · Solo project · Architecture: [`architecture.md`](./architecture.md)

## 1. What we're building

**One-liner:** Upload a lecture PDF → get a Filipino-style reviewer (flashcards, identification, enumeration, multiple choice, true or false, modified true or false) with explanations in English, Filipino or Taglish. Review it offline with spaced repetition.

**Definition of done (v1):**
- [ ] Release APK installed on your own phone
- [ ] PDF (≤ 20 MB) → reviewer generated in under 90 seconds with a progress screen
- [ ] All 6 question types playable and graded **offline** (airplane mode test)
- [ ] FSRS schedules reviews; Home shows "due today"
- [ ] Explanation language setting works (English / Filipino / Taglish)
- [ ] Eval score ≥ 85% on 8 real UE lecture PDFs
- [ ] Monthly Google Cloud cost under $5
- [ ] README with screenshots, architecture diagram, eval table, cost table and a 2-minute demo video

**Out of scope for v1:** accounts, sync, Play Store, camera scan, PPTX/DOCX, exam-term planner, barkada battle.

## 2. Working solo
- **Order matters:** prompt quality → local data → study screens → polish. A beautiful app with bad questions is useless, so the prompt comes first.
- **Use your own lectures as test data:** collect 8–10 real PDFs from different subjects (a technical one, a reading-heavy one like Rizal or Ethics, one with tables/diagrams).
- **Time-box:** ~8–10 hours/week, about 10 weeks. If a phase runs more than a week over, cut scope using the Risks table.
- **AI helpers:** Jules for writing tests, Claude for reviewing diffs and eval failures, Gemini in AI Studio for prompt experiments, Copilot/Antigravity while coding.

## 3. Tools we use

| Purpose | Tool | Notes |
|---|---|---|
| App framework | Flutter (stable) + Dart | Android first |
| IDE | Android Studio (emulator) + VS Code or Antigravity | Test on your real phone too |
| State management | Riverpod | One pattern everywhere |
| Local database | Drift (SQLite) | Offline-first |
| Spaced repetition | `fsrs` package (MIT) | Don't write the math yourself |
| File picking | `file_picker` | PDFs only in v1 |
| AI calls | Firebase AI Logic (`firebase_ai`) → Vertex AI Gemini API | Gemini Flash, structured output |
| App protection | Firebase App Check | Debug provider on your phone |
| Firebase setup | Firebase console + FlutterFire CLI | Blaze plan, linked to the billing account with your credits |
| Prompt experiments | Google AI Studio | Then copy to `assets/prompts/` |
| Evals | Python 3.12 + uv + google-genai + pypdf | `evals/run_eval.py` |
| Source control / CI | GitHub + GitHub Actions (`flutter test`) | Private now, public at the end |
| Mockups | Figma (or Claude-made design mockups) | Before Phase 4 |
| Cost watching | Google Cloud Billing budgets | $10/month, alerts at 50/90/100% |

## 4. Repository layout

```
study-buddy/
├── lib/
│   ├── main.dart
│   ├── config.dart               # model name, max tokens, limits
│   ├── data/
│   │   ├── database.dart         # Drift tables + migrations
│   │   └── repositories/
│   ├── services/
│   │   ├── generator_service.dart  # ONLY place that calls Gemini
│   │   ├── reviewer_parser.dart    # JSON → validated questions
│   │   ├── grader.dart             # offline answer checking
│   │   └── scheduler.dart          # FSRS wrapper
│   ├── features/
│   │   ├── home/  decks/  add_lecture/  study/  settings/
│   └── widgets/
├── assets/prompts/
│   ├── generate_reviewer.md
│   └── reviewer_schema.json
├── test/                          # grader, parser, scheduler tests (no Gemini)
├── evals/
│   ├── run_eval.py
│   ├── lectures/                  # your PDFs (gitignored)
│   └── results/
├── docs/
│   ├── architecture.md
│   ├── process.md                 # this file
│   └── screenshots/
├── CLAUDE.md
└── README.md
```

**Core data model (Drift):**
- `decks` (id, title, subject, source_file_name, file_hash, page_count, language, created_at)
- `questions` (id, deck_id, type, prompt, answer, accepted_answers JSON, choices JSON, items JSON for enumeration, wrong_word + correction for modified T/F, explanation, source_page)
- `card_states` (question_id, FSRS fields: due, stability, difficulty, state, last_review)
- `review_logs` (question_id, rating, was_correct, answered_text, reviewed_at)

## 5. Phases

### Phase 0 — Setup (Week 1)
- [x] Install Flutter, Android Studio, an emulator; run the counter app on your phone (wireless debugging; USB driver didn't work)
- [x] Create Firebase project `study-buddy`, upgrade to Blaze, link the billing account with your AI Pro credits (`study-buddy-ffd63`)
- [x] Budget: $10/month with alerts at 50/90/100% + forecasted spend
- [x] In the Firebase console, enable **AI Logic** with the **Vertex AI Gemini API** provider (now called "Agent Platform"); enable **App Check** (debug provider; register your phone's debug token); enforced
- [x] `flutterfire configure`; add `firebase_core`, `firebase_ai`, `firebase_app_check`
- [x] Hello world: pick a PDF → "Summarize this in Taglish" → show the text
- [ ] Create the GitHub repo, copy `docs/` + `CLAUDE.md`, add the `flutter test` Actions workflow
- **Exit:** your phone summarizes a real lecture PDF through Firebase AI Logic.

### Phase 1 — Prompt & schema (Weeks 2–3)  ← most important phase
- [ ] Collect 8 real lecture PDFs (mixed subjects); put them in `evals/lectures/` (gitignored)
- [ ] Write `reviewer_schema.json`: deck title, questions[] with `type` enum (flashcard, multiple_choice, identification, enumeration, true_false, modified_true_false) and the fields per type
- [ ] Write `generate_reviewer.md`: question-type mix, difficulty spread, "only use facts from the document", accepted alternative answers, source page, explanation language, Filipino reviewer style (e.g., modified true or false: underline the word to check)
- [ ] Iterate in AI Studio with structured output until 3 PDFs look good
- [ ] Write `evals/run_eval.py`: valid JSON · type mix within ±20% of target · answer text found in PDF text (pypdf, fuzzy) · no near-duplicate prompts · explanation language check · tokens + cost per deck
- [ ] Run on all 8 PDFs with Flash and Flash-Lite; log both in Eval History
- **Exit:** ≥ 80% on Flash; model choice decided and written in `lib/config.dart`.

### Phase 2 — Local data, grader, scheduler (Weeks 3–4)
- [ ] Drift tables from the data model above + first migration
- [ ] `reviewer_parser.dart`: JSON → questions, dropping invalid items (with a count of what was dropped)
- [ ] `grader.dart`: normalize (case, accents, punctuation, extra spaces) → exact or accepted-answer match → edit-distance tolerance by answer length; enumeration set match with partial credit; modified T/F requires wrong word + correction
- [ ] `scheduler.dart`: wrap `fsrs`; map right/wrong (and Again/Hard/Good/Easy for flashcards) to ratings
- [ ] Unit tests: at least 30 grader cases (including Filipino words with ñ, abbreviations, typos), parser cases with broken JSON, scheduler due-date cases
- **Exit:** `flutter test` green in CI.

### Phase 3 — Generation flow in the app (Week 5)
- [ ] Add Lecture screen: pick PDF → check size/page count → warn if no text layer (scanned)
- [ ] `generator_service.dart`: load prompt + schema from assets, call Gemini with structured output and `maxOutputTokens`, show progress, handle timeout/no internet with a friendly message and retry
- [ ] Save deck + questions + initial card states in one transaction
- [ ] Dev-only cache keyed by file hash so testing doesn't re-bill
- **Exit:** a real lecture becomes a saved deck; turning the network off afterwards still shows the deck.

### Phase 4 — Study experience (Weeks 6–7)
- [ ] Make mockups first: Home, Deck, Study (one per question type), Explanation sheet, Session summary, Settings
- [ ] Study screens for all 6 types with instant feedback
- [ ] Explanation bottom sheet with the source page number
- [ ] Session summary (score, weakest questions); Home "due today" from FSRS
- [ ] Settings: explanation language, daily new-card limit, dark mode
- **Exit:** a full review session works in **airplane mode**.

### Phase 5 — Polish & hardening (Week 8)
- [ ] Onboarding (3 screens), empty states, error states
- [ ] Test on the cheapest Android phone you can borrow; fix jank and app size (`flutter build apk --split-per-abi`)
- [ ] On-demand "translate explanation" (online, cached) for switching language on old decks
- [ ] Re-run evals; log the score
- [ ] Build a signed release APK; install on your phone
- **Exit:** you use it for a real quiz or exam week.

### Phase 6 — Portfolio (Weeks 9–10)
- [ ] README: problem (Gizmo isn't made for Filipino students), features, screenshots, architecture diagram, eval table (Flash vs Flash-Lite), cost per deck, offline design, how to run
- [ ] 2-minute demo video: upload → reviewer → identification + modified true or false in Taglish → airplane mode
- [ ] Write a short dev.to/LinkedIn post about the build
- [ ] 3–4 resume bullets (structured-output prompt design, eval-driven development, offline-first mobile architecture, cost control)
- [ ] Pick v2 from Add Later (likely camera scan → Play internal testing with classmates)
- **Exit:** public repo + post in your portfolio.

## 6. How to document as you go
1. **Process log (below):** add a dated line when you finish something, get stuck, or learn something.
2. **Decisions:** any change to stack, model or data model → run `/planfirst` to add a new ADR. Never edit old ADRs.
3. **Commits:** clear messages (`grader: accept accented variants`). After any prompt/schema change, run evals and log the score.
4. **Eval history + cost log:** update after every eval run and on the 1st of each month.
5. **Screenshots:** save good and bad generated questions to `docs/screenshots/` — great README and post material.

## 7. Process Log

| Date | What happened / what I learned |
|---|---|
| 2026-11-20 | Moved Study Buddy from AWS (credits unusable) to Google Cloud. Chose Flutter, Android first, just me as the user, offline review. |
| 2026-11-20 | Researched Gizmo, Knowt, Quizlet and Filipino reviewer apps. Gap: nothing turns your own lectures into a Filipino-style reviewer. v1 features: Pinoy quiz formats + Taglish explanations. |
| 2026-11-20 | Phase 0, Step 1: checked my machine. **Have:** Git 2.56, Node 26.12, uv 0.13.1, Python 3.12/3.14/3.15 (evals will use 3.12), VS Code, gcloud CLI, Android Studio (with bundled Java), Android SDK (platform 37, build-tools 36, emulator, `Medium_Phone` AVD). **Missing:** Flutter SDK, Android SDK command-line tools (needed for `flutter doctor --android-licenses`), Firebase CLI, FlutterFire CLI. Also: `steps.md` doesn't exist yet and the docs sit in the project root (`architecture_1.md`, not `docs/architecture.md`). Next: install Flutter. |
| 2026-11-20 | Phase 0, Step 1a: installed Flutter by `git clone -b stable` into `C:\dev\flutter` (no spaces in the path) and added `C:\dev\flutter\bin` to my user PATH. First run downloaded Dart. **Flutter 3.50.1, Dart 3.14.0.** Turned off Flutter analytics. `flutter doctor`: Android toolchain still needs cmdline-tools + licenses. The Visual Studio warning is only for Windows desktop apps, so I can ignore it (Android only). Next: cmdline-tools + licenses. |
| 2026-11-20 | Phase 0, Step 1b: installed Android SDK Command-line Tools from Android Studio's SDK Manager and accepted the licenses with `flutter doctor --android-licenses`. `flutter doctor` is green for Flutter and the Android toolchain (SDK 36, platform 37, Java 25 bundled with Android Studio). Only Visual Studio is ❌, which I don't need. Next: run the counter app on my phone. |
| 2026-11-20 | Phase 0, Step 1c (part 1): created the Flutter project at `C:\dev\study_buddy` (no spaces, so Gradle is happy) with `flutter create --org com.andreiguiang --project-name study_buddy --platforms android`. Android app ID: `com.andreiguiang.study_buddy` (Firebase will use this later). Copied `CLAUDE.md` to the root and the docs into `docs/` (`architecture_1.md` → `docs/architecture.md`). This is now the main copy of the docs. My phone didn't show up in `flutter devices` / `adb devices` yet, so USB debugging still needs fixing. |
| 2026-11-20 | Phase 0, Step 1c (part 2): debugging the USB connection. Windows sees my vivo V30e (USB vendor ID `2D95`) as MTP plus an "ADB Interface" on Microsoft's generic WinUSB driver, but `adb devices` stays empty. Tried restarting adb and adding `0x2d95` to `~/.android/adb_usb.ini`; still empty. Learned: `adb` is the bridge Flutter uses to install apps, and Windows needs the right USB driver for it. Next: revoke + re-allow USB debugging on the phone, install Google USB Driver. |
| 2026-11-20 | Checked again: `adb devices` still empty. The ADB Interface is still on Microsoft's generic `winusb.inf`, and the Google USB Driver folder (`Sdk\extras\google\usb_driver`) doesn't exist, so the driver fix hasn't been applied yet. |
| 2026-11-20 | Third check: still no device; driver still `winusb.inf`, Google USB Driver still not installed. Plan B: **wireless debugging** (Android 11+), which uses Wi-Fi instead of the USB driver. |
| 2026-11-20 | Wireless debugging worked: paired with the code on my phone, then `adb connect <phone-ip>:<port>`. adb now sees my phone (model V2339). First `flutter run` failed after ~4 min: Gradle wanted **Android NDK 28.2.13676358** (Flutter's template sets `ndkVersion = flutter.ndkVersion`) and couldn't auto-install it. Learned: the NDK is Android's C/C++ toolkit; Flutter's engine plugins need it even for the counter app. Next: install that NDK version. |
| 2026-11-20 | ✅ **Counter app runs on my phone.** `sdkmanager` now hands off to Google's new `android` CLI, which wants `ndk/28.2.13676358` (slash), not `ndk;28.2.13676358` (semicolon). Installed it with `android --no-metrics sdk install ndk/28.2.13676358` (2.1 GB). Then `flutter run -d <phone> --no-resident` built `app-debug.apk`, installed it over Wi-Fi and launched it on my V2339. It uses the Impeller renderer (Vulkan). **Phase 0 task 1 done.** Next: Firebase project on Blaze + $10 budget alerts. |
| 2026-11-20 | Phase 0, Step 2a: created the Firebase project **`study-buddy`** (project ID **`study-buddy-ffd63`**, permanent) with the Google AI Pro account. Google Analytics off (single user, nothing to measure). Still on the free Spark plan; Android app not registered yet (`flutterfire configure` will do that). Learned: a Firebase project *is* a Google Cloud project with Firebase features on top. Next: upgrade to Blaze. |
| 2026-11-20 | Phase 0, Step 2b: upgraded `study-buddy-ffd63` to **Blaze** (pay-as-you-go), linked to my only billing account. Learned: Blaze is required for the Vertex AI Gemini API in AI Logic; credits are used before my card; a budget only *alerts*, it doesn't cap spending. Next: $10/month budget with alerts. |
| 2026-11-20 | Phase 0, Step 2c: created budget **`study-buddy-monthly`**: $10/month, scoped to `study-buddy-ffd63`, **credits excluded** (so alerts show real usage, not what's left after credits), email alerts at 50/90/100% actual + 100% forecasted. Next: enable Firebase AI Logic with the Vertex AI Gemini API. |
| 2026-11-20 | Phase 0, Step 2d (started): opened AI Logic. **Google renamed "Vertex AI Gemini API" to "Agent Platform Gemini API"** in the console (billing required, choose location, "Agent Platform Studio"). Picked it, not the Gemini Developer API. The setup wizard needs a registered app before it can enable the API + App Check, so the next step is installing the Firebase CLI + FlutterFire CLI and running `flutterfire configure`. ⚠️ To verify: the `firebase_ai` Dart backend name may have changed too (`vertexAI()` vs something like `agentPlatform()`); check pub.dev before writing code. |
| 2026-11-20 | Phase 0, Step 2e: installed **Firebase CLI 15.37.0** (`npm install -g firebase-tools`) and **FlutterFire CLI 1.5.0** (`dart pub global activate flutterfire_cli`). Added `%LOCALAPPDATA%\Pub\Cache\bin` to my user PATH so `flutterfire` works anywhere. npm blocked install scripts for `protobufjs` and `re2` (npm's new safety default); the CLI runs fine without them, so I left them blocked. Next: `firebase login`, then `flutterfire configure`. |
| 2026-11-20 | Phase 0, Step 2f–2g: signed in with `firebase login`. Ran `flutterfire configure --project=study-buddy-ffd63 --platforms=android --android-package-name=com.andreiguiang.study_buddy --yes`. It registered the Android app (App ID `1:795002709081:android:febdf88b021fd46a64bd48`) and generated `lib/firebase_options.dart`, `android/app/google-services.json` and `firebase.json`. It also added the `com.google.gms.google-services` Gradle plugin (4.3.15). Learned: the API key in these files is an *identifier*, not a password; App Check is what stops other people from using it. Next: reload the AI Logic wizard and finish enabling the Agent Platform Gemini API. |
| 2026-11-20 | Phase 0, Step 2h: reloaded the AI Logic wizard. My Android app showed up, and I **enabled the Agent Platform (Vertex AI) Gemini API**. It costs nothing until requests are sent. Next: App Check. |
| 2026-11-20 | Phase 0, Step 2i: got my debug signing key's fingerprints with `gradlew :app:signingReport` (key: `~/.android/debug.keystore`, valid until 2056). SHA-1 `8C:F2:7E:52:DD:06:5A:27:87:7B:B8:EA:7E:09:26:0D:54:E6:E5:54`, SHA-256 `8B:4C:54:96:6A:BF:FA:AC:F3:AD:00:07:A0:4B:E3:C8:4B:10:8D:F0:2A:0F:13:5C:9A:D3:A6:1E:9C:B6:BD:EC`. Learned: fingerprints are public IDs of the signing key, not secrets; the keystore file itself is the secret part. A release keystore later will have different fingerprints, which I'll need to add too. |
| 2026-11-20 | Phase 0, Step 2j: added the SHA-256 to the Android app in Project settings and **registered App Check with Play Integrity**. Enforcement for AI Logic is **off** on purpose: enforcing before the app sends tokens would block every call. Still to do: add the App Check **debug token** from my phone (after the App Check code is in the app), then enforce. Next: add `firebase_core`, `firebase_ai`, `firebase_app_check`. |
| 2026-11-20 | Phase 0, Step 3: `flutter pub add firebase_core firebase_ai firebase_app_check file_picker` → **firebase_core 5.2.0, firebase_ai 5.2.0, firebase_app_check 0.5.2, file_picker 13.4.0**. `firebase_auth` 7.1.0 came in as a dependency of `firebase_ai`; I'm not *using* Firebase Auth (CLAUDE.md). **Checked the real APIs in the installed source** (handoff's "to verify" list): (1) backend is **`FirebaseAI.agentPlatform(location: ...)`**; `vertexAI()` no longer exists, so the rename reached the SDK too. (2) `GenerationConfig` has **`responseJsonSchema: Map<String, Object?>`**, so the raw JSON schema from `assets/prompts/` can be passed directly and **no JSON → `Schema` converter is needed** (Step 17 shrinks). Only one of `responseSchema` / `responseJsonSchema` may be set. (3) `maxOutputTokens` is in `GenerationConfig`. (4) PDFs go in as `InlineDataPart('application/pdf', bytes)`. (5) App Check: `FirebaseAppCheck.instance.activate(providerAndroid: AndroidDebugProvider())` for debug; the default is `AndroidPlayIntegrityProvider()`. Next: check current Gemini model names + prices, then the hello-world. |
| 2026-11-20 | Checked models + prices (Firebase AI Logic models page + Gemini API pricing page). **Candidates:** `gemini-3.8-flash` (stable, no shutdown date) and `gemini-3.5-flash-lite` (stable, no shutdown date). Avoid `gemini-3.6-flash` (Agent Platform shutdown 2026-11-19, already gone), `gemini-3.7-flash` (shuts down 2027-01-28) and `gemini-2.5-*` (shut down 2026-10-20). Agent Platform may retire "short-term availability" models ~45 days after a replacement, so keep the model name in `lib/config.dart` only. **Prices (Gemini Developer API page, per 1M tokens; Agent Platform page didn't load, so confirm in the Cloud console):** 3.8 Flash $0.75 in / $3.75 out until 2026-12-31, **doubling to $1.50 / $7.50 on 2027-01-01**; 3.5 Flash-Lite $0.30 in / $2.50 out. Thinking tokens bill as output. PDFs bill at the image rate (1 page = 1 image). **Limits:** 20 MB total request (matches the plan), 900 pages per PDF, 65,536 output tokens. Plan: start Phase 0 with `gemini-3.8-flash`; Phase 1 evals decide Flash vs Flash-Lite (the 2027 price jump makes Flash-Lite more attractive). |
| 2026-11-20 | Phase 0, Step 4: wrote the hello-world. `lib/config.dart` (model `gemini-3.8-flash`, location `global`, `maxOutputTokens` 4096, max PDF **15 MB** because base64 makes the request ~33% bigger than the file and the request limit is 20 MB). `assets/prompts/hello_summary.md` (Taglish summary prompt; registered in `pubspec.yaml`). `lib/services/generator_service.dart` (the only Gemini caller; model created `late` so tests never touch Firebase; returns token counts for the cost log). `lib/main.dart` (Firebase init, App Check debug provider in debug builds / Play Integrity in release, pick PDF → summary screen). Replaced the counter test with a hello-screen test. `flutter analyze`: no issues; `flutter test`: 1 passed. Installed on my phone; App Check printed a **debug token** to logcat (secret, so not written here). Learned: Flutter 3.50's template imports `package:material_ui/material_ui.dart`, and `file_picker` 13 uses `FilePicker.pickFile()` returning `PlatformFile.xFile`. Next: register the debug token, then summarize a real lecture. |
| 2026-11-20 | ✅ **Phase 0 exit reached: my phone summarized a real lecture PDF in Taglish through Firebase AI Logic** (Agent Platform Gemini API, `gemini-3.8-flash`, App Check debug token registered in the console as `andrei-phone-v30e`). The whole chain works: file picker → bytes → `GeneratorService` → Firebase AI Logic + App Check → Gemini → text on screen. Remaining Phase 0: enforce App Check for AI Logic, GitHub repo + `flutter test` Actions workflow. |
| 2026-11-20 | Phase 0, Step 5: checked App Check metrics (requests verified), then **enforced App Check for Firebase AI Logic**. Retested after enforcement: summary still works with the debug token. Requests without a valid App Check token are now rejected, so a copied API key alone can't spend my credits. To remember for Phase 5: the release APK uses Play Integrity, which may reject a sideloaded app. Next: GitHub repo + CI. |
| | |

## 8. Eval History

| Date | Model | PDFs | Score | Avg cost / deck | Notes |
|---|---|---|---|---|---|
| | | | | | |

## 9. Cost Log

| Month | Gemini (AI Logic) | Other | Total | Credits left |
|---|---|---|---|---|
| 2026-11 | | | | |

## 10. Risks to watch

| Risk | Sign | Response |
|---|---|---|
| Questions not grounded in the lecture | Eval "answer found in PDF" check < 85% | Tighten the prompt; require `source_page`; drop items without one |
| Grader too strict on Filipino/Taglish answers | You get marked wrong when you were right | Add accepted answers in the prompt; loosen edit-distance; log disputes |
| Long lectures cut off | Truncated JSON / few questions on 60+ page PDFs | Split by page ranges (ADR-003 revisit) |
| Flutter learning curve | Phase 0–2 take more than 5 weeks | Use the official Flutter + Firebase codelabs; cut Settings to language only |
| Schedule slips (exams, thesis) | Phase exit missed by > 1 week | Ship with 4 question types (drop enumeration + modified T/F to v1.1) |
