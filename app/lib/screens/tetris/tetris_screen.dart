import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:graphical_bsdgames/screens/tetris/tetris_game.dart';
import 'package:graphical_bsdgames/screens/tetris/tetris_painter.dart';

class TetrisScreen extends StatefulWidget {
  const TetrisScreen({super.key});

  @override
  State<TetrisScreen> createState() => _TetrisScreenState();
}

class _TetrisScreenState extends State<TetrisScreen> {
  late TetrisGame _game;
  Timer? _timer;
  final _focusNode = FocusNode();

  // Swipe tracking
  Offset? _dragStart;
  static const _swipeThreshold = 20.0;

  @override
  void initState() {
    super.initState();
    _startNewGame();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _startNewGame() {
    _timer?.cancel();
    _game = TetrisGame();
    _scheduleTimer();
    _focusNode.requestFocus();
  }

  void _scheduleTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(milliseconds: _game.tickMs), (_) {
      if (!mounted) return;
      final oldLevel = _game.level;
      setState(() => _game.tick());
      if (_game.level != oldLevel) _scheduleTimer(); // speed up
      if (_game.status == TetrisStatus.gameOver) {
        _timer?.cancel();
        _showGameOver();
      }
    });
  }

  void _showGameOver() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Game Over'),
        content: Text(
          'Score: ${_game.score}\nLevel: ${_game.level}\nLines: ${_game.linesCleared}',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(_startNewGame);
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

  // ── Keyboard handling (macOS / physical keyboard) ──────────────────────────

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    setState(() {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowLeft:
          _game.moveLeft();
        case LogicalKeyboardKey.arrowRight:
          _game.moveRight();
        case LogicalKeyboardKey.arrowDown:
          _game.softDrop();
        case LogicalKeyboardKey.arrowUp:
        case LogicalKeyboardKey.keyZ:
          _game.rotate();
        case LogicalKeyboardKey.space:
          _game.hardDrop();
          if (_game.status == TetrisStatus.gameOver) {
            _timer?.cancel();
            _showGameOver();
          }
        case LogicalKeyboardKey.keyP:
          _game.togglePause();
          if (_game.status == TetrisStatus.playing) _scheduleTimer();
          else _timer?.cancel();
        default:
          return;
      }
    });
    return KeyEventResult.handled;
  }

  // ── Touch gesture helpers ─────────────────────────────────────────────────

  void _onDragStart(DragStartDetails d) => _dragStart = d.localPosition;

  void _onDragUpdate(DragUpdateDetails d) {
    final start = _dragStart;
    if (start == null) return;
    final dx = d.localPosition.dx - start.dx;
    final dy = d.localPosition.dy - start.dy;

    if (dx.abs() > _swipeThreshold && dx.abs() > dy.abs()) {
      setState(() => dx > 0 ? _game.moveRight() : _game.moveLeft());
      _dragStart = d.localPosition;
    } else if (dy > _swipeThreshold && dy > dx.abs()) {
      setState(() => _game.softDrop());
      _dragStart = d.localPosition;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tetris'),
        actions: [
          IconButton(
            icon: Icon(_game.status == TetrisStatus.paused
                ? Icons.play_arrow
                : Icons.pause),
            onPressed: () => setState(() {
              _game.togglePause();
              if (_game.status == TetrisStatus.playing) _scheduleTimer();
              else _timer?.cancel();
            }),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(_startNewGame),
          ),
        ],
      ),
      body: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 500;
            return isWide
                ? _wideLayout(context)
                : _narrowLayout(context);
          },
        ),
      ),
    );
  }

  // ── Narrow (portrait) layout ──────────────────────────────────────────────

  Widget _narrowLayout(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: _scoreRow(context),
        ),
        Expanded(child: _boardAndSide(context, compact: true)),
      ],
    );
  }

  // ── Wide (landscape / ChromeOS) layout ───────────────────────────────────

  Widget _wideLayout(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _board()),
        SizedBox(
          width: 160,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _sidebar(context),
          ),
        ),
      ],
    );
  }

  Widget _boardAndSide(BuildContext context, {required bool compact}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(child: _board()),
        const SizedBox(width: 12),
        SizedBox(
          width: 110,
          child: _sidebar(context),
        ),
      ],
    );
  }

  // ── Board widget ──────────────────────────────────────────────────────────

  Widget _board() {
    return LayoutBuilder(builder: (context, constraints) {
      // Pick the largest cell size that fits both axes so cells are always square.
      final cellByWidth = constraints.maxWidth / TetrisGame.cols;
      final cellByHeight = constraints.hasBoundedHeight
          ? constraints.maxHeight / TetrisGame.rows
          : cellByWidth;
      final cellSize = cellByWidth < cellByHeight ? cellByWidth : cellByHeight;
      final boardW = cellSize * TetrisGame.cols;
      final boardH = cellSize * TetrisGame.rows;

      return Center(
        child: SizedBox(
          width: boardW,
          height: boardH,
          child: GestureDetector(
            onTap: () => setState(() => _game.rotate()),
            onDoubleTap: () {
              setState(() => _game.hardDrop());
              if (_game.status == TetrisStatus.gameOver) {
                _timer?.cancel();
                _showGameOver();
              }
            },
            onPanStart: _onDragStart,
            onPanUpdate: _onDragUpdate,
            child: CustomPaint(
              painter: TetrisBoardPainter(_game),
            ),
          ),
        ),
      );
    });
  }

  // ── Sidebar (score + next piece preview) ─────────────────────────────────

  Widget _sidebar(BuildContext context) {
    final style = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sideLabel(context, 'SCORE', '${_game.score}'),
        const SizedBox(height: 12),
        _sideLabel(context, 'LEVEL', '${_game.level}'),
        const SizedBox(height: 12),
        _sideLabel(context, 'LINES', '${_game.linesCleared}'),
        const SizedBox(height: 20),
        Text('NEXT', style: style.labelSmall?.copyWith(color: Colors.white54)),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 1,
          child: CustomPaint(painter: TetrisPreviewPainter(_game)),
        ),
        const SizedBox(height: 16),
        Text(
          'Tap: rotate\nDbl-tap: drop\nSwipe: move/fall',
          style: style.labelSmall?.copyWith(color: Colors.white38, fontSize: 10),
        ),
      ],
    );
  }

  Widget _sideLabel(BuildContext context, String label, String value) {
    final style = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: style.labelSmall?.copyWith(color: Colors.white54)),
        Text(value, style: style.titleLarge?.copyWith(color: Colors.white)),
      ],
    );
  }

  Widget _scoreRow(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Text('Score: ${_game.score}', style: style),
        Text('Level: ${_game.level}', style: style),
        Text('Lines: ${_game.linesCleared}', style: style),
      ],
    );
  }
}
