import 'package:flutter/material.dart';

import '../../grid/grid_access_type.dart';
import '../../grid/grid_mutations_controller.dart';
import '../../grid/grid_name.dart';
import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_select_field.dart';
import '../../shared/widgets/labeled_field.dart';

/// Make a grid: a name, who may join, and one button.
///
/// Keyboard-complete like the app's other dialogs — autofocus, Enter submits,
/// Escape closes — because the way in is a click but the way through should
/// never need the mouse again.
///
/// Resolves to the new grid's name on success, so the caller can name it in the
/// line it shows afterwards, and to null when the dialog was cancelled.
Future<String?> showCreateGridDialog(
  BuildContext context, {
  required GridMutationsController controller,

  /// The domain this account may gate a grid by, from `GET /v1/grid/me`. Null
  /// means it may not, and the rule is then not offered at all — see
  /// [accessTypesFor] for why it is absent rather than greyed out.
  String? gatedDomain,
}) {
  controller.resetCreate();
  return showAppDialog<String>(
    context: context,
    builder: (_) =>
        _CreateGridDialog(controller: controller, gatedDomain: gatedDomain),
  );
}

class _CreateGridDialog extends StatefulWidget {
  const _CreateGridDialog({required this.controller, this.gatedDomain});

  final GridMutationsController controller;
  final String? gatedDomain;

  @override
  State<_CreateGridDialog> createState() => _CreateGridDialogState();
}

class _CreateGridDialogState extends State<_CreateGridDialog> {
  final _name = TextEditingController();
  GridAccessType _type = GridAccessType.fallback;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onResult);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onResult);
    _name.dispose();
    super.dispose();
  }

  /// Close on success, handing the name back. The warning is not shown here —
  /// the dialog is about to be gone, and a caveat that flashes for a frame is
  /// no better than one that was never printed. The caller has it in
  /// [CreateGridState] and shows it where it will be read.
  void _onResult() {
    if (widget.controller.createState is! CreateGridDone) return;
    final done = widget.controller.createState as CreateGridDone;
    if (mounted) Navigator.of(context).pop(done.network.displayName);
  }

  void _submit(GridAccessType type) {
    widget.controller.create(name: _name.text, type: type);
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.createState;
        final submitting = state is CreateGridSubmitting;
        final error = state is CreateGridFailed ? state.message : null;

        // A rule that is not offered must not stay selected: the picker would
        // draw nothing chosen while `_type` still sent `domain-restricted`.
        final types = accessTypesFor(
          canRestrictToDomain: widget.gatedDomain != null,
        );
        final selected = types.contains(_type)
            ? _type
            : GridAccessType.fallback;

        // Escape and a click on the barrier pop a dialog even when its Cancel
        // button is disabled — so without this, escaping a submit closed the
        // form while the create carried on: the grid was made, `grid use`
        // repointed this computer at it, and the caller's snackbar never fired
        // because the dialog resolved to null. The user cancelled something
        // that happened anyway, silently. Dismissal is blocked only while the
        // call is in flight; an idle form still closes on Escape, which is the
        // keyboard-completeness this dialog is built for.
        return PopScope(
          canPop: !submitting,
          child: AlertDialog(
            title: const Text('Create provider'),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FieldLabel('Name'),
                  TextField(
                    key: const Key('create-grid-name-field'),
                    controller: _name,
                    autofocus: true,
                    enabled: !submitting,
                    maxLength: gridNameMaxLength,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(selected),
                    style: grid.kFieldTextStyle,
                    decoration: const InputDecoration(
                      hintText: 'my-team-provider',
                      // The counter is furniture for a limit nobody is near: it
                      // sits under the field from the first keystroke to say
                      // "0/64". `maxLength` still enforces it.
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 14),
                  const FieldLabel('Who can join'),
                  Opacity(
                    opacity: submitting ? 0.5 : 1,
                    child: IgnorePointer(
                      ignoring: submitting,
                      child: AppSelectField<GridAccessType>(
                        key: const Key('create-grid-access-field'),
                        value: selected,
                        options: [
                          for (final type in types)
                            SelectOption(
                              value: type,
                              label: accessLabelFor(
                                type,
                                domain: widget.gatedDomain,
                              ),
                              // The rule's own sentence, in the row where it is
                              // read: this menu IS the control, and the labels
                              // alone do not say what each rule admits.
                              detail: accessDescriptionFor(
                                type,
                                domain: widget.gatedDomain,
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() => _type = value),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // The rule's own sentence, under the field rather than inside
                  // the menu: the closed control is only as wide as itself and
                  // would arrive clipped mid-clause, which reads as a rendering
                  // bug rather than as an explanation.
                  Text(
                    accessDescriptionFor(selected, domain: widget.gatedDomain),
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
                onPressed: submitting
                    ? null
                    : () => Navigator.of(context).pop(),
                // Ink, not accent. Cancel is the way out, not a suggestion — two
                // coloured words in one corner give the dialog two things that
                // look like the answer.
                style: TextButton.styleFrom(
                  foregroundColor: grid.AppPalette.textSecondary,
                ),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('create-grid-submit'),
                onPressed: submitting ? null : () => _submit(selected),
                child: submitting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create'),
              ),
            ],
          ),
        );
      },
    );
  }
}
