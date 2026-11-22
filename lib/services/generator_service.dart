import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/generation_options.dart';

/// What we send: the PDF plus the student's choices that fill the prompt.
class GenerationRequest {
  const GenerationRequest({
    required this.pdfBytes,
    required this.pageCount,
    required this.fileHash,
    required this.options,
  });

  final Uint8List pdfBytes;
  final int pageCount;
  final String fileHash;
  final GenerationOptions options;
}

/// Fills the prompt template's placeholders. Pure, so it's unit-tested, and
/// `fill_prompt()` in evals/run_eval.py does exactly the same.
String fillPromptTemplate({
  required String template,
  required String mixJson,
  required GenerationOptions options,
  required int pageCount,
}) {
  final mix = options.targetMix(parseQuestionMix(mixJson));
  final table = mix.isEmpty
      ? '(No quiz questions requested.)'
      : [
          '| type | share |',
          '|---|---|',
          for (final entry in mix.entries)
            '| ${entry.key.jsonName} | ${(entry.value * 100).round()}%'
                '${entry.key.jsonName == 'enumeration' ? ' (only if the PDF has real lists)' : ''} |',
        ].join('\n');
  final notes = options.notes
      ? 'requested. Write key points by topic (section 5).'
      : 'not requested. Set `notes` to an empty list.';
  final flashcards = options.flashcards
      ? 'requested. List every key term in `key_terms`, then make one `flashcard` for each (section 3), '
          'in addition to the quiz questions.'
      : 'not requested. Set `key_terms` to an empty list and do not write any `flashcard` items.';
  return template
      .replaceAll('{{explanation_language}}', options.language)
      .replaceAll('{{target_questions}}', options.targetQuestions(pageCount).toString())
      .replaceAll('{{question_mix}}', table)
      .replaceAll('{{flashcard_instruction}}', flashcards)
      .replaceAll('{{notes_instruction}}', notes);
}

/// Gemini's raw JSON text plus token counts (for the Cost Log).
class GenerationOutput {
  const GenerationOutput({
    required this.jsonText,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.thinkingTokens = 0,
    this.fromCache = false,
  });

  final String jsonText;
  final int inputTokens;
  final int outputTokens;
  final int thinkingTokens;

  /// True when a debug build reused an earlier response (no API call, no cost).
  final bool fromCache;
}

/// A problem the student can understand, and whether Retry might help.
class GenerationException implements Exception {
  const GenerationException(this.message, {this.canRetry = true});
  final String message;
  final bool canRetry;
  @override
  String toString() => message;
}

/// Anything that can turn a PDF into reviewer JSON. Tests use a fake.
abstract class ReviewerGenerator {
  Future<GenerationOutput> generate(GenerationRequest request);
}

/// The ONLY place in the app that talks to Gemini (CLAUDE.md rule).
///
/// Loads the prompt + schema from assets/prompts/ (shared with the evals,
/// ADR-006), sends one structured-output request (ADR-003) and returns the
/// raw JSON. Parsing and saving happen elsewhere, offline.
class GeneratorService implements ReviewerGenerator {
  static const _promptAsset = 'assets/prompts/generate_reviewer.md';
  static const _schemaAsset = 'assets/prompts/reviewer_schema.json';
  static const _mixAsset = 'assets/prompts/question_mix.json';

  @override
  Future<GenerationOutput> generate(GenerationRequest request) async {
    final schemaText = await rootBundle.loadString(_schemaAsset);
    final prompt = fillPromptTemplate(
      template: await rootBundle.loadString(_promptAsset),
      mixJson: await rootBundle.loadString(_mixAsset),
      options: request.options,
      pageCount: request.pageCount,
    );

    // Debug builds only: reuse the last response for the same PDF + prompt +
    // schema + model, so testing the app over and over doesn't re-bill.
    final cacheKey = sha256
        .convert(utf8.encode('${request.fileHash}|$prompt|$schemaText|${AppConfig.geminiModel}'))
        .toString();
    final cached = kDebugMode ? await _readCache(cacheKey) : null;
    if (cached != null) return GenerationOutput(jsonText: cached, fromCache: true);

    final model = FirebaseAI.agentPlatform(location: AppConfig.geminiLocation).generativeModel(
      model: AppConfig.geminiModel,
      generationConfig: GenerationConfig(
        maxOutputTokens: AppConfig.maxOutputTokens,
        responseMimeType: 'application/json',
        responseJsonSchema: jsonDecode(schemaText) as Map<String, Object?>,
      ),
    );

    final GenerateContentResponse response;
    try {
      response = await model.generateContent([
        Content.multi([
          InlineDataPart('application/pdf', request.pdfBytes),
          TextPart(prompt),
        ]),
      ]).timeout(AppConfig.generationTimeout);
    } on TimeoutException {
      throw const GenerationException(
        'Ang tagal sumagot ni Gemini. Check your internet, then try again.',
      );
    } catch (e) {
      throw _friendly(e);
    }

    final text = response.text;
    if (text == null || text.trim().isEmpty) {
      throw const GenerationException('Walang sagot si Gemini. Try again.');
    }
    if (kDebugMode) await _writeCache(cacheKey, text);

    final usage = response.usageMetadata;
    return GenerationOutput(
      jsonText: text,
      inputTokens: usage?.promptTokenCount ?? 0,
      outputTokens: usage?.candidatesTokenCount ?? 0,
      thinkingTokens: usage?.thoughtsTokenCount ?? 0,
    );
  }

  /// Turns SDK and network errors into messages a student understands.
  GenerationException _friendly(Object error) {
    final text = error.toString();
    if (error is SocketException ||
        text.contains('SocketException') ||
        text.contains('Failed host lookup') ||
        text.contains('ClientException')) {
      return const GenerationException(
        'Walang internet. Kailangan ng internet para gumawa ng reviewer; '
        'pag tapos na, offline na pwedeng mag-review.',
      );
    }
    if (text.contains('App Check') || text.contains('403') || text.contains('PERMISSION_DENIED')) {
      return const GenerationException(
        'Hindi ma-verify ang app (App Check). Kung debug build ito, '
        'i-register ang debug token sa Firebase console.',
        canRetry: false,
      );
    }
    if (text.contains('429') || text.contains('RESOURCE_EXHAUSTED') || text.contains('quota')) {
      return const GenerationException('Busy si Gemini ngayon. Try again in a minute.');
    }
    return GenerationException('May error kay Gemini: ${text.length > 160 ? text.substring(0, 160) : text}');
  }

  Future<File> _cacheFile(String key) async {
    final dir = await getApplicationCacheDirectory();
    return File('${dir.path}/generation_cache/$key.json');
  }

  Future<String?> _readCache(String key) async {
    try {
      final file = await _cacheFile(key);
      return await file.exists() ? await file.readAsString() : null;
    } catch (_) {
      return null; // a cache problem should never block generation
    }
  }

  Future<void> _writeCache(String key, String text) async {
    try {
      final file = await _cacheFile(key);
      await file.parent.create(recursive: true);
      await file.writeAsString(text);
    } catch (_) {}
  }
}
