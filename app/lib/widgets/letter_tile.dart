import 'package:flutter/material.dart';

enum LetterTileState { idle, correct, wrong, revealed, selected }

class LetterTile extends StatelessWidget {
  final String letter;
  final LetterTileState state;
  final VoidCallback? onTap;
  final double size;

  const LetterTile({
    super.key,
    required this.letter,
    this.state = LetterTileState.idle,
    this.onTap,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final bg = switch (state) {
      LetterTileState.idle     => const Color(0xFFF5E6C8),
      LetterTileState.correct  => const Color(0xFF4CAF50),
      LetterTileState.wrong    => const Color(0xFFE53935),
      LetterTileState.revealed => const Color(0xFFF5E6C8),
      LetterTileState.selected => const Color(0xFFFFB300),
    };

    final fg = switch (state) {
      LetterTileState.idle     => Colors.black87,
      LetterTileState.correct  => Colors.white,
      LetterTileState.wrong    => Colors.white,
      LetterTileState.revealed => Colors.black87,
      LetterTileState.selected => Colors.black87,
    };

    final tile = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFB89A5A), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            offset: const Offset(2, 2),
            blurRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            letter.toUpperCase(),
            style: TextStyle(
              fontSize: size * 0.55,
              fontWeight: FontWeight.bold,
              color: fg,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );

    if (onTap == null || state == LetterTileState.correct || state == LetterTileState.wrong) {
      return tile;
    }
    return GestureDetector(onTap: onTap, child: tile);
  }
}
