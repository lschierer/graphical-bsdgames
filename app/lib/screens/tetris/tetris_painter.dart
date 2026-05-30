import 'package:flutter/material.dart';
import 'tetris_game.dart';

// Maps color index (1-7) to paint colors. Index 0 = empty (not painted).
const _pieceColors = [
  Colors.transparent,       // 0 empty
  Color(0xFF00E5FF),        // 1 I  cyan
  Color(0xFFFFEE00),        // 2 O  yellow
  Color(0xFFAA00FF),        // 3 T  purple
  Color(0xFF00C853),        // 4 S  green
  Color(0xFFDD2222),        // 5 Z  red
  Color(0xFF1565C0),        // 6 J  blue
  Color(0xFFFF6D00),        // 7 L  orange
];

class TetrisBoardPainter extends CustomPainter {
  final TetrisGame game;

  const TetrisBoardPainter(this.game);

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / TetrisGame.cols;
    final cellH = size.height / TetrisGame.rows;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF111118),
    );

    // Grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFF222230)
      ..strokeWidth = 0.5;
    for (var r = 1; r < TetrisGame.rows; r++) {
      canvas.drawLine(Offset(0, r * cellH), Offset(size.width, r * cellH), gridPaint);
    }
    for (var c = 1; c < TetrisGame.cols; c++) {
      canvas.drawLine(Offset(c * cellW, 0), Offset(c * cellW, size.height), gridPaint);
    }

    // Locked board cells
    for (var r = 0; r < TetrisGame.rows; r++) {
      for (var c = 0; c < TetrisGame.cols; c++) {
        final colorIdx = game.board[r][c];
        if (colorIdx != 0) _drawCell(canvas, r, c, cellW, cellH, _pieceColors[colorIdx], 1.0);
      }
    }

    // Ghost piece
    if (game.status == TetrisStatus.playing) {
      for (final cell in game.ghostCells) {
        _drawCell(canvas, cell[0], cell[1], cellW, cellH,
            _pieceColors[_colorOf(game.pieceType)], 0.18);
      }
    }

    // Active piece
    if (game.status == TetrisStatus.playing) {
      for (final cell in game.currentCells) {
        if (cell[0] >= 0) {
          _drawCell(canvas, cell[0], cell[1], cellW, cellH,
              _pieceColors[_colorOf(game.pieceType)], 1.0);
        }
      }
    }

    // Border
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..color = const Color(0xFF444466)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _drawCell(Canvas canvas, int row, int col, double cw, double ch,
      Color color, double opacity) {
    final alpha = (opacity * 255).round();
    final left = col * cw + 1;
    final top = row * ch + 1;
    final right = left + cw - 2;
    final bottom = top + ch - 2;
    final rect = Rect.fromLTRB(left, top, right, bottom);
    const r = Radius.circular(3);

    // Base fill
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, r),
      Paint()..color = color.withAlpha(alpha),
    );

    if (opacity > 0.5) {
      // Top/left highlight (lighter)
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left, top, right - 2, top + 3), r),
        Paint()..color = Colors.white.withAlpha(80),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left, top, left + 3, bottom - 2), r),
        Paint()..color = Colors.white.withAlpha(80),
      );
      // Bottom/right shadow (darker)
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left + 2, bottom - 3, right, bottom), r),
        Paint()..color = Colors.black.withAlpha(80),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(right - 3, top + 2, right, bottom), r),
        Paint()..color = Colors.black.withAlpha(80),
      );
      // Outer border
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, r),
        Paint()
          ..color = Colors.black.withAlpha(120)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  int _colorOf(int pieceType) => pieceType + 1;

  @override
  bool shouldRepaint(TetrisBoardPainter old) => true;
}

// Small next-piece preview painter
class TetrisPreviewPainter extends CustomPainter {
  final TetrisGame game;

  const TetrisPreviewPainter(this.game);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF111118),
    );

    final cellSize = size.width / 4;
    final cells = game.nextPieceCells(0, 0);
    final color = _pieceColors[game.nextType + 1];

    // Center the preview in the 4×4 box
    final rows = cells.map((c) => c[0]).reduce((a, b) => a > b ? a : b) + 1;
    final cols_ = cells.map((c) => c[1]).reduce((a, b) => a > b ? a : b) + 1;
    final offsetRow = (4 - rows) / 2;
    final offsetCol = (4 - cols_) / 2;

    for (final cell in cells) {
      final r = cell[0] + offsetRow;
      final c = cell[1] + offsetCol;
      final rect = Rect.fromLTWH(c * cellSize + 1, r * cellSize + 1,
          cellSize - 2, cellSize - 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..color = color,
      );
    }

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..color = const Color(0xFF444466)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(TetrisPreviewPainter old) => true;
}
