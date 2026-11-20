import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../config.dart';

/// What Gemini sent back, plus token counts so we can track cost.
class SummaryResult {
  const SummaryResult({
    required this.text,
    this.inputTokens,
    this.outputTokens,
    this.thinkingTokens,
  });

  final String text;
  final int? inputTokens;
  final int? outputTokens;
  final int? thinkingTokens;
}

/// The ONLY place in the app that talks to Gemini (CLAUDE.md rule).
///
/// Everything else (grading, scheduling, studying) must work offline,
/// so keeping all AI calls in this one class makes that easy to check.
class GeneratorService {
  /// The model is created lazily (`late`), on the first real request.
  /// That way, tests can build screens that use this service without
  /// starting Firebase or calling Gemini.
  late final GenerativeModel _model =
      FirebaseAI.agentPlatform(location: AppConfig.geminiLocation)
          .generativeModel(
            model: AppConfig.geminiModel,
            generationConfig: GenerationConfig(
              maxOutputTokens: AppConfig.maxOutputTokens,
            ),
          );

  /// Phase 0 hello-world: send a PDF and get a Taglish summary back.
  Future<SummaryResult> summarizePdf(Uint8List pdfBytes) async {
    // The prompt lives in assets/prompts/ so evals can share it (CLAUDE.md).
    final prompt = await rootBundle.loadString(
      'assets/prompts/hello_summary.md',
    );

    // One user message with two parts: our instructions + the PDF itself.
    final response = await _model.generateContent([
      Content.multi([
        TextPart(prompt),
        InlineDataPart('application/pdf', pdfBytes),
      ]),
    ]);

    final usage = response.usageMetadata;
    return SummaryResult(
      text: response.text ?? '(Walang sagot si Gemini. The response was empty.)',
      inputTokens: usage?.promptTokenCount,
      outputTokens: usage?.candidatesTokenCount,
      thinkingTokens: usage?.thoughtsTokenCount,
    );
  }
}
