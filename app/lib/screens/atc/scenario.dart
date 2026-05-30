import 'dart:math';

// ── Direction encoding (matches NetBSD atc extern.c displacement table) ───────
// dir 0=N  1=NE  2=E  3=SE  4=S  5=SW  6=W  7=NW
const _dx = [ 0,  1, 1,  1,  0, -1, -1, -1];
const _dy = [-1, -1, 0,  1,  1,  1,  0, -1];

// Letter → dir (from ATC input.c state machine: w=N e=NE d=E c=SE x=S z=SW a=W q=NW)
const _dirOfLetter = {
  'w': 0, 'e': 1, 'd': 2, 'c': 3,
  'x': 4, 'z': 5, 'a': 6, 'q': 7,
};

int dirDx(int dir) => _dx[dir % 8];
int dirDy(int dir) => _dy[dir % 8];

int dirFromLetter(String ch) => _dirOfLetter[ch] ?? 0;

// Compute the direction index that points from (fx,fy) toward (tx,ty).
int dirToward(int fx, int fy, int tx, int ty) {
  final dx = tx - fx;
  final dy = ty - fy;
  if (dx == 0 && dy == 0) return 0;
  final angle = atan2(dy.toDouble(), dx.toDouble());
  // atan2: 0=E, π/2=S, ±π=W, -π/2=N
  // Map to our dir encoding: 0=N,1=NE,2=E,3=SE,4=S,5=SW,6=W,7=NW
  final raw = (angle / (pi / 4) + 2.5 + 8).round() % 8;
  return raw;
}

// ── Scenario data ─────────────────────────────────────────────────────────────

class ScenarioPoint {
  final int x, y;
  const ScenarioPoint(this.x, this.y);
}

class Exit extends ScenarioPoint {
  final int dir;
  const Exit(super.x, super.y, this.dir);
}

class Beacon extends ScenarioPoint {
  const Beacon(super.x, super.y);
}

class Airport extends ScenarioPoint {
  final int dir;
  const Airport(super.x, super.y, this.dir);
}

class Airway {
  final ScenarioPoint p1, p2;
  const Airway(this.p1, this.p2);
}

class Scenario {
  final String name;
  final int width, height;
  final int updateSecs;   // seconds between ticks
  final int newplaneTime; // ticks between spawns (on average)
  final List<Exit> exits;
  final List<Beacon> beacons;
  final List<Airport> airports;
  final List<Airway> airways;

  const Scenario({
    required this.name,
    required this.width,
    required this.height,
    required this.updateSecs,
    required this.newplaneTime,
    required this.exits,
    required this.beacons,
    required this.airports,
    required this.airways,
  });
}

// ── Parser ────────────────────────────────────────────────────────────────────

Scenario parseScenario(String name, String source) {
  // Strip C-style comments
  final text = source.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ');

  int width = 30, height = 21, updateSecs = 5, newplaneTime = 10;
  final exits = <Exit>[];
  final beacons = <Beacon>[];
  final airports = <Airport>[];
  final airways = <Airway>[];

  // Tokenise: numbers, identifiers, single-char punctuation
  final tokens = RegExp(r'[a-zA-Z_][a-zA-Z_0-9]*|-?\d+|[=;:()\[\],]')
      .allMatches(text)
      .map((m) => m.group(0)!)
      .toList();

  int i = 0;
  String peek() => i < tokens.length ? tokens[i] : '';
  String consume() => tokens[i++];

  void expect(String s) {
    final t = consume();
    if (t != s) throw FormatException('Expected "$s", got "$t"');
  }

  int readInt() => int.parse(consume());

  while (i < tokens.length) {
    final kw = consume();
    switch (kw) {
      case 'update':
        expect('='); updateSecs = readInt(); expect(';');
      case 'newplane':
        expect('='); newplaneTime = readInt(); expect(';');
      case 'width':
        expect('='); width = readInt(); expect(';');
      case 'height':
        expect('='); height = readInt(); expect(';');
      case 'exit':
        expect(':');
        while (peek() == '(') {
          consume(); // (
          final x = readInt(), y = readInt();
          final dir = dirFromLetter(consume());
          expect(')');
          exits.add(Exit(x, y, dir));
        }
        expect(';');
      case 'beacon':
        expect(':');
        while (peek() == '(') {
          consume();
          final x = readInt(), y = readInt();
          expect(')');
          beacons.add(Beacon(x, y));
        }
        expect(';');
      case 'airport':
        expect(':');
        while (peek() == '(') {
          consume();
          final x = readInt(), y = readInt();
          final dir = dirFromLetter(consume());
          expect(')');
          airports.add(Airport(x, y, dir));
        }
        expect(';');
      case 'line':
        expect(':');
        while (peek() == '[') {
          consume();
          expect('('); final x1 = readInt(), y1 = readInt(); expect(')');
          expect('('); final x2 = readInt(), y2 = readInt(); expect(')');
          expect(']');
          airways.add(Airway(ScenarioPoint(x1, y1), ScenarioPoint(x2, y2)));
        }
        expect(';');
    }
  }

  return Scenario(
    name: name,
    width: width,
    height: height,
    updateSecs: updateSecs,
    newplaneTime: newplaneTime,
    exits: exits,
    beacons: beacons,
    airports: airports,
    airways: airways,
  );
}
