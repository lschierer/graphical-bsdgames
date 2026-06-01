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
    int? startFuel,
  })  : newAltitude = altitude,
        newDir = dir,
        fuel = startFuel ?? _startFuel,
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
        p.delayedAtBeacon = false;

      case CmdMark():
        p.status = PlaneStatus.marked;

      case CmdUnmark():
        p.status = PlaneStatus.unmarked;

      case CmdIgnore():
        p.status = PlaneStatus.ignored;

      case CmdWithDelay(:final inner, :final beaconNo):
        if (beaconNo < 0 || beaconNo >= scenario.beacons.length) return;
        final b = scenario.beacons[beaconNo];
        // C delayb rejects the whole command unless the beacon lies directly
        // ahead on the plane's current heading.
        if ((b.x - p.x).sign != dirDx(p.dir) ||
            (b.y - p.y).sign != dirDy(p.dir)) {
          return;
        }
        // Apply the inner command's effect, then freeze direction changes until
        // the plane reaches the beacon.
        applyCommand(inner);
        // When the delay is combined with a "turn toward destination" command,
        // C aims from the beacon to that destination, not from the current pos.
        if (inner is CmdTurnToward) {
          final (tx, ty) = _destPos(inner.destType, inner.destNo);
          p.newDir = dirToward(b.x, b.y, tx, ty);
        }
        p.delayedAtBeacon = true;
        p.delayedBeaconNo = beaconNo;
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

    // Move airborne planes (and ground planes cleared for takeoff). C promotes
    // any ground plane with new_altitude > 0 into the air before this loop, so
    // a plane that has been told to climb begins moving on this tick.
    for (final p in planes) {
      if (p.status == PlaneStatus.gone) continue;
      if (!p.isAirborne && p.newAltitude <= 0) continue; // still parked
      // Props move every other tick.
      if (p.type == PlaneType.prop && _tick.isOdd) continue;

      p.fuel--;
      if (p.fuel < 0) {
        _lose(p, 'ran out of fuel');
        return;
      }

      // Altitude step (±1 toward target).
      if (p.altitude != p.newAltitude) {
        p.altitude += (p.newAltitude > p.altitude) ? 1 : -1;
      }

      // Direction step — max ±2 dir-units per move, unless holding for a beacon.
      if (!p.delayedAtBeacon) {
        int diff;
        if (p.circling) {
          // C sets new_dir = MAXDIR, which clamps to +2 (90° clockwise) a tick.
          diff = 2;
        } else {
          diff = (p.newDir - p.dir) % 8;
          if (diff > 4) diff -= 8; // shortest arc
          if (diff.abs() > 2) diff = diff.sign * 2;
        }
        p.dir = (p.dir + diff + 8) % 8;
      }

      // Move one cell in the (now updated) heading.
      p.x += dirDx(p.dir);
      p.y += dirDy(p.dir);

      // Reached the beacon we were holding for?
      if (p.delayedAtBeacon) {
        final b = scenario.beacons[p.delayedBeaconNo];
        if (p.x == b.x && p.y == b.y) {
          p.delayedAtBeacon = false;
          if (p.status == PlaneStatus.unmarked) p.status = PlaneStatus.marked;
        }
      }

      // ── Destination / crash checks (order mirrors update.c) ──
      if (p.destType == DestType.airport) {
        final a = scenario.airports[p.destNo];
        if (p.x == a.x && p.y == a.y && p.altitude == 0) {
          if (p.dir != a.dir) {
            _lose(p, 'landed in the wrong direction');
            return;
          }
          _safeExits++;
          p.status = PlaneStatus.gone;
          recentEvents.add('${p.label.toUpperCase()} landed safely');
          continue;
        }
      } else if (p.destType == DestType.exit) {
        final e = scenario.exits[p.destNo];
        if (p.x == e.x && p.y == e.y) {
          if (p.altitude != 9) {
            _lose(p, 'exited at the wrong altitude (not 9000 ft)');
            return;
          }
          _safeExits++;
          p.status = PlaneStatus.gone;
          recentEvents.add('${p.label.toUpperCase()} exited safely');
          continue;
        }
      }

      // Flight ceiling.
      if (p.altitude > 9) {
        _lose(p, 'exceeded the flight ceiling');
        return;
      }

      // Altitude 0 without having landed at its destination = crash. Sitting on
      // a non-destination airport counts as landing at the wrong one.
      if (p.altitude <= 0) {
        final atAirport =
            scenario.airports.any((a) => a.x == p.x && a.y == p.y);
        _lose(p, atAirport
            ? 'landed at the wrong airport'
            : 'crashed on the ground');
        return;
      }

      // Left the flight arena. The whole frame (row/col 0 and the far edge) is
      // fatal unless it was the plane's own exit, which is handled above.
      if (p.x < 1 || p.x >= scenario.width - 1 ||
          p.y < 1 || p.y >= scenario.height - 1) {
        _lose(p, 'illegally left the flight arena');
        return;
      }
    }

    // Remove planes that have left, then test collisions (matches C order).
    planes.removeWhere((p) => p.status == PlaneStatus.gone);
    if (_checkCollisions()) return;

    // New planes enter at the END of the tick (C addplane is the last step of
    // update), so they never advance on their entrance tick.
    _maybSpawnPlane();
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
    // Spawn with probability 1/newplaneTime each tick.
    if (_rng.nextInt(scenario.newplaneTime) != 0) return;

    final label = _nextLabel();
    if (label == null) return; // all 26 slots are airborne/on the ground

    final isJet = _rng.nextBool();
    final type = isJet ? PlaneType.jet : PlaneType.prop;
    final totalOrigins = scenario.exits.length + scenario.airports.length;

    // C addplane picks the destination first, then searches for a start point.
    final destIdx = _rng.nextInt(totalOrigins);
    final DestType destType;
    final int destNo;
    if (destIdx < scenario.exits.length) {
      destType = DestType.exit;
      destNo = destIdx;
    } else {
      destType = DestType.airport;
      destNo = destIdx - scenario.exits.length;
    }

    // Find an origin that differs from the destination and — for exit entries —
    // is not within 4 cells of an airborne plane. Give up if none is clear.
    for (var attempt = 0; attempt < totalOrigins; attempt++) {
      int origIdx;
      do {
        origIdx = _rng.nextInt(totalOrigins);
      } while (origIdx == destIdx);

      final fromAirport = origIdx >= scenario.exits.length;
      final origNo = fromAirport ? origIdx - scenario.exits.length : origIdx;
      final origType = fromAirport ? DestType.airport : DestType.exit;

      int sx, sy, sDir, sAlt;
      if (fromAirport) {
        final ap = scenario.airports[origNo];
        sx = ap.x; sy = ap.y; sDir = ap.dir; sAlt = 0; // parked on the ground
      } else {
        final ex = scenario.exits[origNo];
        sx = ex.x; sy = ex.y; sDir = ex.dir; sAlt = 7; // enters at altitude 7
        final tooClose = planes.any((q) =>
            q.status != PlaneStatus.gone && q.isAirborne &&
            (q.altitude - sAlt).abs() <= 4 &&
            (q.x - sx).abs() <= 4 && (q.y - sy).abs() <= 4);
        if (tooClose) continue;
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
        startFuel: scenario.width + scenario.height,
      ));
      recentEvents.add('${label.toUpperCase()} appeared (${isJet ? "jet" : "prop"}) → ${destType == DestType.exit ? "Exit ${destNo + 1}" : "Airport ${destNo + 1}"}');
      return;
    }
  }

  // First letter not currently used by an active plane (C reuses freed slots,
  // so the cap is 26 *concurrent* planes, not 26 for the whole game).
  String? _nextLabel() {
    for (var code = 'a'.codeUnitAt(0); code <= 'z'.codeUnitAt(0); code++) {
      final label = String.fromCharCode(code);
      if (planes.every((p) => p.status == PlaneStatus.gone || p.label != label)) {
        return label;
      }
    }
    return null;
  }
}
