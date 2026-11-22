import 'dart:convert';

import '../models/reviewer_item.dart';
import 'grader.dart' show isCloseMatch, normalizeAnswer;

/// What came out of one Gemini response.
class ParseResult {
  const ParseResult({
    this.error,
    this.deckTitle = '',
    this.subject = '',
    this.explanationLanguage = 'english',
    this.items = const [],
    this.notes = const [],
    this.dropped = const [],
  });

  /// Set when the whole response is unusable (e.g. not JSON at all).
  final String? error;

  final String deckTitle;
  final String subject;
  final String explanationLanguage;

  /// Items that passed every rule.
  final List<ReviewerItem> items;

  /// Valid note sections (key points by topic), in lecture order.
  final List<NoteSection> notes;

  /// One short reason per item we threw away, e.g. "#3 multiple_choice: 3 choices".
  final List<String> dropped;

  bool get isUsable => error == null && (items.isNotEmpty || notes.isNotEmpty);
}

/// Turns Gemini's JSON into validated [ReviewerItem]s.
///
/// CLAUDE.md: never crash on bad model output. Broken items are dropped one
/// by one (ADR-003) and the rules match `item_problems()` in
/// evals/run_eval.py, so the eval score predicts what the app keeps.
class ReviewerParser {
  /// The schema can't limit the list length (Gemini rejects `maxItems`
  /// there), so we cap it here: up to 40 quiz questions + up to 60
  /// flashcards (one per key term, ADR-010).
  static const maxItems = 100;

  static const _languages = {'english', 'filipino', 'taglish'};
  static const _difficulties = {'easy', 'medium', 'hard'};

  /// [pageCount] is the PDF's page count; `source_page` must be within it.
  /// [allowedTypes] are the types the student asked for (null = all);
  /// anything else is dropped.
  /// [fillMissingFlashcards]: when flashcards were requested, every term
  /// bolded in the notes that still has no flashcard gets one built from its
  /// note (ADR-010). Offline; no extra Gemini call.
  static ParseResult parse(
    String jsonText, {
    required int pageCount,
    Set<QuestionType>? allowedTypes,
    bool fillMissingFlashcards = false,
  }) {
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
    final rawNotes = decoded['notes'];
    if (rawQuestions is! List && rawNotes is! List) {
      return const ParseResult(error: 'Missing "questions" and "notes" lists');
    }

    final items = <ReviewerItem>[];
    final dropped = <String>[];
    final seenPrompts = <String>{};
    final questionList = rawQuestions is List ? rawQuestions : const [];

    for (var i = 0; i < questionList.length; i++) {
      final raw = questionList[i];
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
      final type = QuestionType.fromJsonName(raw['type'] as String?);
      if (allowedTypes != null && !allowedTypes.contains(type)) {
        dropped.add('$label: type not requested');
        continue;
      }
      final item = _toItem(raw);
      if (!seenPrompts.add(normalizeAnswer(item.prompt))) {
        dropped.add('$label: duplicate prompt');
        continue;
      }
      items.add(item);
    }

    final notes = <NoteSection>[];
    final noteList = rawNotes is List ? rawNotes : const [];
    for (var i = 0; i < noteList.length; i++) {
      final raw = noteList[i];
      final label = 'note #${i + 1}';
      if (raw is! Map<String, dynamic>) {
        dropped.add('$label: not an object');
        continue;
      }
      final heading = _string(raw['heading']);
      final points = _stringList(raw['points']);
      final page = raw['source_page'];
      if (heading.isEmpty) {
        dropped.add('$label: empty heading');
      } else if (points.isEmpty) {
        dropped.add('$label: no points');
      } else if (page is! int || page < 1 || page > pageCount) {
        dropped.add('$label: source_page $page outside 1..$pageCount');
      } else {
        notes.add(NoteSection(heading: heading, points: points, sourcePage: page));
      }
    }

    if (fillMissingFlashcards) {
      for (final card in flashcardsFromNotes(notes, items)) {
        if (items.length >= maxItems) break;
        if (seenPrompts.add(normalizeAnswer(card.prompt))) items.add(card);
      }
    }

    final language = _string(decoded['explanation_language']);
    return ParseResult(
      deckTitle: _string(decoded['deck_title']),
      subject: _string(decoded['subject']),
      explanationLanguage: _languages.contains(language) ? language : 'english',
      items: items,
      notes: notes,
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

  static final _boldTerm = RegExp(r'\*\*(.+?)\*\*');

  /// ADR-010 safety net: key terms bolded in the notes that have no flashcard
  /// in [existing] yet, as flashcards built from the note itself. Front: the
  /// term. Back: the note point that explains it (bold markers kept, so the
  /// term shows in bold). Skips numbers, comma lists and long phrases, which
  /// are not terms.
  static List<ReviewerItem> flashcardsFromNotes(List<NoteSection> notes, List<ReviewerItem> existing) {
    final covered = [
      for (final item in existing)
        if (item.type == QuestionType.flashcard) normalizeAnswer(item.prompt),
    ];
    bool hasCard(String term) => covered.any((card) =>
        card == term ||
        card.contains(term) ||
        (card.length >= 4 && term.contains(card)) ||
        isCloseMatch(term, card));

    final cards = <ReviewerItem>[];
    for (final section in notes) {
      for (final point in section.points) {
        for (final match in _boldTerm.allMatches(point)) {
          final term = match.group(1)!.trim();
          final key = normalizeAnswer(term);
          final notATerm = key.length < 3 ||
              RegExp(r'\d').hasMatch(term) ||
              term.contains(',') ||
              key.split(' ').length > 5;
          if (notATerm || hasCard(key)) continue;
          covered.add(key);
          cards.add(ReviewerItem(
            type: QuestionType.flashcard,
            sourcePage: section.sourcePage,
            prompt: term[0].toUpperCase() + term.substring(1),
            answer: point,
            explanation: '',
            difficulty: 'easy',
          ));
        }
      }
    }
    return cards;
  }

  static String _string(Object? value) => value is String ? value.trim() : '';

  static List<String> _stringList(Object? value) => value is List
      ? value.whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
      : const [];
}
