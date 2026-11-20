/// The six reviewer formats. `jsonName` is the value used in
/// assets/prompts/reviewer_schema.json and in the database.
enum QuestionType {
  flashcard('flashcard'),
  multipleChoice('multiple_choice'),
  identification('identification'),
  enumeration('enumeration'),
  trueFalse('true_false'),
  modifiedTrueFalse('modified_true_false');

  const QuestionType(this.jsonName);

  final String jsonName;

  /// Returns null for unknown names, so the parser can drop the item.
  static QuestionType? fromJsonName(String? name) {
    for (final type in values) {
      if (type.jsonName == name) return type;
    }
    return null;
  }
}

/// One validated reviewer question, ready to save or study.
class ReviewerItem {
  const ReviewerItem({
    required this.type,
    required this.sourcePage,
    required this.prompt,
    required this.answer,
    required this.explanation,
    required this.difficulty,
    this.choices = const [],
    this.acceptedAnswers = const [],
    this.items = const [],
    this.underlinedWord,
    this.correction,
  });

  final QuestionType type;
  final int sourcePage;
  final String prompt;

  /// flashcard: the back · multiple choice: the correct option ·
  /// identification: the term · enumeration: items joined with "; " ·
  /// true/false and modified true/false: "True" or "False".
  final String answer;

  final String explanation;

  /// "easy", "medium" or "hard".
  final String difficulty;

  /// Multiple choice only: exactly 4 options.
  final List<String> choices;

  /// Identification only: other correct spellings (e.g. an acronym).
  final List<String> acceptedAnswers;

  /// Enumeration only: each expected item.
  final List<String> items;

  /// Modified true/false only: the word shown underlined (ADR-007).
  final String? underlinedWord;

  /// Modified true/false only: the word that makes the statement true.
  /// When [answer] is "False", this is what the student must type.
  final String? correction;

  /// For true/false and modified true/false.
  bool get isTrue => answer == 'True';
}
