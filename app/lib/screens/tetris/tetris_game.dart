import 'dart:math';

enum TetrisStatus { playing, paused, gameOver }

// Color index per piece type (0 = empty). Painter maps these to actual colors.
// 1=I(cyan)  2=O(yellow)  3=T(purple)  4=S(green)  5=Z(red)  6=J(blue)  7=L(orange)

class TetrisGame {
  static const cols = 10;
  static const rows = 20;
  static const _spawnCol = 3; // left edge of 4-wide bounding box

  // pieces[type][rotation] = list of [row, col] offsets from bounding-box origin
  static const _pieces = <List<List<List<int>>>>[
    // 0 — I
    [[[0,0],[1,0],[2,0],[3,0]], [[0,0],[0,1],[0,2],[0,3]]],
    // 1 — O
    [[[0,0],[0,1],[1,0],[1,1]]],
    // 2 — T
    [[[0,1],[1,0],[1,1],[1,2]], [[0,0],[1,0],[1,1],[2,0]],
     [[0,0],[0,1],[0,2],[1,1]], [[0,1],[1,0],[1,1],[2,1]]],
    // 3 — S
    [[[0,1],[0,2],[1,0],[1,1]], [[0,0],[1,0],[1,1],[2,1]]],
    // 4 — Z
    [[[0,0],[0,1],[1,1],[1,2]], [[0,1],[1,0],[1,1],[2,0]]],
    // 5 — J
    [[[0,0],[1,0],[1,1],[1,2]], [[0,0],[0,1],[1,0],[2,0]],
     [[0,0],[0,1],[0,2],[1,2]], [[0,1],[1,1],[2,0],[2,1]]],
    // 6 — L
    [[[0,2],[1,0],[1,1],[1,2]], [[0,0],[1,0],[2,0],[2,1]],
     [[0,0],[0,1],[0,2],[1,0]], [[0,0],[0,1],[1,1],[2,1]]],
  ];

  static const _colorOf = [1, 2, 3, 4, 5, 6, 7]; // piece index → color index

  // Board: board[row][col] = color index (0 = empty)
  final board = List.generate(rows, (_) => List.filled(cols, 0));

  int _pieceType = 0;
  int _rotation = 0;
  int _pieceRow = 0;
  int _pieceCol = _spawnCol;

  int _nextType = 0;

  int score = 0;
  int level = 1;
  int linesCleared = 0;
  TetrisStatus status = TetrisStatus.playing;

  TetrisGame() {
    _nextType = _rand();
    _spawn();
  }

  // ── Public read-only accessors ───────────────────────────────────────────

  int get pieceType => _pieceType;
  int get nextType => _nextType;

  List<List<int>> get currentCells => _cells(_pieceType, _rotation, _pieceRow, _pieceCol);

  List<List<int>> get ghostCells {
    var r = _pieceRow;
    while (_valid(_pieceType, _rotation, r + 1, _pieceCol)) {
      r++;
    }
    return r == _pieceRow ? [] : _cells(_pieceType, _rotation, r, _pieceCol);
  }

  List<List<int>> nextPieceCells(int originRow, int originCol) =>
      _cells(_nextType, 0, originRow, originCol);

  // ── Input ────────────────────────────────────────────────────────────────

  void moveLeft() {
    if (status != TetrisStatus.playing) return;
    if (_valid(_pieceType, _rotation, _pieceRow, _pieceCol - 1)) _pieceCol--;
  }

  void moveRight() {
    if (status != TetrisStatus.playing) return;
    if (_valid(_pieceType, _rotation, _pieceRow, _pieceCol + 1)) _pieceCol++;
  }

  void rotate() {
    if (status != TetrisStatus.playing) return;
    final next = (_rotation + 1) % _pieces[_pieceType].length;
    // Try straight rotation then wall-kick ±1 column
    for (final dc in [0, 1, -1]) {
      if (_valid(_pieceType, next, _pieceRow, _pieceCol + dc)) {
        _rotation = next;
        _pieceCol += dc;
        return;
      }
    }
  }

  void softDrop() {
    if (status != TetrisStatus.playing) return;
    if (_valid(_pieceType, _rotation, _pieceRow + 1, _pieceCol)) {
      _pieceRow++;
      score++;
    }
  }

  void hardDrop() {
    if (status != TetrisStatus.playing) return;
    while (_valid(_pieceType, _rotation, _pieceRow + 1, _pieceCol)) {
      _pieceRow++;
      score += 2;
    }
    _lock();
  }

  void togglePause() {
    if (status == TetrisStatus.gameOver) return;
    status = status == TetrisStatus.playing ? TetrisStatus.paused : TetrisStatus.playing;
  }

  // ── Game loop tick (called by Timer) ────────────────────────────────────

  void tick() {
    if (status != TetrisStatus.playing) return;
    if (_valid(_pieceType, _rotation, _pieceRow + 1, _pieceCol)) {
      _pieceRow++;
    } else {
      _lock();
    }
  }

  // ── Tick duration in ms (decreases with level) ───────────────────────────

  int get tickMs => max(80, 800 - (level - 1) * 72);

  // ── Internal ─────────────────────────────────────────────────────────────

  static int _rand() => Random().nextInt(_pieces.length);

  List<List<int>> _cells(int type, int rot, int row, int col) {
    return _pieces[type][rot % _pieces[type].length]
        .map((c) => [row + c[0], col + c[1]])
        .toList();
  }

  bool _valid(int type, int rot, int row, int col) {
    for (final c in _cells(type, rot, row, col)) {
      final r = c[0], cl = c[1];
      if (r < 0 || r >= rows || cl < 0 || cl >= cols) return false;
      if (board[r][cl] != 0) return false;
    }
    return true;
  }

  void _lock() {
    final color = _colorOf[_pieceType];
    for (final c in currentCells) {
      if (c[0] >= 0 && c[0] < rows) board[c[0]][c[1]] = color;
    }
    _clearLines();
    _spawn();
  }

  void _clearLines() {
    final full = <int>[];
    for (var r = 0; r < rows; r++) {
      if (board[r].every((c) => c != 0)) full.add(r);
    }
    if (full.isEmpty) return;

    // Remove all full rows first (bottom-to-top so indices stay valid),
    // then add the same number of empty rows at the top.
    for (final r in full.reversed) {
      board.removeAt(r);
    }
    for (var i = 0; i < full.length; i++) {
      board.insert(0, List.filled(cols, 0));
    }

    linesCleared += full.length;
    score += [0, 100, 300, 500, 800][full.length] * level;
    level = linesCleared ~/ 10 + 1;
  }

  void _spawn() {
    _pieceType = _nextType;
    _nextType = _rand();
    _rotation = 0;
    _pieceRow = 0;
    _pieceCol = _spawnCol;

    if (!_valid(_pieceType, _rotation, _pieceRow, _pieceCol)) {
      status = TetrisStatus.gameOver;
    }
  }
}
