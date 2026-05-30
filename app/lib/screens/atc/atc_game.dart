import 'dart:math';
import 'scenario.dart';

// ── Plane ─────────────────────────────────────────────────────────────────────

enum PlaneType { prop, jet }
enum PlaneStatus { unmarked, marked, ignored, gone }
enum DestType { exit, airport, beacon }

// Starting fuel from original: LOWFUEL=15; planes spawn with enough fuel
// proportional to map size. We use a generous fixed value.
const _startFuel = 60;

class Plane {
  final String label;       // single letter, a–z
  final PlaneType type;
  int x, y;
  int altitude;             // 0 = ground, 1–9 in air
  int newAltitude;
  int dir;                  // 0–7
  int newDir;
  int fuel;
  PlaneStatus status;
  DestType destType;
  int destNo;
  DestType origType;
  int origNo;
  bool circling;
  bool delayedAtBeacon;
  int delayedBeaconNo;

  Plane({
    required this.label,
    required this.type,
    required this.x,
    required this.y,
    required this.altitude,
    required this.dir,
    required this.destType,
    required this.destNo,
    required this.origType,
    required this.origNo,
  })  : newAltitude = altitude,
        newDir = dir,
        fuel = _startFuel,
        status = PlaneStatus.unmarked,
        circling = false,
        delayedAtBeacon = false,
        delayedBeaconNo = 0;

  bool get isAirborne => altitude > 0;
  bool get isLowFuel  => fuel < 15;

  String get destChar => switch (destType) {
    DestType.exit    => 'E',
    DestType.airport => 'A',
    DestType.beacon  => 'B',
  };

  // Props display as UPPERCASE, jets as lowercase (original ATC convention).
  String get displayLabel =>
      type == PlaneType.prop ? label.toUpperCase() : label.toLowerCase();

  // Short info string: e.g. "B4*A1" (prop B, alt 4, low fuel, dest airport 1)
  //                     or  "g7 E3" (jet g, alt 7, no fuel warning, dest exit 3)
  String get infoLabel =>
      '$displayLabel$altitude${isLowFuel ? "*" : " "}$destChar${destNo + 1}';

  // What the plane is currently doing (for the info panel)
  String get commandDesc {
    if (!isAirborne) return 'gnd';
    if (circling)    return 'circ';
    if (newDir != dir) return '→${newDir * 45}°';
    if (newAltitude > altitude) return '↑$newAltitude';
    if (newAltitude < altitude) return '↓$newAltitude';
    return '-';
  }

  // Description shown in command panel
  String get destDescription => switch (destType) {
    DestType.exit    => 'Exit ${destNo + 1}',
    DestType.airport => 'Airport ${destNo + 1}',
    DestType.beacon  => 'Beacon ${destNo + 1}',
  };
}

// ── Commands (what the UI sends to the game) ──────────────────────────────────

sealed class AtcCommand {
  final String planeLabel;
  const AtcCommand(this.planeLabel);
}

class CmdAltitude   extends AtcCommand {
  final int altitude; // 1–9
  const CmdAltitude(super.l, this.altitude);
}

class CmdTurnDir    extends AtcCommand {
  final int dir;      // absolute 0–7
  const CmdTurnDir(super.l, this.dir);
}

class CmdTurnToward extends AtcCommand {
  final DestType destType;
  final int destNo;
  const CmdTurnToward(super.l, this.destType, this.destNo);
}

class CmdTurnLeft   extends AtcCommand {
  final int steps; // 1 = 45°, 2 = 90°
  const CmdTurnLeft(super.l, this.steps);
}

class CmdTurnRight  extends AtcCommand {
  final int steps;
  const CmdTurnRight(super.l, this.steps);
}

class CmdAltitudeRelative extends AtcCommand {
  final int delta; // positive = climb, negative = descend
  const CmdAltitudeRelative(super.l, this.delta);
}

class CmdCircle     extends AtcCommand {
  const CmdCircle(super.l);
}

class CmdMark       extends AtcCommand {
  const CmdMark(super.l);
}

class CmdUnmark     extends AtcCommand {
  const CmdUnmark(super.l);
}

class CmdIgnore     extends AtcCommand {
  const CmdIgnore(super.l);
}

// Wraps any delayable command: execute it when the plane reaches a beacon.
class CmdWithDelay  extends AtcCommand {
  final AtcCommand inner;
  final int beaconNo; // 0-indexed
  const CmdWithDelay(super.l, this.inner, this.beaconNo);
}

// ── Game state ────────────────────────────────────────────────────────────────

enum AtcStatus { playing, lost, won }

class AtcCollision {
  final String a, b;
  final String reason;
  const AtcCollision(this.a, this.b, this.reason);
}

class AtcGame {
  final Scenario scenario;
  int _tick = 0;
  int _safeExits = 0;
  final List<Plane> planes = [];
  final List<String> _usedLabels = [];
  AtcStatus status = AtcStatus.playing;
  String? lossReason;
  AtcCollision? collision;
  final _rng = Random();

  // Tick events for the UI to show briefly
  final List<String> recentEvents = [];

  AtcGame(this.scenario);

  int get tick => _tick;
  int get safeExits => _safeExits;

  Plane? planeByLabel(String label) =>
      planes.where((p) => p.label == label && p.status != PlaneStatus.gone)
            .firstOrNull;

  // ── Command dispatch ───────────────────────────────────────────────────────

  void applyCommand(AtcCommand cmd) {
    final p = planeByLabel(cmd.planeLabel);
    if (p == null) return;

    // Ground planes can only take off (altitude command > 0).
    if (!p.isAirborne) {
      if (cmd case CmdAltitude(:final altitude) when altitude > 0) {
        p.newAltitude = altitude;
      }
      return;
    }

    switch (cmd) {
      case CmdAltitude(:final altitude):
        p.newAltitude = altitude;
        p.circling = false;

      case CmdTurnLeft(:final steps):
        p.newDir = (p.dir - steps + 8) % 8;
        p.circling = false;
        p.delayedAtBeacon = false;

      case CmdTurnRight(:final steps):
        p.newDir = (p.dir + steps) % 8;
        p.circling = false;
        p.delayedAtBeacon = false;

      case CmdAltitudeRelative(:final delta):
        p.newAltitude = (p.altitude + delta).clamp(0, 9);

      case CmdTurnDir(:final dir):
        p.newDir = dir;
        p.circling = false;
        p.delayedAtBeacon = false;

      case CmdTurnToward(:final destType, :final destNo):
        final (tx, ty) = _destPos(destType, destNo);
        // Just aim toward the target — same as original `ttb/e/a`.
        // The plane flies continuously; it doesn't auto-stop at the waypoint.
        p.newDir = dirToward(p.x, p.y, tx, ty);
        p.circling = false;
        p.delayedAtBeacon = false;

      case CmdCircle():
        p.circling = true;
        p.newDir = (p.dir + 1) % 8;

      case CmdMark():
        p.status = PlaneStatus.marked;

      case CmdUnmark():
        p.status = PlaneStatus.unmarked;

      case CmdIgnore():
        p.status = PlaneStatus.ignored;

      case CmdWithDelay(:final inner, :final beaconNo):
        // Apply the inner command's effect (newDir, circling, etc.) then
        // freeze direction changes until the plane reaches the beacon.
        applyCommand(inner);
        final p2 = planeByLabel(cmd.planeLabel);
        if (p2 != null && p2.isAirborne &&
            beaconNo >= 0 && beaconNo < scenario.beacons.length) {
          p2.delayedAtBeacon = true;
          p2.delayedBeaconNo = beaconNo;
        }
    }
  }

  (int, int) _destPos(DestType type, int no) => switch (type) {
    DestType.exit    => (scenario.exits[no].x, scenario.exits[no].y),
    DestType.airport => (scenario.airports[no].x, scenario.airports[no].y),
    DestType.beacon  => (scenario.beacons[no].x, scenario.beacons[no].y),
  };

  // ── Tick ───────────────────────────────────────────────────────────────────

  void advance() {
    if (status != AtcStatus.playing) return;
    _tick++;

    _maybSpawnPlane();

    // Move airborne planes
    for (final p in planes) {
      if (p.status == PlaneStatus.gone) continue;
      if (!p.isAirborne) continue;
      // Props move every other tick
      if (p.type == PlaneType.prop && _tick.isOdd) continue;

      p.fuel--;
      if (p.fuel < 0) {
        _lose(p, 'ran out of fuel');
        return;
      }

      // Altitude step
      if (p.altitude != p.newAltitude) {
        p.altitude += (p.newAltitude > p.altitude) ? 1 : -1;
      }

      // Direction step — max ±2 dir-units per move
      if (!p.delayedAtBeacon) {
        if (p.circling) {
          p.newDir = (p.dir + 1) % 8;
        }
        var diff = (p.newDir - p.dir) % 8;
        if (diff > 4) diff -= 8; // shortest arc
        if (diff.abs() > 2) diff = diff.sign * 2;
        p.dir = (p.dir + diff + 8) % 8;
      }

      // Move
      p.x += dirDx(p.dir);
      p.y += dirDy(p.dir);

      // Reached delayed beacon?
      if (p.delayedAtBeacon) {
        final b = scenario.beacons[p.delayedBeaconNo];
        if (p.x == b.x && p.y == b.y) {
          p.delayedAtBeacon = false;
          if (p.status == PlaneStatus.unmarked) p.status = PlaneStatus.marked;
        }
      }

      // Check exit
      if (_tryExit(p)) continue;

      // Check landing
      if (_tryLand(p)) continue;

      // Altitude 0 away from any airport = crash (man page: "Planes flying at
      // altitude 0 crash if they are not over an airport.")
      if (p.altitude == 0) {
        final atAirport = scenario.airports.any((a) => a.x == p.x && a.y == p.y);
        if (!atAirport) {
          _lose(p, 'crashed — altitude 0 away from airport');
          return;
        }
      }

      // Out of bounds?
      if (p.x < 0 || p.x >= scenario.width ||
          p.y < 0 || p.y >= scenario.height) {
        _lose(p, 'flew out of bounds');
        return;
      }
    }

    // Collision detection
    if (_checkCollisions()) return;

    planes.removeWhere((p) => p.status == PlaneStatus.gone);
  }

  // A plane is removed only when it reaches *its own* destination exit at alt 9.
  // Any other border crossing is caught by the bounds check → loss.
  bool _tryExit(Plane p) {
    if (p.destType != DestType.exit) return false;
    final e = scenario.exits[p.destNo];
    if (p.x != e.x || p.y != e.y) return false;
    if (p.altitude != 9) {
      _lose(p, 'not at 9000 ft at exit ${p.destNo + 1}');
      return true;
    }
    _safeExits++;
    p.status = PlaneStatus.gone;
    recentEvents.add('${p.label.toUpperCase()} exited safely');
    return true;
  }

  // Landing: plane must be at its destination airport position with altitude 0.
  bool _tryLand(Plane p) {
    if (p.destType != DestType.airport) return false;
    final a = scenario.airports[p.destNo];
    if (p.x != a.x || p.y != a.y) return false;
    if (p.altitude != 0) return false; // still overflying — let it pass
    _safeExits++;
    p.status = PlaneStatus.gone;
    recentEvents.add('${p.label.toUpperCase()} landed safely');
    return true;
  }

  bool _checkCollisions() {
    final air = planes.where((p) => p.isAirborne && p.status != PlaneStatus.gone).toList();
    for (var i = 0; i < air.length; i++) {
      for (var j = i + 1; j < air.length; j++) {
        final a = air[i], b = air[j];
        final dx = (a.x - b.x).abs(), dy = (a.y - b.y).abs();
        final da = (a.altitude - b.altitude).abs();
        if (dx <= 1 && dy <= 1 && da < 2) {
          final reason = dx == 0 && dy == 0
              ? 'collision: same position'
              : 'near-miss collision (too close)';
          collision = AtcCollision(a.label, b.label, reason);
          status = AtcStatus.lost;
          lossReason = '${a.label.toUpperCase()} and ${b.label.toUpperCase()} $reason';
          return true;
        }
      }
    }
    return false;
  }

  void _lose(Plane p, String reason) {
    status = AtcStatus.lost;
    lossReason = '${p.label.toUpperCase()} $reason';
  }

  // ── Plane spawning ─────────────────────────────────────────────────────────

  void _maybSpawnPlane() {
    if (_usedLabels.length >= 26) return;
    // Spawn with probability 1/newplaneTime each tick
    if (_rng.nextInt(scenario.newplaneTime) != 0) return;

    final label = _nextLabel();
    if (label == null) return;

    final isJet = _rng.nextBool();
    final type = isJet ? PlaneType.jet : PlaneType.prop;

    // Pick random origin (exit or airport)
    final totalOrigins = scenario.exits.length + scenario.airports.length;
    final origIdx = _rng.nextInt(totalOrigins);
    final fromAirport = origIdx >= scenario.exits.length;
    final origNo = fromAirport ? origIdx - scenario.exits.length : origIdx;
    final origType = fromAirport ? DestType.airport : DestType.exit;

    // Pick a different random destination
    DestType destType;
    int destNo;
    do {
      final di = _rng.nextInt(totalOrigins);
      if (di < scenario.exits.length) {
        destType = DestType.exit;
        destNo = di;
      } else {
        destType = DestType.airport;
        destNo = di - scenario.exits.length;
      }
    } while (destType == origType && destNo == origNo);

    int sx, sy, sDir, sAlt;
    if (fromAirport) {
      final ap = scenario.airports[origNo];
      sx = ap.x; sy = ap.y;
      sDir = ap.dir;
      sAlt = 0; // starts on ground
    } else {
      final ex = scenario.exits[origNo];
      sx = ex.x; sy = ex.y;
      sDir = ex.dir;
      sAlt = 7; // enters at altitude 7
    }

    planes.add(Plane(
      label: label,
      type: type,
      x: sx, y: sy,
      altitude: sAlt,
      dir: sDir,
      destType: destType,
      destNo: destNo,
      origType: origType,
      origNo: origNo,
    ));
    recentEvents.add('${label.toUpperCase()} appeared (${isJet ? "jet" : "prop"}) → ${destType == DestType.exit ? "Exit ${destNo + 1}" : "Airport ${destNo + 1}"}');
  }

  String? _nextLabel() {
    for (var code = 'a'.codeUnitAt(0); code <= 'z'.codeUnitAt(0); code++) {
      final label = String.fromCharCode(code);
      if (!_usedLabels.contains(label) &&
          planes.every((p) => p.label != label)) {
        _usedLabels.add(label);
        return label;
      }
    }
    return null;
  }
}
