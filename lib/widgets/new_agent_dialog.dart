import 'package:flutter/material.dart';

import '../grid/grid_agent_override.dart';
import '../grid/grid_selection_store.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'engine_identity.dart';
import 'remote_folder_picker.dart';

/// Engines the harness CLI can point at a grid, mirroring `GRID_ENGINE_ENV` in
/// `autonomous-harness/cli/src/lib/gridLaunch.ts`.
///
/// Display only. The CLI is the enforcement point — it refuses every other engine rather than
/// quietly launching it on its own login — so a stale list here costs a warning that did not
/// appear, never a launch that should have worked. Keep both in sync anyway.
const Set<String> kGridCapableEngines = {'claude'};

/// Mirrors the harness CLI's `BYPASS_PERMISSION_FLAGS`
/// (autonomous-harness/cli/src/lib/engineLaunch.ts) 1:1 — this is UI-only display + gating, the CLI
/// is the actual enforcement point. An engine absent here shows no checkbox at all rather than
/// guessing a flag for a CLI we haven't verified. Keep both maps in sync.
const Map<String, String> kEngineBypassPermissionFlag = {
  'claude': '--dangerously-skip-permissions',
  'codex': '--dangerously-bypass-approvals-and-sandbox',
  'cursor': '--force',
  'opencode': '--auto',
};

Future<void> showNewAgentDialog(
  BuildContext context,
  AppNotifier notifier,
  String machineId,
) {
  return showDialog<void>(
    context: context,
    builder: (context) =>
        _NewAgentDialog(notifier: notifier, machineId: machineId),
  );
}

class _NewAgentDialog extends StatefulWidget {
  final AppNotifier notifier;
  final String machineId;

  const _NewAgentDialog({required this.notifier, required this.machineId});

  @override
  State<_NewAgentDialog> createState() => _NewAgentDialogState();
}

class _NewAgentDialogState extends State<_NewAgentDialog> {
  late String _engine = allEngines.first.id;
  String? _folder;
  bool _bypassPermission = false;
  bool _submitting = false;
  String? _error;

  Future<void> _browse() async {
    final picked = await showRemoteFolderPicker(
      context,
      notifier: widget.notifier,
      machineId: widget.machineId,
      initialPath: _folder,
    );
    if (picked != null) setState(() => _folder = picked);
  }

  Future<void> _submit() async {
    final folder = _folder;
    if (folder == null || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    // A relay key is minted per launch, so it is fetched here rather than held
    // in the store. Null when no grid is picked, which leaves the frame exactly
    // as it was before this feature existed.
    final GridAgentOverride? grid;
    try {
      grid = await resolveGridAgentOverride();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        // Named rather than swallowed: falling back to the engine's own login
        // would silently run the agent somewhere the user did not choose.
        _error =
            'Could not get a key for '
            '${gridSelectionStore.value.label}: $error';
      });
      return;
    }
    final error = await widget.notifier.createAgent(
      widget.machineId,
      engine: _engine,
      folder: folder,
      bypassPermission:
          _bypassPermission && kEngineBypassPermissionFlag.containsKey(_engine),
      grid: grid,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _submitting = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bypassFlag = kEngineBypassPermissionFlag[_engine];
    return AlertDialog(
      title: const Text('New agent'),
      // Scrollable because the content grows: the grid warning below, the
      // permissions block and an error line can all be present at once, and a
      // short window would otherwise clip the actions instead of the fields.
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _FieldLabel('ENGINE'),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _engine,
                isExpanded: true,
                items: [
                  for (final identity in allEngines)
                    DropdownMenuItem(
                      value: identity.id,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          EngineMark(engine: identity.id, size: 14),
                          const SizedBox(width: 8),
                          Text(
                            identity.label,
                            style: const TextStyle(fontSize: 13.5),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _engine = value;
                    if (!kEngineBypassPermissionFlag.containsKey(value)) {
                      _bypassPermission = false;
                    }
                  });
                },
              ),
              const SizedBox(height: 14),
              const _FieldLabel('WORKING FOLDER'),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: InputDecorator(
                      decoration: const InputDecoration(isDense: true),
                      child: Text(
                        _folder ?? 'Choose a folder on this machine…',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 13.5,
                          color: _folder == null
                              ? AppColors.muted
                              : AppColors.textSoft,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: _browse,
                    child: const Text(
                      'Browse…',
                      style: TextStyle(fontSize: 13.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const _FieldLabel('RUNS ON'),
              const SizedBox(height: 6),
              _RunsOnRow(engine: _engine),
              if (bypassFlag != null) ...[
                const SizedBox(height: 14),
                const _FieldLabel('PERMISSIONS'),
                const SizedBox(height: 6),
                CheckboxListTile(
                  value: _bypassPermission,
                  onChanged: (value) =>
                      setState(() => _bypassPermission = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text(
                    'Bypass permission prompts',
                    style: TextStyle(fontFamily: AppFonts.sans, fontSize: 13.5),
                  ),
                  subtitle: Text(
                    'Uses $bypassFlag',
                    style: TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11.2,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(
                    color: AppColors.danger,
                    fontFamily: AppFonts.sans,
                    fontSize: 11.2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(fontSize: 13.5)),
        ),
        FilledButton(
          onPressed: _folder == null || _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create agent', style: TextStyle(fontSize: 13.5)),
        ),
      ],
    );
  }
}

/// What this agent will be pointed at, read from the sidebar's own choice.
///
/// Shown, not offered: the picker lives in one place so the two cannot drift,
/// and this is the moment the choice actually takes effect — which is exactly
/// when a user wants to see it stated.
class _RunsOnRow extends StatelessWidget {
  const _RunsOnRow({required this.engine});

  final String engine;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GridSelection>(
      valueListenable: gridSelectionStore,
      builder: (context, chosen, _) {
        final refused = chosen.hasGrid && !kGridCapableEngines.contains(engine);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InputDecorator(
              decoration: const InputDecoration(isDense: true),
              child: Text(
                chosen.hasGrid
                    ? '${chosen.label} · ${chosen.model ?? 'Auto'}'
                    : "This engine's own login — pick a grid in the sidebar",
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontSize: 13.5,
                  color: chosen.hasGrid ? AppColors.textSoft : AppColors.muted,
                ),
              ),
            ),
            if (refused) ...[
              const SizedBox(height: 6),
              Text(
                '${engineIdentity(engine).label} cannot be pointed at a grid — it is configured by '
                'a file rather than its environment. Creating this agent will be refused; choose '
                'Claude Code, or clear the grid in the sidebar.',
                style: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontSize: 11.2,
                  height: 1.4,
                  color: AppColors.warning,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: AppColors.mutedStrong,
        fontFamily: AppFonts.sans,
        fontSize: 11.2,
        letterSpacing: 0.6,
      ),
    );
  }
}
