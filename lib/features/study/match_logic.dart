import 'dart:math';

import '../../widgets/rich_terms.dart';

/// One tile in the Match game: either a term or its meaning.
class MatchTile {
  const MatchTile({required this.pairId, required this.text, required this.isTerm});
  final int pairId;
  final String text;
  final bool isTerm;
}

/// Short version of a flashcard meaning so tiles stay readable.
String shortMeaning(String text, {int max = 90}) {
  final plain = stripBoldMarkers(text).trim();
  return plain.length <= max ? plain : '${plain.substring(0, max).trimRight()}…';
}

/// Picks up to [maxPairs] random (term, meaning) pairs and returns their
/// tiles shuffled. Pure, so it's unit-tested.
List<MatchTile> buildMatchTiles(List<(String, String)> pairs, {Random? random, int maxPairs = 6}) {
  final rng = random ?? Random();
  final picked = [...pairs]..shuffle(rng);
  final tiles = <MatchTile>[
    for (var i = 0; i < picked.length && i < maxPairs; i++) ...[
      MatchTile(pairId: i, text: stripBoldMarkers(picked[i].$1), isTerm: true),
      MatchTile(pairId: i, text: shortMeaning(picked[i].$2), isTerm: false),
    ],
  ];
  return tiles..shuffle(rng);
}

/// A term and its own meaning.
bool isMatch(MatchTile a, MatchTile b) => a.pairId == b.pairId && a.isTerm != b.isTerm;
