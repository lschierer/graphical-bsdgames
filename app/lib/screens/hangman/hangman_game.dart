import 'dart:math';

enum HangmanStatus { playing, won, lost }

class HangmanGame {
  static const maxErrors = 7;
  static const _minLength = 6;

  final String word;
  final _guessed = <String>{};
  int errors = 0;

  HangmanGame._(this.word);

  factory HangmanGame.fromWordList(List<String> words) {
    final eligible = words
        .map((w) => w.trim().toLowerCase())
        .where((w) => w.length >= _minLength && RegExp(r'^[a-z]+$').hasMatch(w))
        .toList();
    if (eligible.isEmpty) throw StateError('No eligible words in list');
    return HangmanGame._(eligible[Random().nextInt(eligible.length)]);
  }

  HangmanStatus get status {
    if (errors >= maxErrors) return HangmanStatus.lost;
    if (word.split('').every(_guessed.contains)) return HangmanStatus.won;
    return HangmanStatus.playing;
  }

  Set<String> get guessed => Set.unmodifiable(_guessed);

  List<String?> get revealed =>
      word.split('').map((c) => _guessed.contains(c) ? c : null).toList();

  void guess(String letter) {
    assert(letter.length == 1 && RegExp(r'[a-z]').hasMatch(letter));
    if (status != HangmanStatus.playing) return;
    if (_guessed.contains(letter)) return;
    _guessed.add(letter);
    if (!word.contains(letter)) errors++;
  }
}
