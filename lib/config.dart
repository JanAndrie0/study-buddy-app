/// App-wide settings for Study Buddy.
///
/// CLAUDE.md rule: the Gemini model name lives in exactly ONE place: here.
/// To switch models (e.g. to Flash-Lite after Phase 1 evals), change it here only.
class AppConfig {
  /// Gemini model used for generation.
  /// Chosen 2026-11-20 by the Phase 1 evals (9 PDFs, Taglish, prompt/schema v3):
  /// gemini-3.5-flash-lite 97.6% at $0.0084/deck and ~14 s, vs
  /// gemini-3.8-flash 97.9% at $0.0269/deck and ~58 s. Within 5 points, so
  /// the cheaper, faster model wins (the plan's rule). Both are stable with no
  /// shutdown date on the Agent Platform API.
  static const String geminiModel = 'gemini-3.5-flash-lite';

  /// Agent Platform (formerly Vertex AI) location. 'global' is the SDK default.
  static const String geminiLocation = 'global';

  /// Hard cap on how much text Gemini may write back (and bill us for).
  /// Thinking tokens also bill as output. In the evals the biggest Flash-Lite
  /// deck (31 questions) used 3,335 output + thinking tokens, so 8192 leaves
  /// room for a 40-question deck without letting a runaway response cost much.
  static const int maxOutputTokens = 8192;

  /// How many questions to ask Gemini for: about 0.8 per page, 10 to 40.
  /// Must match target_questions() in evals/run_eval.py.
  static const double questionsPerPage = 0.8;
  static const int minQuestions = 10;
  static const int maxQuestions = 40;

  /// Firebase AI Logic rejects requests over 20 MB in total. The PDF is sent
  /// base64-encoded, which makes it ~33% bigger, so we cap the raw file at
  /// 15 MB to stay under that limit.
  static const int maxPdfBytes = 15 * 1024 * 1024;
}
