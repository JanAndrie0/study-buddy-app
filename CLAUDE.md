# Study Buddy

Flutter Android app that turns your own lecture PDFs into a Filipino-style reviewer (flashcards, identification, enumeration, multiple choice, true or false, modified true or false) with English/Filipino/Taglish explanations, reviewed offline with FSRS. Build plan and progress log: `./docs/process.md`. Step-by-step guide: `./docs/steps.md`.

**New session? Read `./docs/handoff.md` first** — it has the background, decisions, current status and things still to verify.

<!-- planfirst:start -->
## Architecture Reference
Full spec: `./docs/architecture.md` — read before adding any infrastructure.

### Stack (moment: validate)
- App: Flutter (Dart), Android first, Material 3
- State: Riverpod
- Local DB: Drift (SQLite) — decks, questions, card_states, review_logs
- Spaced repetition: `fsrs` package
- AI: Firebase AI Logic (`firebase_ai`) → Vertex AI Gemini API, Gemini Flash, structured output
- Prompt + schema: `assets/prompts/` (shared with evals)
- Grading: local Dart grader (fuzzy match, enumeration partial credit, modified T/F)
- Protection: Firebase App Check (debug provider on own device)
- Evals: Python `evals/run_eval.py` (google-genai + pypdf)
- CI: GitHub Actions running `flutter test`
- Cost control: Google Cloud budget alerts ($10/mo)

### Agent Rules
- DO NOT add infrastructure that isn't solving a problem you have today. Moment = validate, single user.
- DO NOT add a backend server, Cloud Run, Firestore, Firebase Auth or any cloud database until an "Add Later" trigger in docs/architecture.md is met.
- DO call Gemini ONLY in `GeneratorService`. Grading, scheduling and studying MUST work with the network off.
- DO load the prompt and schema from `assets/prompts/`; never inline prompt text in Dart code.
- DO validate every generated item against the schema and drop invalid items; never crash on bad model output.
- DO use the Vertex AI Gemini API backend in Firebase AI Logic (now named "Agent Platform Gemini API"; `FirebaseAI.agentPlatform()` in Dart), never the Gemini Developer API backend, for real lecture files.
- DO set the model name in exactly one place (`lib/config.dart`) and set `maxOutputTokens`.
- DO use Drift for all persistence and write a migration for every schema change.
- DO use the `fsrs` package for scheduling; DO NOT write custom spaced-repetition math.
- DO write unit tests for the grader, parser and scheduler before building their screens. Tests MUST NOT call Gemini.
- DO run `evals/run_eval.py` after any prompt or schema change and log the score in docs/process.md.
- DO NOT add React Native, LangChain, a vector DB, embeddings or an on-device LLM.
- DO keep App Check enabled; use the debug provider only on your own device.
- DO NOT commit `.env` files, keystores or service account keys.
- PREFER simple, readable Dart over clever abstractions: this is a learning and portfolio repo.
- DO grade modified true or false in the underline style (ADR-007): every item MUST have `underlined_word` appearing in `prompt` (case-insensitive) and, when the answer is False, a non-empty `correction`; drop items that break this.
- DO make every new field in `reviewer_schema.json` required (empty list/string when not applicable): Gemini skips optional fields.
- DO keep `assets/prompts/question_mix.json` as the only source of question-type shares; the app and the evals both read it (ADR-008).
<!-- planfirst:end -->
