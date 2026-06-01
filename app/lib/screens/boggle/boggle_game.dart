import 'dart:math';

enum BoggleStatus { playing, gameOver }
enum SubmitResult { valid, tooShort, alreadyFound, notAWord }
enum BoggleMode { classic, big }

/// How words are valued.
/// netbsd — matches the original C game: percentage of possible words found.
/// hasbro — standard board-game point table (3-4=1, 5=2, 6=3, 7=5, 8+=11).
enum ScoringMode { netbsd, hasbro }

class BoggleGame {
  static const gameDurationSeconds = 180;

  // Classic 4×4 — 16 dice (one char per face; 'q' = "qu" tile)
  static const _classicDice = [
    'aaeegn', 'elrtty', 'aoottw', 'abbjoo',
    'ehrtvw', 'cimotu', 'distty', 'eiosst',
    'delrvy', 'achops', 'himnqu', 'eeinsu',
    'eeghnw', 'affkps', 'hlnnrz', 'deilrx',
  ];

  // Big Boggle 5×5 — 25 dice (standard Boggle Deluxe set)
  static const _bigDice = [
    'aaafrs', 'aaeeee', 'aafirs', 'adennn', 'aeeeem',
    'aeegmu', 'aegmnn', 'afirsy', 'bjkqxz', 'ccnstw',
    'ceiilt', 'ceilpt', 'ceipst', 'ddlnor', 'dhhlor',
    'dhhnot', 'dhlnor', 'eiiitt', 'emottt', 'ensssu',
    'fiprsy', 'gorrvw', 'hiprry', 'nootuw', 'ooottu',
  ];

  final BoggleMode mode;
  final ScoringMode scoringMode;

  // Grid dimensions derived from mode
  int get gridSize => mode == BoggleMode.big ? 5 : 4;
  int get minWordLen => mode == BoggleMode.big ? 4 : 3;

  // Board: gridSize² cells, row-major; 'a'–'z' or 'qu' for the Q die
  final List<String> board;
  final Set<String> dictionary;
  final Set<String> _foundSet = {};
  final List<String> foundWords = [];
  int points = 0;  // Hasbro point total (always tracked, displayed only in hasbro mode)

  // What to show in the AppBar / score chip
  String get scoreDisplay => scoringMode == ScoringMode.hasbro
      ? '${points} pts'
      : '${foundWords.length} word${foundWords.length == 1 ? "" : "s"}';
  int secondsLeft = gameDurationSeconds;
  BoggleStatus status = BoggleStatus.playing;

  BoggleGame(this.dictionary, {
    this.mode = BoggleMode.classic,
    this.scoringMode = ScoringMode.netbsd,
  }) : board = _rollDice(mode);

  static List<String> _rollDice(BoggleMode mode) {
    final rng = Random();
    final dice = mode == BoggleMode.big ? _bigDice : _classicDice;
    final shuffled = List<String>.from(dice)..shuffle(rng);
    return shuffled.map((die) {
      final face = die[rng.nextInt(die.length)];
      return face == 'q' ? 'qu' : face;
    }).toList();
  }

  // Instance helpers — depend on gridSize so cannot be static
  int cellIndex(int row, int col) => row * gridSize + col;
  int cellRow(int idx) => idx ~/ gridSize;
  int cellCol(int idx) => idx % gridSize;

  bool areAdjacent(int a, int b) {
    final dr = (cellRow(a) - cellRow(b)).abs();
    final dc = (cellCol(a) - cellCol(b)).abs();
    return dr <= 1 && dc <= 1 && a != b;
  }

  String pathToWord(List<int> path) => path.map((i) => board[i]).join();

  SubmitResult submit(List<int> path) {
    final word = pathToWord(path);
    if (word.length < minWordLen) return SubmitResult.tooShort;
    if (_foundSet.contains(word)) return SubmitResult.alreadyFound;
    if (!dictionary.contains(word)) return SubmitResult.notAWord;
    _foundSet.add(word);
    foundWords.add(word);
    points += wordScore(word);
    return SubmitResult.valid;
  }

  // Classic: 3–4=1  5=2  6=3  7=5  8+=11
  // Big:       4=1  5=2  6=3  7=5  8+=11  (3-letter tier dropped)
  int wordScore(String word) {
    final len = word.length;
    final base = mode == BoggleMode.big ? 4 : 3;
    if (len <= base + 1) return 1;   // 3-4 classic / 4-5 big
    if (len == base + 2) return 2;   // 5 classic  / 6 big
    if (len == base + 3) return 3;   // 6 classic  / 7 big
    if (len == base + 4) return 5;   // 7 classic  / 8 big
    return 11;                        // 8+ classic / 9+ big
  }

  void tick() {
    if (status != BoggleStatus.playing || secondsLeft <= 0) return;
    secondsLeft--;
    if (secondsLeft == 0) status = BoggleStatus.gameOver;
  }

  String get timerDisplay {
    final m = secondsLeft ~/ 60;
    final s = secondsLeft % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
