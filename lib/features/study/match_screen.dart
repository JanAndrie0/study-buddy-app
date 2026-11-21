import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:flutter/services.dart' show HapticFeedback;

import '../../providers.dart';
import '../../theme.dart';
import 'match_logic.dart';

/// Match (design feedback #4): tap a term, then its meaning, against the
/// clock. Built from the deck's flashcards; offline; nothing is saved.
class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key, required this.deckId});

  final int deckId;

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen> {
  List<(String, String)> _pairs = [];
  List<MatchTile> _tiles = [];
  final Set<int> _cleared = {}; // tile indexes already matched
  int? _selected;
  int? _wrongA;
  int? _wrongB;
  final _watch = Stopwatch();
  Timer? _ticker;
  Duration? _best;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final cards = await ref.read(databaseProvider).loadDeckCards(widget.deckId, types: const {'flashcard'});
    _pairs = [for (final c in cards) (c.question.prompt, c.question.answer)];
    _newGame();
  }

  void _newGame() {
    setState(() {
      _tiles = buildMatchTiles(_pairs);
      _cleared.clear();
      _selected = _wrongA = _wrongB = null;
      _loading = false;
    });
    _watch
      ..reset()
      ..start();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => setState(() {}));
  }

  void _tap(int index) {
    if (_cleared.contains(index) || _watch.isRunning == false) return;
    if (_selected == null || _selected == index) {
      setState(() => _selected = _selected == index ? null : index);
      return;
    }
    final first = _selected!;
    if (isMatch(_tiles[first], _tiles[index])) {
      HapticFeedback.lightImpact();
      setState(() {
        _cleared.addAll([first, index]);
        _selected = null;
      });
      if (_cleared.length == _tiles.length) {
        _watch.stop();
        _ticker?.cancel();
        setState(() {
          if (_best == null || _watch.elapsed < _best!) _best = _watch.elapsed;
        });
      }
    } else {
      HapticFeedback.mediumImpact();
      setState(() {
        _wrongA = first;
        _wrongB = index;
        _selected = null;
      });
      Future.delayed(const Duration(milliseconds: 450), () {
        if (mounted) setState(() => _wrongA = _wrongB = null);
      });
    }
  }

  String _time(Duration d) => '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finished = !_loading && _tiles.isNotEmpty && _cleared.length == _tiles.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Match'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text(_time(_watch.elapsed), style: theme.textTheme.titleMedium)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _pairs.length < 2
              ? const Center(child: Text('Kailangan ng at least 2 flashcards para sa Match.'))
              : finished
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.emoji_events_outlined, size: 64, color: theme.colorScheme.primary),
                            const SizedBox(height: 8),
                            Text('Galing!', style: theme.textTheme.headlineMedium),
                            const SizedBox(height: 8),
                            Text('Time: ${_time(_watch.elapsed)}', style: theme.textTheme.titleLarge),
                            if (_best != null) Text('Best this session: ${_time(_best!)}'),
                            const SizedBox(height: 24),
                            FilledButton(onPressed: _newGame, child: const Text('Play again')),
                            const SizedBox(height: 8),
                            OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
                          ],
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(12),
                      child: GridView.count(
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.25,
                        children: [
                          for (var i = 0; i < _tiles.length; i++)
                            AnimatedOpacity(
                              opacity: _cleared.contains(i) ? 0 : 1,
                              duration: motion(context, 250),
                              child: _MatchTileView(
                                tile: _tiles[i],
                                selected: _selected == i,
                                wrong: _wrongA == i || _wrongB == i,
                                onTap: () => _tap(i),
                              ),
                            ),
                        ],
                      ),
                    ),
    );
  }
}

class _MatchTileView extends StatelessWidget {
  const _MatchTileView({required this.tile, required this.selected, required this.wrong, required this.onTap});

  final MatchTile tile;
  final bool selected;
  final bool wrong;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = wrong ? scheme.error : (selected ? scheme.primary : scheme.outlineVariant);
    return Semantics(
      button: true,
      selected: selected,
      label: '${tile.isTerm ? 'Term' : 'Meaning'}: ${tile.text}${wrong ? '. Not a match' : ''}',
      excludeSemantics: true,
      child: Material(
      color: wrong ? scheme.errorContainer : (selected ? scheme.primaryContainer : Theme.of(context).cardTheme.color),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Stack(
            children: [
              Center(
                child: Text(
                  tile.text,
                  textAlign: TextAlign.center,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: tile.isTerm ? FontWeight.w800 : FontWeight.w400,
                    color: wrong ? scheme.onErrorContainer : null,
                  ),
                ),
              ),
              // Not colour alone: a wrong pair also shows an ✗.
              if (wrong) Positioned(top: 0, right: 0, child: Icon(Icons.close, size: 18, color: scheme.error)),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
