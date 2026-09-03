import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../state/app_state.dart';

/// The one "Edit name" dialog, opened from every place a name is shown.
///
/// Pulled out of the rail so the pane header could use it too: two copies would
/// have been two sets of error handling for one rename, and the second is the
/// one that quietly stops matching.
///
/// Keyboard-complete on purpose — autofocus, Enter submits, Escape closes —
/// because the way in is a double click but the way through should never need
/// the mouse again.
Future<void> showAgentRenameDialog(
  BuildContext context,
  AppNotifier notifier,
  String machineId,
  String agentId,
  String currentName,
) async {
  final controller = TextEditingController(text: currentName);
  String? error;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Edit name'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                style: grid.kFieldTextStyle,
                onSubmitted: (_) async {
                  final result = await notifier.renameAgent(
                    machineId,
                    agentId,
                    controller.text,
                  );
                  if (result == null) {
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  } else {
                    setDialogState(() => error = result);
                  }
                },
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(
                  error!,
                  style: TextStyle(
                    color: grid.AppPalette.dangerFill,
                    fontFamily: grid.AppFont.sans,
                    fontSize: 11.2,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final result = await notifier.renameAgent(
                machineId,
                agentId,
                controller.text,
              );
              if (result == null) {
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              } else {
                setDialogState(() => error = result);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
}
