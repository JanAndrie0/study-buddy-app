/// App-wide settings for Study Buddy.
///
/// CLAUDE.md rule: the Gemini model name lives in exactly ONE place: here.
/// To switch models (e.g. to Flash-Lite after Phase 1 evals), change it here only.
class AppConfig {
  /// Gemini model used for generation.
  /// Checked 2026-11-20: stable, no shutdown date on the Agent Platform API.
  /// Candidate to compare in Phase 1 evals: 'gemini-3.5-flash-lite'.
  static const String geminiModel = 'gemini-3.8-flash';

  /// Agent Platform (formerly Vertex AI) location. 'global' is the SDK default.
  static const String geminiLocation = 'global';

  /// Hard cap on how much text Gemini may write back (and bill us for).
  /// Thinking tokens also bill as output; a summary needs far less than this.
  static const int maxOutputTokens = 4096;

  /// Firebase AI Logic rejects requests over 20 MB in total. The PDF is sent
  /// base64-encoded, which makes it ~33% bigger, so we cap the raw file at
  /// 15 MB to stay under that limit.
  static const int maxPdfBytes = 15 * 1024 * 1024;
}
