# Handoff — Study Buddy (from Claude chat → Claude Code)

> Written 2026-11-20. Read this first, then `CLAUDE.md`, `docs/architecture.md`, `docs/process.md`, `docs/steps.md`.

## Who you're working with
- **John Andrei Guiang**, 3rd-year BSIT student at the University of the East (Manila), working **solo**.
- Goal: become an **AI engineer**; this is a **learning + portfolio** project, so explain what you do and why while building, not just hand over code.
- Studies mostly on his **phone**, often on mobile data / no signal (commutes).
- Tools he has: Google AI Pro (≈$10/month Google Cloud credits, ~$80 banked), GitHub Education (Copilot), Claude Pro, Coursera.
- Wants **every phase documented** so he learns while building.

## Project in one paragraph
Study Buddy is a **Flutter Android app** that turns his own lecture PDFs into a **Filipino-style reviewer**: flashcards, multiple choice, **identification, enumeration, true or false, modified true or false**, each with a short explanation in **English, Filipino or Taglish** (default Taglish). Gemini runs **once per upload** via **Firebase AI Logic (Vertex AI Gemini API backend)**; afterwards, studying, grading and **FSRS** spaced repetition run **fully offline** from a local **Drift (SQLite)** database. Inspired by Gizmo, but built for Filipino students.

## History (why things are the way they are)
1. Study Buddy was first planned on **AWS** (React web app + SAM). He **can't use his AWS credits**, so it moved to **Google Cloud**.
2. He switched from web to **mobile** because he studies on his phone.
3. Research done in chat: Gizmo/Knowt/Quizlet do "your files → flashcards" but aren't made for Filipinos; Filipino apps (Super Tutor, Purrple Academy, CSC reviewers) only sell pre-made board-exam content. **Gap: your own lectures → Filipino-style reviewer, offline.**
4. Decisions from his answers:
   | Question | Answer |
   |---|---|
   | Users | **Just him first** (sideloaded APK, no Play Store) |
   | Framework | **Flutter** |
   | Offline | **Yes** — generate online, review offline |
   | v1 Filipino features | **Pinoy quiz formats + Taglish explanations** (exam-term planner and barkada battle deferred) |
   | Team | **Solo** |
5. A separate project, **Jeepney Commute Copilot** (ADK agent on Cloud Run), was also planned in the same chat. It has its own docs and is **not** part of this repo.

## Key architecture decisions (details + ADRs in architecture.md)
- **No backend server.** Gemini is called from the app through `firebase_ai`, protected by **App Check** (debug provider on his phone).
- **AI only at generation time** (`GeneratorService` is the only file that calls Gemini). Grading is **local Dart rules**, not AI.
- **One structured-output call per PDF**; prompt + JSON schema live in `assets/prompts/` and are **shared with the Python eval script**.
- **Single model** set in `lib/config.dart`: start with Gemini **Flash**; switch to **Flash-Lite** if evals are within 5 points.
- **Vertex AI backend, not the Gemini Developer API**, so credits apply and lecture files aren't used for training.
- **Evals are a deliverable** (`evals/run_eval.py`: grounding, type mix, duplicates, language, cost).
- Explicitly **not now**: Cloud Run backend, Firestore/Auth/sync, vector DB/RAG, on-device LLM, LangChain, React Native, gamified hearts/leaderboards.

## Current status
- **Nothing is built yet.** No Flutter project, Firebase project or repo exists.
- Docs ready: `CLAUDE.md`, `docs/architecture.md`, `docs/process.md`, `docs/steps.md`, `docs/handoff.md`.
- **Next step: Phase 0, Step 1** in `docs/steps.md` (install tools → run blank app on his phone → Firebase project on Blaze with budget alerts → AI Logic with Vertex AI → App Check → hello-world PDF summary).

## Things to verify (not confirmed in chat)
- **Exact Gemini model names** and current prices (Google changed both often in 2026). Check the Gemini/Vertex pricing page before writing `lib/config.dart`.
- **`firebase_ai` / `firebase_app_check` method names**: snippets in `steps.md` were not compiled. Check pub.dev; e.g., App Check activation and `responseSchema` vs a JSON-schema option may differ by version.
- Whether `firebase_ai` accepts a raw JSON schema; if not, write a small JSON → `Schema` converter (planned in Step 17).
- **`fsrs` package API** (v2.x on pub.dev, MIT). `dart_srs` is the fallback.
- Firebase AI Logic inline file size limit (plan assumes **20 MB**).

## How he likes to work
- Explain each step in plain language before/while doing it; he's learning Flutter and Firebase for the first time.
- Keep `docs/process.md` updated: add a dated line to the **Process Log** at the end of each work session, and fill in **Eval History** / **Cost Log**.
- Architecture changes → new ADR via `/planfirst`; **never edit old ADRs**.
- Prefer simple, readable code over clever abstractions.
- Budget-conscious: never leave anything that bills continuously.

## Suggested first message in Claude Code
```
Read docs/handoff.md, CLAUDE.md and docs/steps.md. We're starting Phase 0, Step 1.
Check what's installed on my machine (flutter doctor, node, uv), tell me what's
missing, and walk me through each step one at a time. Explain what each command
does. After each step, update the Process Log in docs/process.md.
```
