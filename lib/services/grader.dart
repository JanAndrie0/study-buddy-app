import '../models/reviewer_item.dart';

/// Offline answer checking for the Pinoy reviewer formats (ADR-004, ADR-007).
///
/// No AI here: grading must work in airplane mode. The rules are simple on
/// purpose so they're easy to test and tune.

/// The result of checking one answer.
class GradeResult {
  const GradeResult({required this.isCorrect, required this.score});

  final bool isCorrect;

  /// 0.0 to 1.0. Enumeration gives partial credit; modified true/false gives
  /// 0.5 for "False" with a wrong correction.
  final double score;
}

/// Lowercase, remove accents (á → a, ñ → n), turn punctuation into spaces,
/// collapse spaces and drop a leading "the", "a" or "an".
String normalizeAnswer(String text) {
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_accentMap[char] ?? char);
  }
  final words = buffer
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.length > 1 && const {'the', 'a', 'an'}.contains(words.first)) {
    words.removeAt(0);
  }
  return words.join(' ');
}

const _accentMap = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ñ': 'n', 'ç': 'c',
};

/// Number of single-letter edits (insert, delete, replace) between two strings.
int editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0);
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      current[j] = [
        previous[j] + 1, // delete
        current[j - 1] + 1, // insert
        previous[j - 1] + cost, // replace
      ].reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }
  return previous[b.length];
}

/// How many typos we forgive, based on the length of the expected answer.
/// Short answers must be exact ("DNA" vs "DNS" is a different thing).
int allowedTypos(int length) {
  if (length <= 4) return 0;
  if (length <= 8) return 1;
  if (length <= 15) return 2;
  return 3;
}

/// True if [input] matches [expected] after normalizing, allowing small typos.
/// Numbers must match exactly (1990 is not 1991).
bool isCloseMatch(String input, String expected) {
  final given = normalizeAnswer(input);
  final target = normalizeAnswer(expected);
  if (given.isEmpty || target.isEmpty) return false;
  if (given == target) return true;
  if (given.replaceAll(' ', '') == target.replaceAll(' ', '')) return true;

  final digits = RegExp(r'\d+');
  final givenNumbers = digits.allMatches(given).map((m) => m.group(0)).toList();
  final targetNumbers = digits.allMatches(target).map((m) => m.group(0)).toList();
  if (givenNumbers.join(',') != targetNumbers.join(',')) return false;

  return editDistance(given, target) <= allowedTypos(target.length);
}

GradeResult _result(bool correct) =>
    GradeResult(isCorrect: correct, score: correct ? 1.0 : 0.0);

/// Identification: the answer or any accepted alternative, with typo tolerance.
GradeResult gradeIdentification(String input, ReviewerItem item) {
  final options = [item.answer, ...item.acceptedAnswers];
  return _result(options.any((option) => isCloseMatch(input, option)));
}

/// Multiple choice: the tapped option must be the answer.
GradeResult gradeMultipleChoice(String selected, ReviewerItem item) =>
    _result(selected == item.answer);

/// True or false: the tapped button must match.
GradeResult gradeTrueFalse(bool pickedTrue, ReviewerItem item) =>
    _result(pickedTrue == item.isTrue);

/// Modified true or false, underline style (ADR-007).
/// True statement: picking True is correct.
/// False statement: picking False AND typing the correction is correct;
/// picking False with a wrong correction earns half credit.
GradeResult gradeModifiedTrueFalse(
  ReviewerItem item, {
  required bool pickedTrue,
  String correctionInput = '',
}) {
  if (item.isTrue) return _result(pickedTrue);
  if (pickedTrue) return _result(false);
  final fixed = isCloseMatch(correctionInput, item.correction ?? '');
  return GradeResult(isCorrect: fixed, score: fixed ? 1.0 : 0.5);
}

/// Enumeration: any order, each expected item counted once, partial credit.
GradeResult gradeEnumeration(List<String> inputs, ReviewerItem item) {
  final remaining = [...item.items];
  var matched = 0;
  for (final input in inputs) {
    final index = remaining.indexWhere((expected) => isCloseMatch(input, expected));
    if (index != -1) {
      remaining.removeAt(index);
      matched++;
    }
  }
  final total = item.items.length;
  final score = total == 0 ? 0.0 : matched / total;
  return GradeResult(isCorrect: matched == total && total > 0, score: score);
}
