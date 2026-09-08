// What the dial turning to an agent does to the grid.
//
// The dial's carousel is built around the desk: the tiles first, in tile order,
// and past either end of them the ring carries on into agents that have no
// tile. Landing on one of those is what puts it on the desk — it replaces the
// tile at the end it was reached from, so the grid stays the size the user
// chose and the tile that changes is the one they walked off.
//
// WHICH end is the daemon's answer, not this side's: it holds the flat list of
// every agent on every machine, so it is the only side that can tell whether an
// agent sits before the first tile or after the last. Here that arrives as
// `edge`, and these tests are about obeying it.
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/models.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/state/terminal_pane.dart';

AppNotifier _notifier() => AppNotifier(
  config: AppConfig.dev,
  authSession: AuthSession(),
  configStore: null,
);

Agent _agent(String id) => Agent.fromJson({
  'id': id,
  'name': id,
  'engine': 'claude',
  'terminal': {
    'runtimes': [
      {'backend': 'tmux', 'paneId': '%1'},
    ],
  },
});

MachineState _machine(AppNotifier app, String id, List<String> agentIds) {
  final machine = Machine(
    machineId: id,
    apiKey: '',
    authMode: MachineAuthMode.remote,
    name: id,
    status: 'online',
  );
  final state = MachineState(machine)
    ..nodeOnline =
        false // keeps _attachSession from dialling out
    ..agentLoadStatus = AgentLoadStatus.loaded
    ..agents = [for (final agentId in agentIds) _agent(agentId)];
  app.machines = [...app.machines, machine];
  app.machineStates[id] = state;
  return state;
}

List<String?> _desk(AppNotifier app) => [for (final p in app.panes) p.agentId];

Future<AppNotifier> _withTiles(List<String> agentIds) async {
  final app = _notifier();
  _machine(app, 'm1', ['a1', 'a2', 'a3', 'a4', 'a5']);
  for (final id in agentIds) {
    await app.assignAgentToPane(null, 'm1', id);
  }
  return app;
}

void main() {
  test('the roster the daemon builds its ring from is in tile order', () {
    // The section in the rail, the tile order on screen and the dial's carousel
    // are one list. This is the end of it the window owns: what it reports is
    // the order it draws, so the numbers beside the rail rows and the steps
    // under the thumb are the same walk.
    final app = _notifier();
    _machine(app, 'm1', ['a1', 'a2', 'a3']);
    app.panes.addAll([
      TerminalPane(id: 1, machineId: 'm1', agentId: 'a3'),
      TerminalPane(id: 2, machineId: 'm1', agentId: 'a1'),
    ]);
    expect(_desk(app), ['a3', 'a1']);
    app.dispose();
  });

  test('an agent past the LAST tile replaces the last tile', () async {
    final app = await _withTiles(['a1', 'a2', 'a3']);
    await app.selectAgentFromDial('m1', 'a4', edge: DeskEdge.tail);

    expect(_desk(app), ['a1', 'a2', 'a4']);
    expect(app.panes.length, 3, reason: 'the grid keeps the size it was');
    app.dispose();
  });

  test('an agent past the FIRST tile replaces the first tile', () async {
    // The half of the rule that a "replace the last one" reading gets wrong: an
    // agent reached by walking BACK off the desk appears at the far end, and the
    // focus jumps across the grid to meet it.
    final app = await _withTiles(['a2', 'a3', 'a4']);
    await app.selectAgentFromDial('m1', 'a1', edge: DeskEdge.head);

    expect(_desk(app), ['a1', 'a3', 'a4']);
    app.dispose();
  });

  test('the tile at that end becomes the focused one', () async {
    final app = await _withTiles(['a1', 'a2', 'a3']);
    await app.selectAgentFromDial('m1', 'a5', edge: DeskEdge.tail);

    expect(app.focusedPane?.agentId, 'a5');
    app.dispose();
  });

  test('walking on replaces the SAME tile again, not another one', () async {
    // The emergent shape of the rule, and the reason it is comfortable: the tile
    // at the end you are walking off becomes a rotating preview while every
    // other tile stays exactly where it was.
    final app = await _withTiles(['a1', 'a2', 'a3']);
    await app.selectAgentFromDial('m1', 'a4', edge: DeskEdge.tail);
    await app.selectAgentFromDial('m1', 'a5', edge: DeskEdge.tail);

    expect(_desk(app), ['a1', 'a2', 'a5']);
    app.dispose();
  });

  test('an agent that already has a tile is focused, never duplicated', () async {
    // The daemon sends no edge for one of these, but the guard does not lean on
    // that: opening the same agent twice would have the two tiles take over each
    // other's terminal, so it is refused whatever the wire says.
    final app = await _withTiles(['a1', 'a2', 'a3']);
    await app.selectAgentFromDial('m1', 'a1', edge: DeskEdge.tail);

    expect(_desk(app), ['a1', 'a2', 'a3']);
    expect(app.focusedPane?.agentId, 'a1');
    app.dispose();
  });

  test('with one tile, either end replaces that tile', () async {
    // Both ends of a one-tile desk are the same tile, which makes the dial a
    // plain browser of the list.
    final app = await _withTiles(['a3']);
    await app.selectAgentFromDial('m1', 'a4', edge: DeskEdge.tail);
    expect(_desk(app), ['a4']);

    await app.selectAgentFromDial('m1', 'a2', edge: DeskEdge.head);
    expect(_desk(app), ['a2']);
    app.dispose();
  });

  test('with no tiles at all, one is opened rather than replaced', () async {
    // There is no end of the desk to land on, so "look at this" can only mean
    // opening it.
    final app = _notifier();
    _machine(app, 'm1', ['a1', 'a2']);
    await app.selectAgentFromDial('m1', 'a2', edge: DeskEdge.tail);

    expect(_desk(app), ['a2']);
    app.dispose();
  });

  // ── a notification asks for a tile of its own ───────────────────────────────
  //
  // Turning the dial says where the eye is and a tile moves to match. Tapping a
  // notification is a different verb: the turn just FINISHED, so it is something
  // new to look at, not a replacement for what the person was already watching.
  test('a notification opens a NEW tile, leaving the others alone', () async {
    final app = await _withTiles(['a1', 'a2']);
    await app.openAgentFromDial('m1', 'a3');

    expect(_desk(app), ['a1', 'a2', 'a3']);
    expect(app.focusedPane?.agentId, 'a3');
    app.dispose();
  });

  test('at the ceiling it reuses the LAST tile rather than refusing', () async {
    // Refusing would make the notification a liar: it says there is something to
    // see and then does nothing when pressed. The last tile is already the place
    // the desk treats as where things arrive — it is what the dial's own right
    // edge replaces.
    final app = _notifier();
    _machine(app, 'm1', [for (var i = 0; i < AppNotifier.maxPanes + 1; i++) 'a$i']);
    for (var i = 0; i < AppNotifier.maxPanes; i++) {
      await app.assignAgentToPane(null, 'm1', 'a$i');
    }
    expect(app.canAddPane, isFalse);
    final untouched = [for (final p in app.panes.take(app.panes.length - 1)) p.agentId];

    await app.openAgentFromDial('m1', 'a${AppNotifier.maxPanes}');

    expect(app.panes.length, AppNotifier.maxPanes, reason: 'the grid holds');
    expect(app.panes.last.agentId, 'a${AppNotifier.maxPanes}');
    expect(
      [for (final p in app.panes.take(app.panes.length - 1)) p.agentId],
      untouched,
      reason: 'every other tile is where it was',
    );
    app.dispose();
  });

  test('a notification for a tile already open only focuses it', () async {
    final app = await _withTiles(['a1', 'a2', 'a3']);
    app.focusPane(app.panes.first.id);

    await app.openAgentFromDial('m1', 'a3');

    expect(_desk(app), ['a1', 'a2', 'a3'], reason: 'nothing opened twice');
    expect(app.focusedPane?.agentId, 'a3');
    app.dispose();
  });

  // ── the wire ────────────────────────────────────────────────────────────────
  //
  // Everything above calls the method directly, which proves the rule and
  // nothing about the frame that carries it. These drive the real `dial_focus`
  // frame through the app's own handler, because a typo in one string is
  // exactly how this feature would look installed and be inert — and that is
  // the failure that actually happened, twice, on the real dial.
  Future<void> dialFocus(
    AppNotifier app,
    String agentId, {
    String? edge,
  }) => app.handleEventForTest('m1', {
    'type': 'dial_focus',
    'payload': {
      'machineId': 'm1',
      'agentId': agentId,
      'edge': ?edge,
    },
  });

  test('a dial_focus frame naming the tail edge replaces the last tile', () async {
    final app = await _withTiles(['a1', 'a2', 'a3']);
    await dialFocus(app, 'a4', edge: 'tail');

    expect(_desk(app), ['a1', 'a2', 'a4']);
    app.dispose();
  });

  test('a dial_focus frame naming the head edge replaces the first tile', () async {
    final app = await _withTiles(['a2', 'a3', 'a4']);
    await dialFocus(app, 'a1', edge: 'head');

    expect(_desk(app), ['a1', 'a3', 'a4']);
    app.dispose();
  });

  test('a dial_focus frame for a tile that is open only moves the focus', () async {
    // Walking WITHIN the desk. The daemon sends no edge for these, and the grid
    // must not change at all — this is the swipe people make constantly.
    final app = await _withTiles(['a1', 'a2', 'a3']);
    app.focusPane(app.panes.first.id);
    await dialFocus(app, 'a3');

    expect(_desk(app), ['a1', 'a2', 'a3']);
    expect(app.focusedPane?.agentId, 'a3');
    app.dispose();
  });

  test('an edge the app does not know is treated as none, not as a guess', () async {
    // A newer daemon naming a third edge must not silently replace a tile at
    // whichever end this build happens to check first.
    final app = await _withTiles(['a1', 'a2', 'a3']);
    app.focusPane(app.panes[1].id);
    await dialFocus(app, 'a4', edge: 'middle');

    expect(_desk(app), ['a1', 'a4', 'a3'], reason: 'the ordinary path');
    app.dispose();
  });

  test('a dial_open frame opens a tile, where dial_focus would replace one', () async {
    // The two verbs side by side, driven through the app's own handler: the same
    // agent, one frame each, and the grid ends up a different size.
    final app = await _withTiles(['a1', 'a2']);
    await app.handleEventForTest('m1', {
      'type': 'dial_open',
      'payload': {'machineId': 'm1', 'agentId': 'a4'},
    });
    expect(_desk(app), ['a1', 'a2', 'a4']);

    await dialFocus(app, 'a5', edge: 'tail');
    expect(_desk(app), ['a1', 'a2', 'a5'], reason: 'focus replaces, open adds');
    app.dispose();
  });

  test('no edge means the ordinary selection path, untouched', () async {
    // Every other caller of the dial's focus — and the app itself — still gets
    // "replace the focused tile", which is what a click on the rail does.
    final app = await _withTiles(['a1', 'a2', 'a3']);
    app.focusPane(app.panes[1].id);
    await app.selectAgentFromDial('m1', 'a4');

    expect(_desk(app), ['a1', 'a4', 'a3']);
    app.dispose();
  });
}
