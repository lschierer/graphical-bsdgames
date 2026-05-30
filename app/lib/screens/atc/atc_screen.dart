import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'atc_game.dart';
import 'atc_painter.dart';
import 'scenario.dart';

// ── Scenario list ─────────────────────────────────────────────────────────────

const _scenarioAssets = [
  ('easy',       'assets/atc/easy'),
  ('novice',     'assets/atc/novice'),
  ('default',    'assets/atc/default'),
  ('OHare',      'assets/atc/OHare'),
  ('Atlantis',   'assets/atc/Atlantis'),
  ('crosshatch', 'assets/atc/crosshatch'),
  ('Killer',     'assets/atc/Killer'),
];

// ── Top-level screen ──────────────────────────────────────────────────────────

class AtcScreen extends StatefulWidget {
  const AtcScreen({super.key});

  @override
  State<AtcScreen> createState() => _AtcScreenState();
}

class _AtcScreenState extends State<AtcScreen> {
  List<(String, Scenario)>? _scenarios;
  int _scenarioIdx = 0;
  AtcGame? _game;
  Timer? _timer;
  String? _selectedLabel;
  _PanelMode _panelMode = _PanelMode.none;

  // Keyboard command state machine
  _KbdState _kbdState = _KbdState.idle;
  String _kbdBuffer = '';      // typed chars for display
  AtcCommand? _pendingCmd;     // command queued for optional delay suffix

  @override
  void initState() {
    super.initState();
    // Use HardwareKeyboard so we capture keys regardless of which widget has
    // focus — the Focus-widget approach loses capture to command-panel buttons.
    HardwareKeyboard.instance.addHandler(_hardwareKeyHandler);
    _loadScenarios();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_hardwareKeyHandler);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadScenarios() async {
    final list = <(String, Scenario)>[];
    for (final (name, asset) in _scenarioAssets) {
      try {
        final text = await rootBundle.loadString(asset);
        list.add((name, parseScenario(name, text)));
      } catch (_) {}
    }
    setState(() => _scenarios = list);
    _startGame();
  }

  void _startGame() {
    _timer?.cancel();
    final sc = _scenarios![_scenarioIdx].$2;
    setState(() {
      _game = AtcGame(sc);
      _selectedLabel = null;
      _panelMode = _PanelMode.none;
    });
    _timer = Timer.periodic(Duration(seconds: sc.updateSecs), (_) {
      if (!mounted) return;
      setState(() {
        _game!.advance();
        _game!.recentEvents.clear();
      });
      if (_game!.status != AtcStatus.playing) {
        _timer?.cancel();
        WidgetsBinding.instance.addPostFrameCallback((_) => _showEndDialog());
      }
    });
  }

  void _selectPlane(String label) {
    setState(() {
      _selectedLabel = label;
      _panelMode = _PanelMode.top;
    });
  }

  void _dismissPanel() {
    setState(() {
      _selectedLabel = null;
      _panelMode = _PanelMode.none;
    });
  }

  void _sendCommand(AtcCommand cmd) {
    setState(() {
      _game!.applyCommand(cmd);
      _panelMode = _PanelMode.top;
    });
  }

  // ── Hardware keyboard handler (bypasses Flutter focus routing) ───────────
  // Using HardwareKeyboard.instance ensures we receive every key event even
  // when a command-panel button has widget focus, which would swallow Enter
  // when using the older Focus(onKeyEvent:) approach.

  bool _hardwareKeyHandler(KeyEvent event) {
    if (!mounted) return false;
    if (event is KeyUpEvent) return false;

    final game = _game;
    if (game == null || game.status != AtcStatus.playing) return false;

    final logKey = event.logicalKey;

    if (logKey == LogicalKeyboardKey.escape ||
        logKey == LogicalKeyboardKey.backspace) {
      setState(() { _kbdBuffer = ''; _kbdState = _KbdState.idle; _pendingCmd = null; });
      return true;
    }

    if (logKey == LogicalKeyboardKey.enter ||
        logKey == LogicalKeyboardKey.numpadEnter) {
      if (_kbdState == _KbdState.idle) {
        // Fast-forward one tick
        setState(() { game.advance(); game.recentEvents.clear(); });
        if (game.status != AtcStatus.playing) {
          _timer?.cancel();
          WidgetsBinding.instance.addPostFrameCallback((_) => _showEndDialog());
        }
      } else {
        // Cancel partial command
        setState(() { _kbdBuffer = ''; _kbdState = _KbdState.idle; _pendingCmd = null; });
      }
      return true;
    }

    final ch = event.character;
    if (ch == null || ch.isEmpty) return false;

    _processKbdChar(ch, game);
    return true;
  }

  void _processKbdChar(String ch, AtcGame game) {
    switch (_kbdState) {

      case _KbdState.idle:
        if (RegExp(r'^[a-z]$').hasMatch(ch)) {
          final p = game.planeByLabel(ch);
          if (p != null && p.isAirborne) {
            setState(() {
              _kbdBuffer = ch;
              _kbdState = _KbdState.plane;
              _selectPlane(ch);
            });
          }
        }

      case _KbdState.plane:
        final lbl = _kbdBuffer[0];
        switch (ch) {
          case 't': setState(() { _kbdBuffer += 't'; _kbdState = _KbdState.turn; });
          case 'a': setState(() { _kbdBuffer += 'a'; _kbdState = _KbdState.alt; });
          // Circle is delayable — queue it and wait for Enter or ab-delay
          case 'c': _queueDelayable(CmdCircle(lbl), 'c');
          // Immediate-only:
          case 'm': _execReset(CmdMark(lbl), game);
          case 'u': _execReset(CmdUnmark(lbl), game);
          case 'i': _execReset(CmdIgnore(lbl), game);
        }

      case _KbdState.turn:
        final lbl = _kbdBuffer[0];
        switch (ch) {
          case 'l': case '-':
            setState(() { _kbdBuffer += 'l'; _kbdState = _KbdState.turnLeftAmt; });
          case 'r': case '+':
            setState(() { _kbdBuffer += 'r'; _kbdState = _KbdState.turnRightAmt; });
          case 'L': _queueDelayable(CmdTurnLeft(lbl, 2), 'L');
          case 'R': _queueDelayable(CmdTurnRight(lbl, 2), 'R');
          case 't': setState(() { _kbdBuffer += 't'; _kbdState = _KbdState.towards; });
          // Absolute directions — all delayable
          case 'w': _queueDelayable(CmdTurnDir(lbl, 0), 'w');
          case 'e': _queueDelayable(CmdTurnDir(lbl, 1), 'e');
          case 'd': _queueDelayable(CmdTurnDir(lbl, 2), 'd');
          case 'c': _queueDelayable(CmdTurnDir(lbl, 3), 'c');
          case 'x': _queueDelayable(CmdTurnDir(lbl, 4), 'x');
          case 'z': _queueDelayable(CmdTurnDir(lbl, 5), 'z');
          case 'a': _queueDelayable(CmdTurnDir(lbl, 6), 'a');
          case 'q': _queueDelayable(CmdTurnDir(lbl, 7), 'q');
        }

      // tl [dir] — direction letter is the AMOUNT to turn left (NOT destination).
      // In relative context, 'a' means delay (@), not the 270° direction step.
      // Valid amounts: w=0 e=1 d=2 c=3 x=4 z=5 q=7  (no 'a' — that's delay)
      case _KbdState.turnLeftAmt:
        final lbl = _kbdBuffer[0];
        const leftMap = {'w':0,'e':1,'d':2,'c':3,'x':4,'z':5,'q':7};
        if (leftMap.containsKey(ch)) {
          _queueDelayable(CmdTurnLeft(lbl, leftMap[ch]!), ch);
        } else if (ch == 'a' || ch == '@') {
          // 'a' in relative context = delay trigger; default 45° left
          _queueDelayable(CmdTurnLeft(lbl, 1), '');
          _startDelay(); // immediately transition to delay setup
        } else {
          // unexpected — execute default 45° and discard char
          _queueDelayable(CmdTurnLeft(lbl, 1), '');
        }

      case _KbdState.turnRightAmt:
        final lbl = _kbdBuffer[0];
        const rightMap = {'w':0,'e':1,'d':2,'c':3,'x':4,'z':5,'q':7};
        if (rightMap.containsKey(ch)) {
          _queueDelayable(CmdTurnRight(lbl, rightMap[ch]!), ch);
        } else if (ch == 'a' || ch == '@') {
          _queueDelayable(CmdTurnRight(lbl, 1), '');
          _startDelay();
        } else {
          _queueDelayable(CmdTurnRight(lbl, 1), '');
        }

      // Command was just executed; player may optionally type a/@bN to add
      // a delay retroactively (sets delayedAtBeacon on the plane).
      case _KbdState.delayable:
        if (ch == 'a' || ch == '@') {
          _startDelay();
        } else {
          // Non-delay char: close the delay window, re-process in idle
          setState(() { _kbdBuffer = ''; _kbdState = _KbdState.idle; _pendingCmd = null; });
          _processKbdChar(ch, game);
        }

      // Typed a/@; waiting for 'b' or '*' (beacon specifier)
      case _KbdState.delayAtBeacon:
        if (ch == 'b' || ch == '*') {
          setState(() { _kbdBuffer += 'b'; _kbdState = _KbdState.delayAtBeaconNum; });
        }

      // Typed ab; waiting for beacon number
      case _KbdState.delayAtBeaconNum:
        if (RegExp(r'^[0-9]$').hasMatch(ch)) {
          final beaconNo = int.parse(ch) - 1;
          final pending = _pendingCmd;
          if (pending != null && beaconNo >= 0 &&
              beaconNo < game.scenario.beacons.length) {
            // The inner command already executed; CmdWithDelay re-applies its
            // direction/circling effect then freezes it until the beacon.
            game.applyCommand(CmdWithDelay(pending.planeLabel, pending, beaconNo));
          }
          setState(() { _kbdBuffer = ''; _kbdState = _KbdState.idle; _pendingCmd = null; });
        }

      case _KbdState.towards:
        switch (ch) {
          case 'b': case '*':
            setState(() { _kbdBuffer += 'b'; _kbdState = _KbdState.towardBeacon; });
          case 'e':
            setState(() { _kbdBuffer += 'e'; _kbdState = _KbdState.towardExit; });
          case 'a':
            setState(() { _kbdBuffer += 'a'; _kbdState = _KbdState.towardAirport; });
        }

      case _KbdState.towardBeacon:
        _resolveToward(ch, DestType.beacon, game.scenario.beacons.length, game);

      case _KbdState.towardExit:
        _resolveToward(ch, DestType.exit, game.scenario.exits.length, game);

      case _KbdState.towardAirport:
        _resolveToward(ch, DestType.airport, game.scenario.airports.length, game);

      case _KbdState.alt:
        final lbl = _kbdBuffer[0];
        if (RegExp(r'^[0-9]$').hasMatch(ch)) {
          // Altitude is immediate-only (not delayable)
          _execReset(CmdAltitude(lbl, int.parse(ch)), game);
        } else if (ch == '+' || ch == 'c') {
          setState(() { _kbdBuffer += ch; _kbdState = _KbdState.altClimb; });
        } else if (ch == '-' || ch == 'd') {
          setState(() { _kbdBuffer += ch; _kbdState = _KbdState.altDescend; });
        }

      case _KbdState.altClimb:
        if (RegExp(r'^[0-9]$').hasMatch(ch)) {
          _execReset(CmdAltitudeRelative(_kbdBuffer[0], int.parse(ch)), game);
        }

      case _KbdState.altDescend:
        if (RegExp(r'^[0-9]$').hasMatch(ch)) {
          _execReset(CmdAltitudeRelative(_kbdBuffer[0], -int.parse(ch)), game);
        }
    }
  }

  // Execute a delayable command immediately, then open a brief window where
  // the player can type a/@bN to add a beacon delay retroactively.
  void _queueDelayable(AtcCommand cmd, String suffix) {
    final game = _game;
    if (game != null) game.applyCommand(cmd);
    setState(() {
      _pendingCmd = cmd;          // kept so _startDelay can wrap it
      _kbdBuffer += suffix;
      _kbdState = _KbdState.delayable;
    });
  }

  // Transition to delay-at-beacon setup after a/@ is typed.
  void _startDelay() {
    setState(() {
      _kbdBuffer += '@';
      _kbdState = _KbdState.delayAtBeacon;
    });
  }

  void _resolveToward(String ch, DestType type, int count, AtcGame game) {
    if (!RegExp(r'^[0-9]$').hasMatch(ch)) return;
    final n = int.parse(ch) - 1;
    if (n >= 0 && n < count) {
      _queueDelayable(CmdTurnToward(_kbdBuffer[0], type, n), '$ch');
    } else {
      setState(() { _kbdBuffer = ''; _kbdState = _KbdState.idle; _pendingCmd = null; });
    }
  }

  void _execReset(AtcCommand cmd, AtcGame game) {
    game.applyCommand(cmd);
    setState(() { _kbdBuffer = ''; _kbdState = _KbdState.idle; _pendingCmd = null; });
  }

  // ── End-game dialog ───────────────────────────────────────────────────────

  void _showEndDialog() {
    final game = _game!;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Incident!'),
        content: Text(game.lossReason ?? 'Unknown incident'),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(context); _startGame(); },
            child: const Text('New game'),
          ),
          TextButton(
            onPressed: () { Navigator.pop(context); Navigator.pop(context); },
            child: const Text('Main menu'),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scenarios = _scenarios;
    if (scenarios == null || _game == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final game = _game!;
    final sc = game.scenario;

    return Scaffold(
      backgroundColor: const Color(0xFF050F05),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A2A0A),
        foregroundColor: const Color(0xFF90FF90),
        title: Text(
          'ATC: ${sc.name}',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
        ),
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.map),
            tooltip: 'Change map',
            onSelected: (idx) { setState(() => _scenarioIdx = idx); _startGame(); },
            itemBuilder: (_) => scenarios
                .asMap()
                .entries
                .map((e) => PopupMenuItem(value: e.key, child: Text(e.value.$1)))
                .toList(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'New game',
            onPressed: _startGame,
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        // Wide (ChromeOS / macOS / landscape tablet): radar left, sidebar right.
        // Narrow (portrait phone): radar top, compact panel bottom.
        const sidebarW = 185.0;
        final useWide = constraints.maxWidth >= 520;

        if (useWide) {
          final radarW = constraints.maxWidth - sidebarW;
          final cellSize = [radarW / sc.width, constraints.maxHeight / sc.height]
              .reduce((a, b) => a < b ? a : b);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRadar(game, cellSize),
              Container(width: 1, color: const Color(0xFF1A5C1A)),
              Expanded(child: _buildSidebar(game)),
            ],
          );
        } else {
          const panelH = 170.0;
          final cellSize = [
            constraints.maxWidth / sc.width,
            (constraints.maxHeight - panelH) / sc.height,
          ].reduce((a, b) => a < b ? a : b);
          return Column(children: [
            _buildRadar(game, cellSize),
            SizedBox(height: panelH, child: _buildPanel(game)),
          ]);
        }
      }),
    );
  }

  Widget _buildRadar(AtcGame game, double cellSize) {
    final sc = game.scenario;
    return GestureDetector(
      onTapUp: (d) => _handleRadarTap(d.localPosition, cellSize),
      child: SizedBox(
        width: cellSize * sc.width,
        height: cellSize * sc.height,
        child: CustomPaint(
          painter: AtcPainter(game,
              selectedLabel: _selectedLabel, cellSize: cellSize),
        ),
      ),
    );
  }

  // ── Right sidebar (wide layout) ────────────────────────────────────────────

  Widget _buildSidebar(AtcGame game) {
    final active = game.planes
        .where((p) => p.status != PlaneStatus.gone)
        .toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    final airborne = active.where((p) => p.isAirborne).toList();
    final ground   = active.where((p) => !p.isAirborne).toList();

    const mono = TextStyle(fontFamily: 'monospace', fontSize: 12);
    const dimGreen  = Color(0xFF3A7A3A);
    const normGreen = Color(0xFF80FF80);

    return Container(
      color: const Color(0xFF0A2A0A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time / safe
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
            child: Text(
              'Time: ${game.tick}   Safe: ${game.safeExits}',
              style: mono.copyWith(color: normGreen),
            ),
          ),
          // Column header
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
            child: Text('pl  dt   comm',
                style: mono.copyWith(color: dimGreen, fontSize: 11)),
          ),
          const Divider(height: 1, color: Color(0xFF1A5C1A)),
          // Airborne planes
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ...airborne.map((p) => _buildPlaneRow(p)),
                if (ground.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: Text('── ground ──',
                        style: mono.copyWith(color: dimGreen, fontSize: 10)),
                  ),
                  ...ground.map((p) => _buildPlaneRow(p)),
                ],
              ],
            ),
          ),
          // Command section (when a plane is selected)
          if (_selectedLabel != null && game.planeByLabel(_selectedLabel!) != null) ...[
            const Divider(height: 1, color: Color(0xFF1A5C1A)),
            _buildSidebarCommands(game.planeByLabel(_selectedLabel!)!, game),
          ],
          // Keyboard status
          const Divider(height: 1, color: Color(0xFF1A5C1A)),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
            child: _kbdStatusLine(),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaneRow(Plane p) {
    final isSelected = p.label == _selectedLabel;
    final color = isSelected       ? const Color(0xFFFFFF00)
                : p.isLowFuel      ? const Color(0xFFFFAA00)
                :                    const Color(0xFF80FF80);

    // "B9* E7: Circle" — fixed-width fields
    final plField = '${p.displayLabel}${p.altitude}${p.isLowFuel ? "*" : " "}';
    final dtField = '${p.destChar}${p.destNo + 1}';
    final line    = '$plField $dtField: ${p.commandDesc}';

    return GestureDetector(
      onTap: () => _selectPlane(p.label),
      child: Container(
        color: isSelected ? const Color(0xFF1A1A00) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(line,
            style: TextStyle(
                fontFamily: 'monospace', fontSize: 12, color: color)),
      ),
    );
  }

  Widget _buildSidebarCommands(Plane plane, AtcGame game) {
    return Container(
      color: const Color(0xFF070F07),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: switch (_panelMode) {
        _PanelMode.none || _PanelMode.top => _sidebarTopButtons(plane, game),
        _PanelMode.altitude               => _sidebarAltButtons(plane),
        _PanelMode.turn                   => _sidebarTurnButtons(plane),
        _PanelMode.goTo                   => _sidebarGoToButtons(plane, game),
      },
    );
  }

  Widget _sidebarTopButtons(Plane plane, AtcGame game) => Wrap(
    spacing: 6, runSpacing: 4,
    children: [
      _cmdBtn('Alt',    () => setState(() => _panelMode = _PanelMode.altitude)),
      _cmdBtn('Turn',   () => setState(() => _panelMode = _PanelMode.turn)),
      _cmdBtn('Go To',  () => setState(() => _panelMode = _PanelMode.goTo)),
      _cmdBtn('Circ',   () => _sendCommand(CmdCircle(plane.label))),
      _cmdBtn(plane.status == PlaneStatus.ignored ? 'Unmk' : 'Ign',
              () => _sendCommand(plane.status == PlaneStatus.ignored
                  ? CmdUnmark(plane.label) : CmdIgnore(plane.label))),
      _cmdBtn('✕', _dismissPanel),
    ],
  );

  Widget _sidebarAltButtons(Plane plane) {
    final goalAlt = switch (plane.destType) {
      DestType.airport => 0, DestType.exit => 9, DestType.beacon => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Text('Altitude (goal: ${goalAlt ?? "—"})',
              style: const TextStyle(color: Color(0xFF90FF90),
                  fontFamily: 'monospace', fontSize: 11)),
          const Spacer(), _backBtn(),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 4, runSpacing: 4,
          children: List.generate(10, (alt) => _altBtn(
            alt == 0 ? '▼' : '$alt',
            alt == plane.altitude,
            alt == goalAlt && alt != plane.altitude,
            () => _sendCommand(CmdAltitude(plane.label, alt)),
          )),
        ),
      ],
    );
  }

  Widget _sidebarTurnButtons(Plane plane) {
    const dirs = [('N',0),('NE',1),('E',2),('SE',3),('S',4),('SW',5),('W',6),('NW',7)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          const Text('Turn', style: TextStyle(color: Color(0xFF90FF90),
              fontFamily: 'monospace', fontSize: 11)),
          const SizedBox(width: 8),
          _cmdBtn('Circ', () => _sendCommand(CmdCircle(plane.label))),
          const Spacer(), _backBtn(),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 4, runSpacing: 4,
          children: dirs.map((d) => _dirBtn(d.$1, d.$2 == plane.dir,
              () => _sendCommand(CmdTurnDir(plane.label, d.$2)))).toList(),
        ),
      ],
    );
  }

  Widget _sidebarGoToButtons(Plane plane, AtcGame game) {
    final sc = game.scenario;
    final items = <(String, DestType, int)>[
      for (var i = 0; i < sc.exits.length;    i++) ('Ex${i+1}',  DestType.exit,    i),
      for (var i = 0; i < sc.airports.length; i++) ('Ap${i+1}',  DestType.airport, i),
      for (var i = 0; i < sc.beacons.length;  i++) ('Bc${i+1}',  DestType.beacon,  i),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          const Text('Go to', style: TextStyle(color: Color(0xFF90FF90),
              fontFamily: 'monospace', fontSize: 11)),
          const Spacer(), _backBtn(),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 4, runSpacing: 4,
          children: items.map((item) {
            final isDest = plane.destType == item.$2 && plane.destNo == item.$3;
            return _cmdBtn(isDest ? '★${item.$1}' : item.$1,
                () => _sendCommand(CmdTurnToward(plane.label, item.$2, item.$3)));
          }).toList(),
        ),
      ],
    );
  }

  void _handleRadarTap(Offset pos, double cellSize) {
    final game = _game!;
    final col = (pos.dx / cellSize).floor();
    final row = (pos.dy / cellSize).floor();
    for (final p in game.planes) {
      if (p.status == PlaneStatus.gone) continue;
      if (p.x == col && p.y == row) { _selectPlane(p.label); return; }
    }
    _dismissPanel();
  }

  // ── Command panel ─────────────────────────────────────────────────────────

  Widget _buildPanel(AtcGame game) {
    final plane = _selectedLabel == null ? null : game.planeByLabel(_selectedLabel!);
    if (_selectedLabel != null && plane == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _dismissPanel());
    }

    final commandArea = (plane == null || _panelMode == _PanelMode.none)
        ? _buildIdleHelp()
        : switch (_panelMode) {
            _PanelMode.none     => _buildIdleHelp(),
            _PanelMode.top      => _buildTopPanel(plane, game),
            _PanelMode.altitude => _buildAltitudePanel(plane),
            _PanelMode.turn     => _buildTurnPanel(plane),
            _PanelMode.goTo     => _buildGoToPanel(plane, game),
          };

    return Container(
      color: const Color(0xFF0A2A0A),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Always-visible plane list
          _buildPlaneList(game),
          const Divider(height: 1, color: Color(0xFF1A5C1A)),
          // Command area
          Expanded(child: commandArea),
        ],
      ),
    );
  }

  Widget _buildPlaneList(AtcGame game) {
    final active = game.planes.where((p) => p.status != PlaneStatus.gone).toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    if (active.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text('No planes yet   t:${game.tick}  safe:${game.safeExits}',
            style: const TextStyle(color: Color(0xFF3A7A3A), fontFamily: 'monospace', fontSize: 11)),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: active.map((p) {
          final isSelected = p.label == _selectedLabel;
          final color = isSelected
              ? const Color(0xFFFFFF00)
              : p.isLowFuel
                  ? const Color(0xFFFFAA00)
                  : const Color(0xFF60D060);
          return GestureDetector(
            onTap: () => _selectPlane(p.label),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF2A2A00)
                    : const Color(0xFF0A1A0A),
                border: Border.all(color: color, width: isSelected ? 1.5 : 0.5),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '${p.infoLabel}: ${p.commandDesc}',
                style: TextStyle(
                    color: color, fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildIdleHelp() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Tap a plane chip above, or type its letter on the keyboard.',
              style: TextStyle(color: Color(0xFF40A040), fontSize: 12)),
          const Spacer(),
          _kbdStatusLine(),
        ],
      ),
    );
  }

  Widget _buildTopPanel(Plane plane, AtcGame game) {
    return Container(
      color: const Color(0xFF0A2A0A),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Text(
              '${plane.label.toUpperCase()}  '
              'Alt ${plane.altitude}→${plane.newAltitude}  '
              '${plane.type == PlaneType.jet ? "JET" : "PROP"}  '
              'Fuel ${plane.fuel}  → ${plane.destDescription}',
              style: TextStyle(
                color: plane.isLowFuel
                    ? const Color(0xFFFFAA00)
                    : const Color(0xFF90FF90),
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _dismissPanel,
              child: const Icon(Icons.close, size: 16, color: Color(0xFF60D060)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _cmdBtn('Altitude', () => setState(() => _panelMode = _PanelMode.altitude)),
            const SizedBox(width: 8),
            _cmdBtn('Turn', () => setState(() => _panelMode = _PanelMode.turn)),
            const SizedBox(width: 8),
            _cmdBtn('Go To', () => setState(() => _panelMode = _PanelMode.goTo)),
            const SizedBox(width: 8),
            _cmdBtn(
              plane.status == PlaneStatus.ignored ? 'Unignore' : 'Ignore',
              () => _sendCommand(plane.status == PlaneStatus.ignored
                  ? CmdUnmark(plane.label)
                  : CmdIgnore(plane.label)),
            ),
          ]),
          const Spacer(),
          _kbdStatusLine(),
        ],
      ),
    );
  }

  Widget _buildAltitudePanel(Plane plane) {
    // Highlight the "goal" altitude so the player knows where to aim:
    // airport destination → 0 (land), exit destination → 9 (exit altitude).
    final goalAlt = switch (plane.destType) {
      DestType.airport => 0,
      DestType.exit    => 9,
      DestType.beacon  => null,
    };

    return Container(
      color: const Color(0xFF0A2A0A),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            const Text('Set altitude:',
                style: TextStyle(
                    color: Color(0xFF90FF90), fontFamily: 'monospace')),
            const SizedBox(width: 8),
            Text(
              goalAlt != null
                  ? '(goal: $goalAlt${goalAlt == 0 ? " to land" : " to exit"})'
                  : '',
              style: const TextStyle(
                  color: Color(0xFF60D060), fontFamily: 'monospace',
                  fontSize: 11),
            ),
            const Spacer(),
            _backBtn(),
          ]),
          const SizedBox(height: 8),
          // Altitudes 0–9.  0 = land at airport.  9 = exit altitude.
          Row(children: List.generate(10, (alt) {
            final isCurrent = alt == plane.altitude;
            final isGoal = alt == goalAlt;
            return Padding(
              padding: const EdgeInsets.only(right: 5),
              child: _altBtn(
                alt == 0 ? '▼' : '$alt',
                isCurrent,
                isGoal && !isCurrent,
                () => _sendCommand(CmdAltitude(plane.label, alt)),
              ),
            );
          })),
        ],
      ),
    );
  }

  Widget _buildTurnPanel(Plane plane) {
    const dirs = [
      ('N', 0), ('NE', 1), ('E', 2), ('SE', 3),
      ('S', 4), ('SW', 5), ('W', 6), ('NW', 7),
    ];
    return Container(
      color: const Color(0xFF0A2A0A),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            const Text('Turn heading:',
                style: TextStyle(
                    color: Color(0xFF90FF90), fontFamily: 'monospace')),
            const SizedBox(width: 8),
            _cmdBtn('Circle', () => _sendCommand(CmdCircle(plane.label))),
            const Spacer(),
            _backBtn(),
          ]),
          const SizedBox(height: 8),
          Row(children: dirs.map((d) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _dirBtn(d.$1, d.$2 == plane.dir,
                () => _sendCommand(CmdTurnDir(plane.label, d.$2))),
          )).toList()),
        ],
      ),
    );
  }

  Widget _buildGoToPanel(Plane plane, AtcGame game) {
    final sc = game.scenario;
    final items = <(String, DestType, int)>[
      for (var i = 0; i < sc.exits.length; i++) ('Exit ${i+1}', DestType.exit, i),
      for (var i = 0; i < sc.airports.length; i++) ('Aprt ${i+1}', DestType.airport, i),
      for (var i = 0; i < sc.beacons.length; i++) ('Bcn ${i+1}', DestType.beacon, i),
    ];
    return Container(
      color: const Color(0xFF0A2A0A),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            const Text('Go to:',
                style: TextStyle(
                    color: Color(0xFF90FF90), fontFamily: 'monospace')),
            const Spacer(),
            _backBtn(),
          ]),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: items.map((item) {
              final isDest = plane.destType == item.$2 && plane.destNo == item.$3;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _cmdBtn(
                  isDest ? '★ ${item.$1}' : item.$1,
                  () => _sendCommand(CmdTurnToward(plane.label, item.$2, item.$3)),
                ),
              );
            }).toList()),
          ),
        ],
      ),
    );
  }

  // ── Shared small widgets ──────────────────────────────────────────────────

  Widget _cmdBtn(String label, VoidCallback onPressed) => OutlinedButton(
    style: OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFF80FF80),
      side: const BorderSide(color: Color(0xFF40A040)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    onPressed: onPressed,
    child: Text(label,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
  );

  Widget _altBtn(String label, bool current, bool goal, VoidCallback onPressed) =>
      SizedBox(
        width: 30,
        height: 30,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: current
                ? const Color(0xFF1A5C1A)
                : const Color(0xFF0A2A0A),
            foregroundColor: goal
                ? const Color(0xFFFFFF00)
                : const Color(0xFF90FF90),
            side: BorderSide(
              color: current
                  ? const Color(0xFF80FF80)
                  : goal
                      ? const Color(0xFFFFFF00)
                      : const Color(0xFF40A040),
            ),
            padding: EdgeInsets.zero,
          ),
          onPressed: onPressed,
          child: Text(label, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
        ),
      );

  Widget _dirBtn(String label, bool current, VoidCallback onPressed) =>
      OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor:
              current ? const Color(0xFFFFFF00) : const Color(0xFF80FF80),
          side: BorderSide(
              color: current
                  ? const Color(0xFFFFFF00)
                  : const Color(0xFF40A040)),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: onPressed,
        child: Text(label,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      );

  Widget _backBtn() => TextButton(
    onPressed: () => setState(() => _panelMode = _PanelMode.top),
    child: const Text('← Back',
        style: TextStyle(color: Color(0xFF60D060), fontSize: 12)),
  );

  Widget _kbdStatusLine() {
    final hint = switch (_kbdState) {
      _KbdState.idle         => 'kbd: [a-z] select plane  Enter=fast-forward',
      _KbdState.plane        => 'kbd: t=turn  a=alt  c=circle  m=mark  u=unmark  i=ignore',
      _KbdState.turn         => 'kbd: l/r=turn±  L/R=90°  t=towards  w/e/d/c/x/z/a/q=abs',
      _KbdState.turnLeftAmt  => 'kbd: [wedcxzq]=amount (e=45 d=90…)  a/@=delay  Enter=45°',
      _KbdState.turnRightAmt => 'kbd: [wedcxzq]=amount (e=45 d=90…)  a/@=delay  Enter=45°',
      _KbdState.delayable    => 'kbd: Enter=execute now  a/@=delay until beacon',
      _KbdState.delayAtBeacon    => 'kbd: b/* for beacon',
      _KbdState.delayAtBeaconNum => 'kbd: [1-${_game!.scenario.beacons.length}] beacon number',
      _KbdState.towards      => 'kbd: b/*=beacon  e=exit  a=airport',
      _KbdState.towardBeacon => 'kbd: [1-${_game!.scenario.beacons.length}] beacon number',
      _KbdState.towardExit   => 'kbd: [1-${_game!.scenario.exits.length}] exit number',
      _KbdState.towardAirport=> 'kbd: [1-${_game!.scenario.airports.length}] airport number',
      _KbdState.alt          => 'kbd: [0-9]=set alt  +/c=climb  -/d=descend',
      _KbdState.altClimb     => 'kbd: [1-9] floors to climb',
      _KbdState.altDescend   => 'kbd: [1-9] floors to descend',
    };
    return Row(children: [
      if (_kbdBuffer.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF1A5C1A),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            '$_kbdBuffer█',
            style: const TextStyle(
                color: Color(0xFFCCFFCC), fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        const SizedBox(width: 8),
      ],
      Expanded(
        child: Text(hint,
            style: const TextStyle(
                color: Color(0xFF3A7A3A), fontFamily: 'monospace', fontSize: 11),
            overflow: TextOverflow.ellipsis),
      ),
      const Text('Esc=cancel',
          style: TextStyle(
              color: Color(0xFF2A5A2A), fontFamily: 'monospace', fontSize: 10)),
    ]);
  }
}

enum _PanelMode { none, top, altitude, turn, goTo }

enum _KbdState {
  idle, plane, turn,
  turnLeftAmt, turnRightAmt,   // after tl/tr — optional amount, or a/@ for delay
  delayable,                   // command queued; Enter=execute, a/@=add delay
  delayAtBeacon,               // typed a/@; waiting for b/*
  delayAtBeaconNum,            // typed ab; waiting for beacon number
  towards, towardBeacon, towardExit, towardAirport,
  alt, altClimb, altDescend,
}
