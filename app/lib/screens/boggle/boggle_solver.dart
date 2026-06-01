// Finds every valid word on a Boggle board via DFS with binary-search
// prefix pruning (no trie needed — the dict file is already sorted).

class BoggleSolverParams {
  final List<String> board;
  final List<String> sortedDict; // alphabetically sorted
  final Set<String> wordSet;
  final int gridSize;
  final int minWordLen;
  const BoggleSolverParams({
    required this.board,
    required this.sortedDict,
    required this.wordSet,
    required this.gridSize,
    required this.minWordLen,
  });
}

/// Top-level so it can be passed to Flutter's compute().
Set<String> solveBoard(BoggleSolverParams p) {
  final n = p.gridSize * p.gridSize;
  final found = <String>{};

  // Binary search: does any word in sortedDict start with [prefix]?
  bool hasPrefix(String prefix) {
    var lo = 0, hi = p.sortedDict.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (p.sortedDict[mid].compareTo(prefix) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo < p.sortedDict.length &&
        p.sortedDict[lo].startsWith(prefix);
  }

  bool adjacent(int a, int b) {
    if (a == b) return false;
    return ((a ~/ p.gridSize) - (b ~/ p.gridSize)).abs() <= 1 &&
           ((a % p.gridSize) - (b % p.gridSize)).abs() <= 1;
  }

  void dfs(int idx, String word, List<bool> used) {
    if (!hasPrefix(word)) return; // prune entire subtree
    if (word.length >= p.minWordLen && p.wordSet.contains(word)) {
      found.add(word);
    }
    if (word.length >= 15) return;
    for (var next = 0; next < n; next++) {
      if (!used[next] && adjacent(idx, next)) {
        used[next] = true;
        dfs(next, word + p.board[next], used);
        used[next] = false;
      }
    }
  }

  for (var i = 0; i < n; i++) {
    final used = List.filled(n, false);
    used[i] = true;
    dfs(i, p.board[i], used);
  }

  return found;
}
