import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../theme/app_theme.dart';

/// An agent in flight between the rail and the grid.
class AgentDragRef {
  const AgentDragRef({
    required this.machineId,
    required this.agentId,
    required this.name,
  });

  final String machineId;
  final String agentId;
  final String name;
}

/// Whether a rail row is currently being dragged, readable by the grid.
///
/// A [ValueNotifier] beside the widgets rather than a field on AppNotifier: it
/// describes a hand on a mouse for the length of one gesture, and nothing about
/// machines, agents or sessions. Putting it in the domain state would mean every
/// listener of that state rebuilding on mouse-down, and would outlive the
/// gesture in a place where later readers would reasonably expect it to mean
/// something.
///
/// The grid watches it to reveal the empty slot: an "add a tile" cell that is
/// always on screen would permanently halve a single terminal to advertise a
/// feature, so it appears when there is something to drop into it and goes away
/// again afterwards.
final agentDrag = ValueNotifier<AgentDragRef?>(null);

/// The one way out of a tile, in the one place every tile puts it.
class PaneCloseButton extends StatelessWidget {
  const PaneCloseButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Tooltip(
      message: 'Close pane',
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(Icons.close, size: 15, color: AppColors.muted),
        splashRadius: 13,
        constraints: const BoxConstraints.tightFor(width: 26, height: 26),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
