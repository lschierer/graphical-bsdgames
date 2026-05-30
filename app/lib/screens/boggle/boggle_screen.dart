import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:graphical_bsdgames/screens/boggle/boggle_game.dart';
import 'package:graphical_bsdgames/widgets/letter_tile.dart';

class BoggleScreen extends StatefulWidget {
  const BoggleScreen({super.key});

  @override
  State<BoggleScreen> createState() => _BoggleScreenState();
}

class _BoggleScreenState extends State<BoggleScreen> {
  Set<String>? _dictionary;
  BoggleGame? _game;
  List<int> _path = [];
  SubmitResult? _feedback;
  Timer? _gameTimer;
  Timer? _feedbackTimer;
  bool _panMoved = false;

  @override
  void initState() {
    super.initState();
    _loadDictionary();
  }

  @override
  void dispose() {
    _gameTimer?.cancel();
    _feedbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDictionary() async {
    final text = await rootBundle.loadString('assets/words/boggle_dict.txt');
    final dict = text.split('\n').where((w) => w.isNotEmpty).toSet();
    setState(() {
      _dictionary = dict;
      _game = BoggleGame(dict);
    });
    _startTimer();
  }

  void _startTimer() {
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final game = _game;
      if (game == null) return;
      setState(() => game.tick());
      if (game.status == BoggleStatus.gameOver) {
        _gameTimer?.cancel();
        WidgetsBinding.instance.addPostFrameCallback((_) => _showGameOver());
      }
    });
  }

  void _newGame() {
    _gameTimer?.cancel();
    setState(() {
      _game = BoggleGame(_dictionary!);
      _path = [];
      _feedback = null;
    });
    _startTimer();
  }

  // ── Gesture helpers ──────────────────────────────────────────────────────

  // Visible gap between tiles (matches the margin used in _buildGrid).
  static const _tileGap = 3.0;

  int _cellAt(Offset pos, double cellSize) {
    final col = (pos.dx / cellSize).floor();
    final row = (pos.dy / cellSize).floor();
    if (row < 0 || row >= BoggleGame.gridSize) return -1;
    if (col < 0 || col >= BoggleGame.gridSize) return -1;
    // Treat the gap margin as dead space — not inside any tile.
    final localX = pos.dx - col * cellSize;
    final localY = pos.dy - row * cellSize;
    const half = _tileGap / 2;
    if (localX < half || localX > cellSize - half) return -1;
    if (localY < half || localY > cellSize - half) return -1;
    return BoggleGame.cellIndex(row, col);
  }

  void _handlePanStart(DragStartDetails d, double cellSize) {
    final idx = _cellAt(d.localPosition, cellSize);
    if (idx < 0) return;
    setState(() {
      _path = [idx];
      _feedback = null;
      _panMoved = false;
    });
  }

  void _handlePanUpdate(DragUpdateDetails d, double cellSize) {
    if (_path.isEmpty) return;

    final pos = d.localPosition;
    final lastIdx = _path.last;
    final lastCenter = _cellCenter(lastIdx, cellSize);
    final delta = pos - lastCenter;
    final dist = delta.distance;

    // Don't snap until the cursor has moved at least half a cell from the
    // current tile's center.  This prevents triggering while the pointer is
    // still physically inside the starting tile — which would happen with the
    // old proximity approach because diagonal neighbors are only ~1.41 cells
    // away and a corner position is already within 0.75 of their centers.
    if (dist < cellSize * 0.5) return;

    // Quantise the movement angle to the nearest 45° to get one of 8 grid
    // directions, then resolve to a (dr, dc) step.
    final angle = atan2(delta.dy, delta.dx);
    final snapped = (angle / (pi / 4)).round() * (pi / 4);
    final dc = cos(snapped).round(); // -1, 0, or 1
    final dr = sin(snapped).round(); // -1, 0, or 1

    final targetRow = BoggleGame.cellRow(lastIdx) + dr;
    final targetCol = BoggleGame.cellCol(lastIdx) + dc;

    if (targetRow < 0 || targetRow >= BoggleGame.gridSize) return;
    if (targetCol < 0 || targetCol >= BoggleGame.gridSize) return;

    final targetIdx = BoggleGame.cellIndex(targetRow, targetCol);

    if (_path.contains(targetIdx)) {
      // Direction points back to an earlier tile → truncate path to there.
      final pos_ = _path.indexOf(targetIdx);
      if (pos_ < _path.length - 1) {
        setState(() {
          _path = _path.sublist(0, pos_ + 1);
          _panMoved = true;
        });
      }
      return;
    }

    setState(() {
      _path.add(targetIdx);
      _panMoved = true;
    });
  }

  Offset _cellCenter(int idx, double cellSize) {
    final r = BoggleGame.cellRow(idx);
    final c = BoggleGame.cellCol(idx);
    return Offset((c + 0.5) * cellSize, (r + 0.5) * cellSize);
  }

  void _handlePanEnd(DragEndDetails _) {
    if (_panMoved) {
      _submit();
    }
    // If no movement it was a tap — keep the single-tile path so the user
    // can tap more tiles to build a word, then use Submit button.
  }

  void _handleTileTap(int idx) {
    final game = _game;
    if (game == null || game.status != BoggleStatus.playing) return;

    setState(() {
      _feedback = null;
      if (_path.isEmpty) {
        _path = [idx];
      } else if (_path.last == idx) {
        // Tap last tile again = backspace
        _path.removeLast();
      } else if (_path.contains(idx)) {
        // Tap an earlier tile = truncate path to that tile
        final pos = _path.indexOf(idx);
        _path = _path.sublist(0, pos + 1);
      } else if (game.areAdjacent(_path.last, idx)) {
        _path.add(idx);
      } else {
        // Not adjacent — start fresh
        _path = [idx];
      }
    });
  }

  void _submit() {
    final game = _game;
    if (game == null || _path.isEmpty) return;
    final result = game.submit(_path);
    setState(() {
      _feedback = result;
      _path = [];
    });
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  void _clear() {
    setState(() {
      _path = [];
      _feedback = null;
    });
  }

  void _showGameOver() {
    final game = _game;
    if (game == null || !mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Time\'s up!'),
        content: Text(
          'Score: ${game.score} points\n'
          '${game.foundWords.length} word${game.foundWords.length == 1 ? "" : "s"} found',
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

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final game = _game;
    if (game == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Boggle'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                game.timerDisplay,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: game.secondsLeft <= 30
                      ? Colors.redAccent
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '${game.score} pts',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'New game',
            onPressed: _newGame,
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;
        return isWide
            ? _buildWide(game, constraints)
            : _buildNarrow(game, constraints);
      }),
    );
  }

  Widget _buildNarrow(BoggleGame game, BoxConstraints constraints) {
    final gridSize = constraints.maxWidth.clamp(0.0, 400.0);
    final cellSize = gridSize / BoggleGame.gridSize;
    return Column(
      children: [
        const SizedBox(height: 8),
        _buildCurrentWord(game),
        const SizedBox(height: 4),
        _buildFeedback(),
        const SizedBox(height: 8),
        _buildGrid(game, gridSize, cellSize),
        const SizedBox(height: 8),
        _buildButtons(game),
        const SizedBox(height: 8),
        Expanded(child: _buildFoundWords(game)),
      ],
    );
  }

  Widget _buildWide(BoggleGame game, BoxConstraints constraints) {
    final gridSize = (constraints.maxHeight - 80).clamp(0.0, constraints.maxWidth * 0.55);
    final cellSize = gridSize / BoggleGame.gridSize;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCurrentWord(game),
              const SizedBox(height: 4),
              _buildFeedback(),
              const SizedBox(height: 8),
              _buildGrid(game, gridSize, cellSize),
              const SizedBox(height: 8),
              _buildButtons(game),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
            child: _buildFoundWords(game),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentWord(BoggleGame game) {
    final word = game.pathToWord(_path).toUpperCase();
    return SizedBox(
      height: 40,
      child: Center(
        child: Text(
          word.isEmpty ? '—' : word,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: word.isEmpty
                ? Theme.of(context).colorScheme.onSurface.withAlpha(80)
                : Theme.of(context).colorScheme.onSurface,
            letterSpacing: 4,
          ),
        ),
      ),
    );
  }

  Widget _buildFeedback() {
    final msg = switch (_feedback) {
      SubmitResult.valid       => null, // word added to list — no inline message needed
      SubmitResult.tooShort    => 'Need at least 3 letters',
      SubmitResult.alreadyFound => 'Already found!',
      SubmitResult.notAWord    => 'Not a word',
      null                     => null,
    };
    final color = switch (_feedback) {
      SubmitResult.valid        => Colors.green,
      SubmitResult.alreadyFound => Colors.amber,
      _                         => Colors.redAccent,
    };
    return SizedBox(
      height: 18,
      child: msg == null
          ? null
          : Text(msg, style: TextStyle(color: color, fontSize: 13)),
    );
  }

  Widget _buildGrid(BoggleGame game, double gridSize, double cellSize) {
    return GestureDetector(
      onPanStart: (d) => _handlePanStart(d, cellSize),
      onPanUpdate: (d) => _handlePanUpdate(d, cellSize),
      onPanEnd: _handlePanEnd,
      child: SizedBox(
        width: gridSize,
        height: gridSize,
        child: Stack(
          children: [
            // Tile grid — each tile sits in a cellSize×cellSize slot with a
            // _tileGap/2 margin on each side, creating _tileGap of dead space
            // between adjacent tiles.  This gives the cursor/finger a gap to
            // pass through so diagonal vs orthogonal intent is clear.
            Column(
              children: List.generate(BoggleGame.gridSize, (row) {
                return Row(
                  children: List.generate(BoggleGame.gridSize, (col) {
                    final idx = BoggleGame.cellIndex(row, col);
                    final inPath = _path.contains(idx);
                    return SizedBox(
                      width: cellSize,
                      height: cellSize,
                      child: Center(
                        child: LetterTile(
                          letter: game.board[idx],
                          size: cellSize - _tileGap,
                          state: inPath ? LetterTileState.selected : LetterTileState.idle,
                          onTap: game.status == BoggleStatus.playing
                              ? () => _handleTileTap(idx)
                              : null,
                        ),
                      ),
                    );
                  }),
                );
              }),
            ),
            // Path connector overlay
            CustomPaint(
              size: Size(gridSize, gridSize),
              painter: _PathPainter(_path, cellSize),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButtons(BoggleGame game) {
    final playing = game.status == BoggleStatus.playing;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        OutlinedButton(
          onPressed: playing && _path.isNotEmpty ? _clear : null,
          child: const Text('Clear'),
        ),
        const SizedBox(width: 16),
        FilledButton(
          onPressed: playing && _path.length >= 2 ? _submit : null,
          child: const Text('Submit'),
        ),
      ],
    );
  }

  Widget _buildFoundWords(BoggleGame game) {
    // Sort: longest first, then alphabetical within same length
    final sorted = [...game.foundWords]
      ..sort((a, b) {
        final lenCmp = b.length.compareTo(a.length);
        return lenCmp != 0 ? lenCmp : a.compareTo(b);
      });

    if (sorted.isEmpty) {
      return Center(
        child: Text(
          'Found words will appear here',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withAlpha(80),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: sorted.map((word) {
          final pts = _game!.wordScore(word);
          return Chip(
            label: Text(
              '${word.toUpperCase()} +$pts',
              style: const TextStyle(fontSize: 12),
            ),
            backgroundColor:
                Theme.of(context).colorScheme.secondaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );
        }).toList(),
      ),
    );
  }
}

// Draws lines connecting the selected tiles in the current path
class _PathPainter extends CustomPainter {
  final List<int> path;
  final double cellSize;

  const _PathPainter(this.path, this.cellSize);

  @override
  void paint(Canvas canvas, Size size) {
    if (path.length < 2) return;
    final paint = Paint()
      ..color = const Color(0xFFFFB300).withAlpha(160)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final pts = path.map((idx) {
      final r = BoggleGame.cellRow(idx);
      final c = BoggleGame.cellCol(idx);
      return Offset((c + 0.5) * cellSize, (r + 0.5) * cellSize);
    }).toList();

    final pathObj = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      pathObj.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(pathObj, paint);

    // Dot on first tile (start indicator)
    canvas.drawCircle(pts.first, 6, Paint()..color = const Color(0xFFFF6F00));
  }

  @override
  bool shouldRepaint(_PathPainter old) => old.path != path || old.cellSize != cellSize;
}
