import 'dart:convert';

import '../models/reviewer_item.dart';
import 'grader.dart' show normalizeAnswer;

/// What came out of one Gemini response.
class ParseResult {
  const ParseResult({
    this.error,
    this.deckTitle = '',
    this.subject = '',
    this.explanationLanguage = 'taglish',
    this.items = const [],
    this.dropped = const [],
  });

  /// Set when the whole response is unusable (e.g. not JSON at all).
  final String? error;

  final String deckTitle;
  final String subject;
  final String explanationLanguage;

  /// Items that passed every rule.
  final List<ReviewerItem> items;

  /// One short reason per item we threw away, e.g. "#3 multiple_choice: 3 choices".
  final List<String> dropped;

  bool get isUsable => error == null && items.isNotEmpty;
}

/// Turns Gemini's JSON into validated [ReviewerItem]s.
///
/// CLAUDE.md: never crash on bad model output. Broken items are dropped one
/// by one (ADR-003) and the rules match `item_problems()` in
/// evals/run_eval.py, so the eval score predicts what the app keeps.
class ReviewerParser {
  /// The schema can't limit the list length (Gemini rejects `maxItems`
  /// there), so we cap it here.
  static const maxItems = 60;

  static const _languages = {'english', 'filipino', 'taglish'};
  static const _difficulties = {'easy', 'medium', 'hard'};

  /// [pageCount] is the PDF's page count; `source_page` must be within it.
  static ParseResult parse(String jsonText, {required int pageCount}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException catch (e) {
      return ParseResult(error: 'Not valid JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      return const ParseResult(error: 'Expected a JSON object');
    }
    final rawQuestions = decoded['questions'];
    if (rawQuestions is! List) {
      return const ParseResult(error: 'Missing "questions" list');
    }

    final items = <ReviewerItem>[];
    final dropped = <String>[];
    final seenPrompts = <String>{};

    for (var i = 0; i < rawQuestions.length; i++) {
      final raw = rawQuestions[i];
      final label = '#${i + 1} ${raw is Map ? raw['type'] : '?'}';
      if (items.length >= maxItems) {
        dropped.add('$label: over the $maxItems-item limit');
        continue;
      }
      if (raw is! Map<String, dynamic>) {
        dropped.add('$label: not an object');
        continue;
      }
      final problem = _problemWith(raw, pageCount);
      if (problem != null) {
        dropped.add('$label: $problem');
        continue;
      }
      final item = _toItem(raw);
      if (!seenPrompts.add(normalizeAnswer(item.prompt))) {
        dropped.add('$label: duplicate prompt');
        continue;
      }
      items.add(item);
    }

    final language = _string(decoded['explanation_language']);
    return ParseResult(
      deckTitle: _string(decoded['deck_title']),
      subject: _string(decoded['subject']),
      explanationLanguage: _languages.contains(language) ? language : 'taglish',
      items: items,
      dropped: dropped,
    );
  }

  /// Returns why this item is broken, or null if it's fine.
  static String? _problemWith(Map<String, dynamic> q, int pageCount) {
    final type = QuestionType.fromJsonName(q['type'] as String?);
    if (type == null) return 'unknown type';
    for (final field in ['prompt', 'answer', 'explanation']) {
      if (_string(q[field]).isEmpty) return 'empty $field';
    }
    final page = q['source_page'];
    if (page is! int || page < 1 || page > pageCount) {
      return 'source_page $page outside 1..$pageCount';
    }
    final prompt = _string(q['prompt']);
    final answer = _string(q['answer']);

    switch (type) {
      case QuestionType.multipleChoice:
        final choices = _stringList(q['choices']);
        if (choices.length != 4) return '${choices.length} choices';
        if (!choices.contains(answer)) return 'answer not in choices';
        if (choices.map(normalizeAnswer).toSet().length != 4) return 'duplicate choices';
      case QuestionType.enumeration:
        if (_stringList(q['items']).length < 2) return 'fewer than 2 items';
      case QuestionType.trueFalse:
        if (answer != 'True' && answer != 'False') return 'answer is not True/False';
      case QuestionType.modifiedTrueFalse:
        if (answer != 'True' && answer != 'False') return 'answer is not True/False';
        final underlined = _string(q['underlined_word']);
        // Case-insensitive: the app can underline "Spur" inside "spur" (ADR-007).
        if (underlined.isEmpty || !prompt.toLowerCase().contains(underlined.toLowerCase())) {
          return 'underlined_word not in prompt';
        }
        if (answer == 'False') {
          final correction = _string(q['correction']);
          if (correction.isEmpty) return 'False but no correction';
          if (normalizeAnswer(correction) == normalizeAnswer(underlined)) {
            return 'correction same as underlined_word';
          }
        }
      case QuestionType.identification:
        final term = normalizeAnswer(answer);
        if (RegExp('\\b${RegExp.escape(term)}\\b').hasMatch(normalizeAnswer(prompt))) {
          return 'answer appears in prompt';
        }
      case QuestionType.flashcard:
        break;
    }
    return null;
  }

  static ReviewerItem _toItem(Map<String, dynamic> q) {
    final type = QuestionType.fromJsonName(q['type'] as String?)!;
    final difficulty = _string(q['difficulty']);
    final isModified = type == QuestionType.modifiedTrueFalse;
    return ReviewerItem(
      type: type,
      sourcePage: q['source_page'] as int,
      prompt: _string(q['prompt']),
      answer: _string(q['answer']),
      explanation: _string(q['explanation']),
      difficulty: _difficulties.contains(difficulty) ? difficulty : 'medium',
      choices: type == QuestionType.multipleChoice ? _stringList(q['choices']) : const [],
      acceptedAnswers:
          type == QuestionType.identification ? _stringList(q['accepted_answers']) : const [],
      items: type == QuestionType.enumeration ? _stringList(q['items']) : const [],
      underlinedWord: isModified ? _string(q['underlined_word']) : null,
      correction: isModified ? _string(q['correction']) : null,
    );
  }

  static String _string(Object? value) => value is String ? value.trim() : '';

  static List<String> _stringList(Object? value) => value is List
      ? value.whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
      : const [];
}
