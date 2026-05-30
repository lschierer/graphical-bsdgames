import 'dart:math';

enum BoggleStatus { playing, gameOver }

enum SubmitResult { valid, tooShort, alreadyFound, notAWord }

class BoggleGame {
  static const gridSize = 4;
  static const gameDurationSeconds = 180;

  // Classic Boggle 16-die set (one face per char; 'q' = "qu" tile)
  static const _dice = [
    'aaeegn', 'elrtty', 'aoottw', 'abbjoo',
    'ehrtvw', 'cimotu', 'distty', 'eiosst',
    'delrvy', 'achops', 'himnqu', 'eeinsu',
    'eeghnw', 'affkps', 'hlnnrz', 'deilrx',
  ];

  // 16 cells, row-major; 'a'–'z' or 'qu' for the Q die
  final List<String> board;
  final Set<String> dictionary;
  final Set<String> _foundSet = {};
  final List<String> foundWords = [];
  int score = 0;
  int secondsLeft = gameDurationSeconds;
  BoggleStatus status = BoggleStatus.playing;

  BoggleGame(this.dictionary) : board = _rollDice();

  static List<String> _rollDice() {
    final rng = Random();
    final shuffled = List<String>.from(_dice)..shuffle(rng);
    return shuffled.map((die) {
      final face = die[rng.nextInt(die.length)];
      return face == 'q' ? 'qu' : face;
    }).toList();
  }

  static int cellIndex(int row, int col) => row * gridSize + col;
  static int cellRow(int idx) => idx ~/ gridSize;
  static int cellCol(int idx) => idx % gridSize;

  bool areAdjacent(int a, int b) {
    final dr = (cellRow(a) - cellRow(b)).abs();
    final dc = (cellCol(a) - cellCol(b)).abs();
    return dr <= 1 && dc <= 1 && a != b;
  }

  String pathToWord(List<int> path) => path.map((i) => board[i]).join();

  SubmitResult submit(List<int> path) {
    final word = pathToWord(path);
    if (word.length < 3) return SubmitResult.tooShort;
    if (_foundSet.contains(word)) return SubmitResult.alreadyFound;
    if (!dictionary.contains(word)) return SubmitResult.notAWord;
    _foundSet.add(word);
    foundWords.add(word);
    score += wordScore(word);
    return SubmitResult.valid;
  }

  int wordScore(String word) {
    final len = word.length;
    if (len <= 4) return 1;
    if (len == 5) return 2;
    if (len == 6) return 3;
    if (len == 7) return 5;
    return 11;
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
