import 'package:flutter/material.dart';

import '../../grid/grid_mutations_controller.dart';
import '../../grid/grid_name.dart';
import '../../grid/grid_network.dart';
import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/labeled_field.dart';

/// Rename a grid you own.
///
/// Only the name people see changes — the grid keeps working for everyone
/// already on it, which the dialog says out loud so nobody fears breaking
/// their setup by touching it.
///
/// Resolves to the new name on success, and to null when it was cancelled or
/// nothing was changed.
Future<String?> showRenameGridDialog(
  BuildContext context, {
  required GridMutationsController controller,
  required GridNetwork network,
}) {
  // The controller outlives this dialog, so a failure from a previous attempt
  // would otherwise greet the user on reopen.
  controller.resetRename();
  return showAppDialog<String>(
    context: context,
    builder: (_) => _RenameGridDialog(controller: controller, network: network),
  );
}

class _RenameGridDialog extends StatefulWidget {
  const _RenameGridDialog({required this.controller, required this.network});

  final GridMutationsController controller;
  final GridNetwork network;

  @override
  State<_RenameGridDialog> createState() => _RenameGridDialogState();
}

class _RenameGridDialogState extends State<_RenameGridDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.network.name,
  );

  /// Held so the selection can be applied the moment the field takes focus.
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Select the whole name, so the first keystroke replaces it — Finder's
    // rename, where you type over the old name rather than clearing it
    // yourself. Otherwise an autofocused field parks the caret at one end and
    // makes you backspace through a name you had already decided to discard.
    //
    // On the focus event, not at construction: `autofocus` sets its own
    // selection when the field first takes focus, which lands AFTER the
    // controller is built and quietly replaces anything set there.
    _focus.addListener(_selectAllOnFocus);
  }

  void _selectAllOnFocus() {
    if (!_focus.hasFocus) return;
    _focus.removeListener(_selectAllOnFocus);
    _name.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _name.text.length,
    );
  }

  @override
  void dispose() {
    _focus.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    // Nothing to save: close rather than spend a round-trip renaming a grid to
    // what it is already called.
    if (name == widget.network.name.trim()) {
      Navigator.of(context).pop();
      return;
    }
    final error = await widget.controller.rename(
      networkId: widget.network.networkId,
      name: name,
    );
    if (!mounted || error != null) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.renameState;
        final saving = state is RenameGridSaving;
        final error = state is RenameGridFailed ? state.message : null;

        // Blocked only while the save is in flight — see the same note on
        // [showCreateGridDialog]. Escape on an idle form still closes it.
        return PopScope(
          canPop: !saving,
          child: AlertDialog(
            title: const Text('Rename provider'),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FieldLabel('Provider name'),
                  TextField(
                    key: const Key('rename-grid-name-field'),
                    controller: _name,
                    focusNode: _focus,
                    autofocus: true,
                    enabled: !saving,
                    maxLength: gridNameMaxLength,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    style: grid.kFieldTextStyle,
                    decoration: const InputDecoration(counterText: ''),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Only the name changes. Everyone on this provider keeps their '
                    'access, and apps you connected keep working.',
                    style: TextStyle(
                      color: grid.AppPalette.textSecondary,
                      fontFamily: grid.AppFont.sans,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      error,
                      style: TextStyle(
                        color: grid.AppPalette.dangerFill,
                        fontFamily: grid.AppFont.sans,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.of(context).pop(),
                // Ink, not accent — the accent belongs to Save alone.
                style: TextButton.styleFrom(
                  foregroundColor: grid.AppPalette.textSecondary,
                ),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('rename-grid-submit'),
                onPressed: saving ? null : _submit,
                child: saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
  }
}
