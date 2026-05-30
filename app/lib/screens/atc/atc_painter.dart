import 'dart:math';
import 'package:flutter/material.dart';
import 'atc_game.dart';
import 'scenario.dart';

// Radar-green palette
const _bgColor      = Color(0xFF050F05);
const _gridColor    = Color(0xFF0A2A0A);
const _lineColor    = Color(0xFF1A5C1A);
const _exitColor    = Color(0xFF40A040);
const _beaconColor  = Color(0xFF60D060);
const _airportColor = Color(0xFF80FF80);
const _planeColor   = Color(0xFFCCFFCC);
const _lowFuelColor = Color(0xFFFFAA00);
const _selectedColor= Color(0xFFFFFF00);

class AtcPainter extends CustomPainter {
  final AtcGame game;
  final String? selectedLabel;
  final double cellSize;

  const AtcPainter(this.game, {this.selectedLabel, required this.cellSize});

  Offset _c(int x, int y) =>
      Offset((x + 0.5) * cellSize, (y + 0.5) * cellSize);

  @override
  void paint(Canvas canvas, Size size) {
    final sc = game.scenario;

    // Background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = _bgColor);

    // Grid
    final gridPaint = Paint()..color = _gridColor..strokeWidth = 0.5;
    for (var x = 0; x <= sc.width; x++) {
      canvas.drawLine(Offset(x * cellSize, 0), Offset(x * cellSize, sc.height * cellSize), gridPaint);
    }
    for (var y = 0; y <= sc.height; y++) {
      canvas.drawLine(Offset(0, y * cellSize), Offset(sc.width * cellSize, y * cellSize), gridPaint);
    }

    // Airways
    final airwayPaint = Paint()..color = _lineColor..strokeWidth = 1;
    for (final aw in sc.airways) {
      canvas.drawLine(_c(aw.p1.x, aw.p1.y), _c(aw.p2.x, aw.p2.y), airwayPaint);
    }

    // Exits
    for (var i = 0; i < sc.exits.length; i++) {
      final e = sc.exits[i];
      _drawExit(canvas, e, i);
    }

    // Beacons
    for (var i = 0; i < sc.beacons.length; i++) {
      final b = sc.beacons[i];
      _drawBeacon(canvas, b, i);
    }

    // Airports
    for (var i = 0; i < sc.airports.length; i++) {
      final a = sc.airports[i];
      _drawAirport(canvas, a, i);
    }

    // Planes
    for (final p in game.planes) {
      if (p.status == PlaneStatus.gone) continue;
      _drawPlane(canvas, p, p.label == selectedLabel);
    }
  }

  void _drawExit(Canvas canvas, Exit e, int idx) {
    final pos = _c(e.x, e.y);
    final r = cellSize * 0.35;
    canvas.drawRect(
      Rect.fromCenter(center: pos, width: r * 2, height: r * 2),
      Paint()..color = _exitColor..style = PaintingStyle.stroke..strokeWidth = 1.5,
    );
    _drawLabel(canvas, pos + Offset(r + 4, -r), '${idx + 1}', _exitColor, 10);
  }

  void _drawBeacon(Canvas canvas, Beacon b, int idx) {
    final pos = _c(b.x, b.y);
    final r = cellSize * 0.3;
    // Star (asterisk-style: 3 lines)
    final paint = Paint()..color = _beaconColor..strokeWidth = 1.5;
    for (var a = 0; a < 3; a++) {
      final angle = a * pi / 3;
      canvas.drawLine(
        pos + Offset(cos(angle) * r, sin(angle) * r),
        pos - Offset(cos(angle) * r, sin(angle) * r),
        paint,
      );
    }
    _drawLabel(canvas, pos + Offset(r + 4, -r), '${idx + 1}', _beaconColor, 10);
  }

  void _drawAirport(Canvas canvas, Airport a, int idx) {
    final pos = _c(a.x, a.y);
    final r = cellSize * 0.38;
    // Runway rectangle, oriented along landing direction
    final angle = _dirToAngle(a.dir);
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(angle);
    canvas.drawRect(
      Rect.fromCenter(center: Offset.zero, width: r * 2, height: r * 0.6),
      Paint()..color = _airportColor..style = PaintingStyle.stroke..strokeWidth = 1.5,
    );
    // Arrow showing takeoff direction
    canvas.drawLine(
      Offset(0, 0), Offset(r, 0),
      Paint()..color = _airportColor..strokeWidth = 1.5,
    );
    canvas.restore();
    _drawLabel(canvas, pos + Offset(r + 4, -r), '${idx + 1}', _airportColor, 10);
  }

  void _drawPlane(Canvas canvas, Plane p, bool selected) {
    final pos = _c(p.x, p.y);
    final color = selected
        ? _selectedColor
        : p.isLowFuel
            ? _lowFuelColor
            : _planeColor;

    final r = cellSize * 0.42;
    final angle = _dirToAngle(p.dir);

    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(angle);

    final paint = Paint()
      ..color = color
      ..strokeWidth = selected ? 2.0 : 1.5
      ..style = PaintingStyle.stroke;

    if (p.type == PlaneType.jet) {
      _drawJet(canvas, paint, r);
    } else {
      _drawProp(canvas, paint, r);
    }

    canvas.restore();

    // Props = UPPERCASE, jets = lowercase (original ATC convention)
    final label = '${p.displayLabel}${p.altitude}';
    _drawLabel(canvas, pos + Offset(cellSize * 0.1, -r - 10), label, color,
        selected ? 13 : 11);

    // Destination indicator (small char below)
    if (selected) {
      _drawLabel(canvas, pos + Offset(0, r + 8), p.destDescription,
          _selectedColor, 10);
    }
  }

  // Jet silhouette: delta-wing triangle + tail
  void _drawJet(Canvas canvas, Paint paint, double r) {
    final path = Path()
      ..moveTo(r, 0)           // nose
      ..lineTo(-r * 0.5, -r * 0.55)  // left wing tip
      ..lineTo(-r * 0.2, 0)
      ..lineTo(-r * 0.5, r * 0.55)   // right wing tip
      ..close();
    canvas.drawPath(path, paint);
    // Tail fin
    canvas.drawLine(Offset(-r * 0.5, 0), Offset(-r * 0.7, 0), paint);
  }

  // Prop silhouette: rounded fuselage + straight wings
  void _drawProp(Canvas canvas, Paint paint, double r) {
    // Fuselage oval
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: r * 1.4, height: r * 0.45),
      paint,
    );
    // Wings
    canvas.drawLine(Offset(0, -r * 0.55), Offset(0, r * 0.55), paint);
    // Prop dot
    canvas.drawCircle(Offset(r * 0.7, 0), r * 0.1,
        paint..style = PaintingStyle.fill);
    paint.style = PaintingStyle.stroke;
  }

  void _drawLabel(Canvas canvas, Offset pos, String text, Color color,
      double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  // Convert dir 0–7 to radians where 0°=pointing right (East) in canvas coords.
  // dir 0=N → -90°, dir 2=E → 0°, dir 4=S → 90°, dir 6=W → 180°
  double _dirToAngle(int dir) => (dir - 2) * pi / 4;

  @override
  bool shouldRepaint(AtcPainter old) => true;
}
