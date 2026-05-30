import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:graphical_bsdgames/screens/hangman/hangman_game.dart';
import 'package:graphical_bsdgames/screens/hangman/hangman_painter.dart';
import 'package:graphical_bsdgames/widgets/letter_tile.dart';

class HangmanScreen extends StatefulWidget {
  const HangmanScreen({super.key});

  @override
  State<HangmanScreen> createState() => _HangmanScreenState();
}

class _HangmanScreenState extends State<HangmanScreen> {
  List<String> _words = [];
  HangmanGame? _game;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadWords();
  }

  Future<void> _loadWords() async {
    final raw = await rootBundle.loadString('assets/words/hangman_words.txt');
    _words = raw.split('\n').where((w) => w.trim().isNotEmpty).toList();
    _newGame();
  }

  void _newGame() {
    setState(() {
      _game = HangmanGame.fromWordList(_words);
      _loading = false;
    });
  }

  void _guess(String letter) {
    final game = _game;
    if (game == null) return;
    setState(() => game.guess(letter));
    if (game.status != HangmanStatus.playing) {
      _showEndDialog(game);
    }
  }

  void _showEndDialog(HangmanGame game) {
    final won = game.status == HangmanStatus.won;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(won ? 'You won!' : 'Game over'),
        content: Text(
          won
              ? 'You guessed "${game.word}" with ${game.errors} wrong guess${game.errors == 1 ? "" : "es"}.'
              : 'The word was "${game.word}".',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _newGame();
            },
            child: const Text('Play again'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Main menu'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final game = _game!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hangman'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'New game',
            onPressed: _newGame,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 600;
          return isWide
              ? _WideLayout(game: game, onGuess: _guess)
              : _NarrowLayout(game: game, onGuess: _guess);
        },
      ),
    );
  }
}

// ── Narrow (portrait phone) layout ──────────────────────────────────────────

class _NarrowLayout extends StatelessWidget {
  final HangmanGame game;
  final ValueChanged<String> onGuess;

  const _NarrowLayout({required this.game, required this.onGuess});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: 4,
          child: _GallowsSection(game: game),
        ),
        _WordDisplay(game: game),
        const SizedBox(height: 12),
        _Keyboard(game: game, onGuess: onGuess),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Wide (tablet / ChromeOS / landscape) layout ─────────────────────────────

class _WideLayout extends StatelessWidget {
  final HangmanGame game;
  final ValueChanged<String> onGuess;

  const _WideLayout({required this.game, required this.onGuess});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _GallowsSection(game: game)),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _WordDisplay(game: game),
              const SizedBox(height: 24),
              _Keyboard(game: game, onGuess: onGuess),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Gallows ──────────────────────────────────────────────────────────────────

class _GallowsSection extends StatelessWidget {
  final HangmanGame game;

  const _GallowsSection({required this.game});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Expanded(
            child: CustomPaint(
              painter: HangmanPainter(game.errors),
              child: const SizedBox.expand(),
            ),
          ),
          Text(
            '${game.errors} / ${HangmanGame.maxErrors} wrong',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ── Word display ─────────────────────────────────────────────────────────────

class _WordDisplay extends StatelessWidget {
  final HangmanGame game;

  const _WordDisplay({required this.game});

  @override
  Widget build(BuildContext context) {
    final revealed = game.revealed;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: revealed.map((ch) {
          return LetterTile(
            letter: ch ?? ' ',
            state: ch != null ? LetterTileState.correct : LetterTileState.idle,
            size: 44,
          );
        }).toList(),
      ),
    );
  }
}

// ── QWERTY keyboard ──────────────────────────────────────────────────────────

const _qwertyRows = [
  ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
  ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
  ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
];

class _Keyboard extends StatelessWidget {
  final HangmanGame game;
  final ValueChanged<String> onGuess;

  const _Keyboard({required this.game, required this.onGuess});

  @override
  Widget build(BuildContext context) {
    final guessed = game.guessed;
    final playing = game.status == HangmanStatus.playing;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _qwertyRows.map((row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: row.map((letter) {
                final wasGuessed = guessed.contains(letter);
                final isCorrect = wasGuessed && game.word.contains(letter);
                final isWrong = wasGuessed && !game.word.contains(letter);

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: LetterTile(
                    letter: letter,
                    size: 36,
                    state: isCorrect
                        ? LetterTileState.correct
                        : isWrong
                            ? LetterTileState.wrong
                            : LetterTileState.idle,
                    onTap: playing && !wasGuessed ? () => onGuess(letter) : null,
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }
}
