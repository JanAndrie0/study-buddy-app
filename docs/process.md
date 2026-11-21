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
- [x] Create the GitHub repo, copy `docs/` + `CLAUDE.md`, add the `flutter test` Actions workflow (`JanAndrie0/study-buddy-app`, private)
- **Exit:** your phone summarizes a real lecture PDF through Firebase AI Logic.

### Phase 1 — Prompt & schema (Weeks 2–3)  ← most important phase
- [x] Collect 8 real lecture PDFs (mixed subjects); put them in `evals/lectures/` (gitignored). *9 PDFs, 4 subjects; no Filipino-language lecture yet*
- [x] Write `reviewer_schema.json`: deck title, questions[] with `type` enum (flashcard, multiple_choice, identification, enumeration, true_false, modified_true_false) and the fields per type
- [x] Write `generate_reviewer.md`: question-type mix, difficulty spread, "only use facts from the document", accepted alternative answers, source page, explanation language, Filipino reviewer style (e.g., modified true or false: underline the word to check)
- [x] Iterate until PDFs look good. *Done with the eval script (v1 → v3) instead of AI Studio, plus reading real decks by hand*
- [x] Write `evals/run_eval.py`: valid JSON · type mix within ±20% of target · answer text found in PDF text (pypdf, fuzzy) · no near-duplicate prompts · explanation language check · tokens + cost per deck
- [x] Run on all PDFs with Flash and Flash-Lite; log both in Eval History
- **Exit:** ≥ 80% on Flash; model choice decided and written in `lib/config.dart`.

### Phase 2 — Local data, grader, scheduler (Weeks 3–4)
- [x] Drift tables from the data model above + first migration (schema v1)
- [x] `reviewer_parser.dart`: JSON → questions, dropping invalid items (with a reason for each dropped item)
- [x] `grader.dart`: normalize (case, accents, punctuation, extra spaces) → exact or accepted-answer match → edit-distance tolerance by answer length; enumeration set match with partial credit; modified T/F in the underline style (ADR-007: True/False + correction)
- [x] `scheduler.dart`: wrap `fsrs`; map right/wrong (and Again/Hard/Good/Easy for flashcards) to ratings
- [x] Unit tests: 45 grader cases (including Filipino words with ñ, abbreviations, typos), 24 parser cases with broken JSON, 6 scheduler due-date cases, 5 database cases
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
| 2026-11-20 | Phase 0, Step 6: installed **GitHub CLI 2.105.0** (`winget install GitHub.cli`), signed in with `gh auth login` (account JanAndrie0). Added `.env`, keystores, service-account keys, `evals/lectures/` and Python caches to `.gitignore`; scanned the 38 files for the debug token or private keys before committing (none). Commit email set per repo to my GitHub **no-reply** address so my real email stays private. `study-buddy` was already taken by the old AWS repo (left untouched), so I created **private `JanAndrie0/study-buddy-app`** and pushed the first commit. Added `.github/workflows/flutter-test.yml` (Flutter 3.50.1: `pub get` → `analyze` → `test`). **First CI run: green ✅.** One warning: `actions/checkout@v4` runs on deprecated Node 20, so bump to v5 later. **🎉 Phase 0 complete.** Next: Phase 1, prompt & schema. |
| 2026-11-20 | **Phase 1 started.** Created `evals/lectures/` (gitignored, checked with `git check-ignore`) and `evals/results/`. Step 1: collecting 8 real lecture PDFs from different subjects. |
| 2026-11-20 | PDF inventory (pypdf via `uv run --with pypdf`, no Gemini). 5 PDFs, **all CIT4303** (IT economics): LECT3 Software Acquisition (6 pp), LECT4 Software Quality Economics (7 pp), LECT5 Technology Cost Analysis pt 1 (6 pp), with text layers of ~1,700–2,000 chars/page. Lect7 TCO (24 pp) and Lect8 Cost-Benefit/ROI (35 pp) have **no text layer: 0 fonts, one image per page** (slides saved as images). Gemini can still read image PDFs (it treats each page as an image), but the eval's "answer found in PDF text" check can't run on them, so they'll be scored on everything except grounding. Learned: "has text" vs "image-only" is checkable by looking for fonts in the PDF. Gaps: other subjects, a 40+ page text PDF, Filipino/Taglish content, a programming/technical one. |
| 2026-11-20 | Added more PDFs; the two image-only CIT4303 decks (Lect7, Lect8) are no longer in the folder. **Eval set now 9 PDFs, 4 subjects, all with text layers:** CIT4303 IT economics ×3 (6–7 pp, ~1,700–2,000 chars/pg); Ethics ×3 (M2 Human Acts 39 pp, M3 Intellectualism 25 pp, M4 Virtue Ethics 22 pp); Ethical Hacking ×2 (Module 1 intro 9 pp, Module 2 Network Scanning 19 pp, ~1,450–1,750 chars/pg); Typography ×1 (31 pp). Typography, M3 and M4 are "thin" (112–170 chars/pg): normal slide decks with short bullets, so there are fewer facts per page to ground questions on. Still missing: Filipino-language content. |
| 2026-11-20 | Phase 1, Step 2: wrote **`assets/prompts/reviewer_schema.json`**. Top level: `deck_title`, `subject`, `explanation_language` (english/filipino/taglish), `questions` (1–60). Each question has the required `type`, `source_page`, `prompt`, `answer`, `explanation`, `difficulty`, plus optional type-specific fields: `choices` (exactly 4, MCQ), `accepted_answers` (identification), `items` (enumeration), `wrong_word` + `correction` (modified T/F when False). **Design choice: one flat question shape + per-type rules in `description`s**, not a separate `anyOf` branch per type, because it's simpler for the model and for my parser. The parser (Phase 2) enforces per-type rules and drops broken items (ADR-003). `source_page` comes before `answer` and `explanation` comes after `answer` on purpose: the model writes fields in order, so it "finds the page" first and explains after deciding the answer. Also wrote `test/fixtures/sample_reviewer.json` (one of each type, Taglish). Checked with Python `jsonschema` (Draft 2020-12): schema valid, sample 0 errors, deliberately broken sample caught. Not yet checked: whether Gemini accepts every keyword (`minItems`, `minimum`); the first eval run will tell. *(Later: `maxItems` on `questions` was rejected and removed; `correction` became required in v3.)* |
| 2026-11-20 | **Decision: modified true or false uses the classic underline style.** The statement shows one underlined word (`underlined_word`, always present, exact substring of `prompt`); the student answers True/False and, if False, types the replacement (`correction`). Ran `/planfirst` (UPDATE): added **ADR-007** to `docs/architecture.md`, superseding only the modified T/F rule of ADR-004 (ADR-004 itself not edited, per the never-edit-old-ADRs rule). Updated the Local grader role, the agent rules (architecture.md + CLAUDE.md) and the Changelog, which also notes the Vertex AI → Agent Platform rename. Schema + fixture: `wrong_word` → `underlined_word`. Re-validated: schema valid, sample 0 errors, `underlined_word` found in `prompt`. Learned: an ADR records *why* a decision was made; superseding instead of editing keeps the history honest. Next: write `generate_reviewer.md`. |
| 2026-11-20 | Phase 1, Step 3: wrote **`assets/prompts/generate_reviewer.md`** v1 (~760 words). Sections: (1) grounding: only PDF facts, write fewer rather than pad, skip cover/objectives/references, `source_page` = physical PDF page; (2) type mix (identification 25, MCQ 20, flashcard 15, T/F 15, modified T/F 15, enumeration 10%) + difficulty 40/40/20 + each fact tested at most twice; (3) per-type rules (MCQ: 4 plausible options from the same lecture, no "all of the above"; identification: answer not in the prompt, acronym/full form in `accepted_answers`; enumeration: only real lists; T/F and modified T/F: ~half False, change an important detail; underline style per ADR-007); (4) explanations in the chosen language with examples of natural Filipino and Taglish; questions stay in the lecture's language. Two placeholders filled by code: `{{explanation_language}}`, `{{target_questions}}`. Checked: every field name in the prompt exists in the schema. Not yet tested on Gemini; that's what the eval script is for. Next: `evals/run_eval.py`. |
| 2026-11-20 | Phase 1, Step 4: built **`evals/run_eval.py`** (uv project `evals/pyproject.toml`: Python 3.12, google-genai 3.6.1, pypdf 7.1.1, jsonschema 4.26.0, rapidfuzz 3.14.6). It calls Vertex AI (`genai.Client(vertexai=True, project="study-buddy-ffd63", location="global")`) with the **same** prompt + schema files as the app, using my gcloud Application Default Credentials. Score per deck = average of **validity** (per-type rules the Dart parser will enforce), **grounding** (answer fuzzily found in the PDF text, rapidfuzz ≥ 85), **mix** (1 − half the total difference from the target type shares), **uniqueness** (no prompts ≥ 90 token-set similar) and **language** (Filipino function-word ratio of explanations). Also reports page accuracy, tokens and cost. Target questions = 0.8 × pages, clamped 10–40. Responses are cached by a hash of prompt + schema + PDF + model, so re-scoring is free (`--rescore`). **Bug found:** Gemini returned a bare `400 INVALID_ARGUMENT`. I narrowed it down with tiny test calls: model ✓, PDF ✓, small schema ✓, our schema ✗, and the culprit was **`maxItems` on the top-level `questions` array** (all other min/max rules are accepted). Removed it; the parser will cap at 60 instead. Smoke test (LECT4, Flash): **93.5%**, 10/10 questions, $0.019, 76 s, 2,839 thinking tokens. Learned: when an API error is vague, bisect the request. |
| 2026-11-20 | Phase 1, Step 5: eval iterations (details in Eval History). **v1** both models ~94% but validity ~90%: modified T/F items marked False with the correction only in the explanation. **v2** (field moved next to `answer`, "MUST" in the prompt) didn't help; inspecting raw responses showed the `correction` key was simply **missing** in 18 of 20 cases: with constrained decoding, Gemini skips optional fields. **v3** made `correction` a **required** field with a value for every case (False → replacement, True → copy of the underlined word, other types → ""), which brought validity to **100%** for both models. Also fixed two bugs in my own scorer, found by reading the flagged items instead of trusting the number: one-word flashcards counted as "duplicates" of every question containing that word, and the English word "to" counted as Filipino. Spot-read real decks (Virtue Ethics): plausible MCQ options, sensible underlines, natural Taglish. Learned: (1) a schema rule beats a prompt instruction; (2) always read examples behind a metric, because evals can be wrong too. Also added 429/503 retry with backoff to the script. |
| 2026-11-20 | ✅ **Phase 1 complete. Model decision: `gemini-3.5-flash-lite`** (97.6% vs Flash's 97.9%, within the plan's 5-point rule; ~⅓ the cost at $0.0084/deck; 14 s vs 58 s; and 3.8 Flash's price doubles on 2027-01-01). Explanation languages all ≥ 97% (EN 97.4, FIL 97.2, Taglish 97.6). Updated `lib/config.dart`: model `gemini-3.5-flash-lite`, `maxOutputTokens` 8192 (biggest deck used 3,335), and `questionsPerPage` 0.8 / min 10 / max 40, matching `target_questions()` in the eval. `flutter analyze` clean, `flutter test` passing. Total Gemini spend for Phase 0–1 ≈ $1.13. **Known gaps:** no Filipino-language lecture in the eval set yet; page accuracy ~80% (the source page is sometimes off by more than 1 page, so the explanation sheet's "see page X" may be wrong); explanations sometimes mention "slide N". Next: Phase 2 (Drift tables, parser, grader, scheduler, tests). |
| 2026-11-20 | **Phase 2: local data, grader, scheduler.** Added **drift 2.35.4**, drift_flutter 0.3.1, **fsrs 2.0.1** (dev: drift_dev 2.35.3, build_runner 2.17.1). Read the installed fsrs source first (handoff "to verify"): `Card(cardId:)`, `Scheduler().reviewCard(card, Rating.good, reviewDateTime: utc)` returns `(card, reviewLog)`; times must be UTC. Wrote: **`lib/models/reviewer_item.dart`** (`QuestionType` enum + `ReviewerItem`); **`lib/services/reviewer_parser.dart`** (never throws; drops broken items with a reason; same rules as `item_problems()` in the eval so the eval score predicts what the app keeps; also drops duplicate prompts and caps at 60, since Gemini rejected `maxItems`); **`lib/services/grader.dart`** (normalize: case, accents, ñ → n, punctuation, leading "the/a/an"; typo tolerance 0/1/2/3 edits for ≤4/≤8/≤15/longer answers so "DNS" ≠ "DNA"; numbers must match exactly; enumeration any order with partial credit; modified T/F per ADR-007 with 0.5 credit for False + wrong correction); **`lib/services/scheduler.dart`** (`ReviewScheduler`: score 1.0 → Good, ≥ 0.5 → Hard, else Again; flashcards pick their own rating); **`lib/data/database.dart`** (tables `decks`, `questions`, `card_states`, `review_logs`; list fields as JSON via a `TypeConverter`; schema v1 with `onCreate` + an `onUpgrade` hook for future versions; `PRAGMA foreign_keys = ON` so deleting a deck cascades; `insertDeck()` saves deck + questions + initial FSRS cards in **one transaction**; `countDue()` for Home). Generated `database.g.dart` with `dart run build_runner build`. **Tests: 78 passing** (45 grader, 24 parser, 6 scheduler with fuzzing off, 5 database on in-memory SQLite, incl. a failed save leaving nothing behind). `flutter analyze` clean. Learned: SQLite ignores `ON DELETE CASCADE` unless foreign keys are switched on per connection. |
| 2026-11-20 | **Phase 3 core:** Add Lecture flow (pick PDF → local checks → generate → parse → save in one transaction), real `GeneratorService` (prompt + schema from assets, Taglish error messages, debug-only cache by file hash), Home + Deck screens, Riverpod. Dropped pdfrx (its PDFium build hook needs MSVC just to run tests) for a ~80-line pure-Dart PDF inspector (page count from `/Type /Pages /Count`, text layer from `Tj`/`TJ` in inflated streams); it matches pypdf's page count on all 9 lectures. Verified on my phone: generate → open deck → airplane mode → deck still there. Prompt rule: no "slide N" in explanations (re-eval 96.6%). CI → `actions/checkout@v5`. |
| 2026-11-21 | **Phase 3 add-on (my request): choose quiz types, flashcards, notes** (ADR-008 via `/planfirst`). Add Lecture now asks "Gusto mo ba ng quiz?" + 5 quiz types (MCQ, identification, modified T/F default), then Flashcards / Notes; at least one required. Notes = key points by topic from the same single call (required `notes` array). Shared `assets/prompts/question_mix.json`; prompt placeholders `{{question_mix}}`, `{{notes_instruction}}`. DB schema v2 (`note_sections`) with Drift `make-migrations` snapshots + a data-checked v1 → v2 test. Evals (Flash-Lite): everything on **96.1%** ($0.0106/deck); MCQ-only + notes **96.5%** with **149/149 questions MCQ**. Max output 5,350 tokens, so `maxOutputTokens` 8192 stays. |
| 2026-11-21 | **Phase 4 (code done, phone test pending):** mockups in `docs/mockups.md`; DB schema v3 (`app_settings`: language, new cards/day, theme, onboarding flag); study queue (due reviews first, then today's new-card allowance); `StudyController` + one screen per type (modified T/F underlines the word, asks for the correction on False), feedback panel with explanation + source page, session summary; Settings screen; "Mag-review na" on Home, "Study" on decks. **134 tests passing**, analyze clean. Installed on my phone over the old build: launched with no errors after the real v1 → v3 upgrade. **Stopped here for the day; not committed yet.** Next: hand-test Phase 4 on the phone (incl. airplane mode), commit + push, then Phase 5 (onboarding, polish, release APK) and Phase 6 (README, demo). |
| 2026-11-21 | **Design feedback #1–4** (`docs/design-feedback.md`, plan approved). **#3 English default:** ADR-009; DB schema v4 rebuilds `app_settings` and switches the untouched Taglish row to English; migrations moved to Drift's `stepByStep` with frozen per-version schemas (the v1 → v3 test failed until then, because `createTable(appSettings)` used today's definition). **#1 bold terms:** prompt wraps key terms in `**…**` in notes + explanations; `RichTerms` widget renders them. Eval (Flash-Lite, English): **96.0%**, 171/181 note points and 127/132 explanations bolded, 0 stray `**` in questions/answers. **#2 + #4 Quizlet-style redesign (own branding, indigo kept):** shared `lib/theme.dart`; deck page with header, swipeable flashcard preview, mode tiles (Flashcards · Quiz · Test · Match) and tabs **Flashcards · Notes · Questions** with a tab-specific button; **Flashcards** mode (all deck cards, flip animation, swipe right = Know / left = Still learning, saved to FSRS, "review the still learning" rounds); **Quiz** with a slide-up green/red feedback banner + segmented progress; **Test** (choose types + count, no feedback, score ring, practice only); **Match** (6 pairs, timer); Home hero "due today" card + deck cards with "% known". **149 tests passing**, analyze clean. Installed on my phone over the old build: no errors after the v3 → v4 upgrade. Phone hand-test still to do. |
| 2026-11-21 | **UI/UX polish with the `ui-ux-pro-max` skill.** (The `mobile-app-ui-design` skill I installed wasn't found in this session.) The skill's search database (`scripts/`, `references/`) isn't in the installed plugin, so I used its built-in priority checklist instead, not database matches. Fixes: real Material icons instead of emoji-as-icons; theme-aware `successColor`/`warningColor`/`onSemanticColor` so green/orange keep contrast in dark mode (white-on-light-green buttons failed there); ✓/✗ icons on multiple-choice results and wrong Match pairs (not colour alone); every animation goes through `motion()` and respects Android's "remove animations"; haptics on right/wrong, swipes and matches; screen-reader labels on flip cards and Match tiles; "Item 1…" labels on enumeration boxes; SafeArea under the Flashcards buttons; body line height 1.45; Home empty state with icon + "Add lecture" button. 149 tests passing, analyze clean. APK built; phone install pending (phone wasn't connected). |
| 2026-11-21 | **Phone bugs B1–B4** (`docs/design-feedback.md`). **B1** red "dismissed Dismissible is still part of the tree" flash on every flashcard swipe → the controller now shows the next card first and saves after. **B2** Test stuck on loading with one type → the Test screen only watched the auto-disposed session after "Start", so `start()` filled a session that got thrown away; it now watches from the first frame. **B3** Quiz on a new deck said "Walang due" → the daily new-card limit (counting flashcard swipes too) was used up; a deck's Quiz now ignores the limit (you chose the deck), and Home review says "You've reached today's new-card limit, N waiting" with **Study anyway**. **B4** hard-to-read MCQ choices (light accent text, greyed when locked) → main text colour, medium weight, 17 sp, also when disabled. Regression tests for B1 and B3 (**152 passing**, analyze clean); B2 checked on the phone because widget tests can't wait on the in-memory database. Learned: with Riverpod `autoDispose`, `ref.read(...notifier)` without anyone watching can hand you a provider that's about to be disposed. |
| 2026-11-21 | **Phase 5 (polish + release).** App Check decision: my sideloaded release APK uses the **debug provider with a fixed token** (only my phone), passed at build time with `--dart-define-from-file=secrets.json` (gitignored) and registered in the Firebase console as `andrei-phone-release`; other release builds would use Play Integrity. Release signing via `android/key.properties` + my keystore (both outside Git; falls back to the debug key when missing, so CI still builds). Gradle gotcha: inside `android { }`, `java` means the Android Java settings, so `java.util.Properties` didn't resolve; imported it at the top instead. **3 onboarding screens** on first launch (Skip / Next / Get started, saved in `app_settings.onboarding_done`). Test empty state no longer says "Walang due". `flutter build apk --release --split-per-abi`: **arm64 20.8 MB**, armeabi-v7a 18.7 MB, x86_64 22.0 MB (debug APK was 209 MB). 152 tests passing. Installing the release build needs the debug app uninstalled first (different signing key), which deletes local decks. |
| | |

## 8. Eval History

| Date | Model | PDFs | Score | Avg cost / deck | Notes |
|---|---|---|---|---|---|
| 2026-11-20 | gemini-3.8-flash | 9 | **94.5%** | $0.0233 | prompt/schema v1, Taglish. Validity ~90%: 13 modified T/F "False but no correction", 5 underline not in prompt. Page accuracy 58–100%. ~76 s/deck. |
| 2026-11-20 | gemini-3.5-flash-lite | 9 | **93.9%** | $0.0084 | v1, Taglish. Same failure pattern (10 no-correction, 5 underline, 1 dup choice, 1 answer-in-prompt). LECT5 validity 70%. First try hit a 429 from running 2 models in parallel; added retry with backoff. |
| 2026-11-20 | gemini-3.8-flash | 9 | 93.0% | $0.0295 | v2: `correction` moved right after `answer` + "MUST fill" in prompt; eval checks flashcards by either side and underline case-insensitively. **Didn't fix it**: 12 no-correction, 9 underline. 44 s/deck. |
| 2026-11-20 | gemini-3.5-flash-lite | 9 | 93.5% | $0.0083 | v2. 11 no-correction, 1 underline. 9 s/deck. Root cause found: 18 of 20 False modified T/F items had **no `correction` key at all**, so Gemini skips optional fields regardless of the prompt. |
| 2026-11-20 | gemini-3.8-flash | 9 | **97.9%** | $0.0269 | **v3**: `correction` REQUIRED on every item (False → replacement, True → the underlined word, other types → ""). **Validity 100%**, 0 broken items. 58 s/deck, max 7,267 out+think tokens. Scorer fixes (re-scored from cache): duplicates via `token_sort_ratio` (token_set flagged one-word flashcards), "to" removed from the Filipino word list. |
| 2026-11-20 | gemini-3.5-flash-lite | 9 | **97.6%** | $0.0084 | **v3, Taglish. ✅ Chosen model.** Validity 100%, 14 s/deck, max 3,335 out+think. Sometimes writes fewer than the target on thin slides (23/25, 16/20, 12/15), which the prompt allows. Page accuracy ~80%. |
| 2026-11-20 | gemini-3.5-flash-lite | 9 | 97.4% | $0.0084 | v3, **English** explanations. |
| 2026-11-20 | gemini-3.5-flash-lite | 9 | 97.2% | $0.0087 | v3, **Filipino** explanations. |
| | | | | | |

## 9. Cost Log

| Month | Gemini (AI Logic) | Other | Total | Credits left |
|---|---|---|---|---|
| 2026-11 | ≈ $1.13 so far (estimate: eval runs + hello-world, at Gemini API list prices; check the Billing page for the real figure) | $0 | ≈ $1.13 | check console |

## 10. Risks to watch

| Risk | Sign | Response |
|---|---|---|
| Questions not grounded in the lecture | Eval "answer found in PDF" check < 85% | Tighten the prompt; require `source_page`; drop items without one |
| Grader too strict on Filipino/Taglish answers | You get marked wrong when you were right | Add accepted answers in the prompt; loosen edit-distance; log disputes |
| Long lectures cut off | Truncated JSON / few questions on 60+ page PDFs | Split by page ranges (ADR-003 revisit) |
| Flutter learning curve | Phase 0–2 take more than 5 weeks | Use the official Flutter + Firebase codelabs; cut Settings to language only |
| Schedule slips (exams, thesis) | Phase exit missed by > 1 week | Ship with 4 question types (drop enumeration + modified T/F to v1.1) |
