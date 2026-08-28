import '../terminal/terminal_session.dart';

/// One tile in the terminal grid.
///
/// The INTENT (which agent this tile is for) and the live [session] are kept
/// apart on purpose. A restored layout names agents on machines that have not
/// answered yet, and machines answer in an order this side does not decide —
/// so a tile has to be able to exist, and say what it is waiting for, before
/// there is anything to attach. The same split is what lets a tile survive its
/// machine going offline and coming back without the grid reshuffling around
/// it.
class TerminalPane {
  TerminalPane({required this.id, required this.machineId, this.agentId});

  /// Stable for the tile's whole life, including across a machine going away
  /// and returning. Widget keys hang off this: keying on the agent id instead
  /// would tear down and rebuild the WebView — and with it the scrollback the
  /// user was reading — every time a tile were reassigned.
  final int id;

  String machineId;

  /// Null means the tile is about the MACHINE, not an agent on it.
  ///
  /// A machine that needs linking cannot list its agents — that is what needing
  /// a link means — so there is no agent to put in a tile, and without this the
  /// link screen would have no way onto the screen at all. The same shape
  /// carries "this machine has no agents yet".
  String? agentId;

  TerminalSession? session;

  /// Whether this tile shows the composer textbox under its terminal.
  ///
  /// Only ever consulted for a remote machine — that is the one where typing straight into the
  /// pane pays a network round trip per keystroke. On by default, and remembered, so the choice
  /// survives a restart the way the rest of the layout does.
  bool composerVisible = true;
}

/// A tile as it survives a restart: intent only, never the session.
class PaneLayoutEntry {
  const PaneLayoutEntry({
    required this.machineId,
    required this.agentId,
    this.composerVisible = true,
  });

  final String machineId;
  final String agentId;
  final bool composerVisible;

  Map<String, dynamic> toJson() => {
    'machineId': machineId,
    'agentId': agentId,
    'composerVisible': composerVisible,
  };

  static PaneLayoutEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final machineId = raw['machineId'];
    final agentId = raw['agentId'];
    if (machineId is! String || machineId.isEmpty) return null;
    if (agentId is! String || agentId.isEmpty) return null;
    final composer = raw['composerVisible'];
    return PaneLayoutEntry(
      machineId: machineId,
      agentId: agentId,
      // Absent means a layout written before the composer existed. Those default to ON, matching a
      // tile the user has never had an opinion about — never to OFF, which would read as a setting
      // they chose.
      composerVisible: composer is bool ? composer : true,
    );
  }
}
