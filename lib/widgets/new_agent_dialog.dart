import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../analytics/analytics.dart';
import '../core/engine_availability.dart';
import '../core/codex_profiles.dart';
import '../grid/grid_agent_override.dart';
import '../grid/grid_api_client.dart';
import '../grid/grid_selection_store.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_checkbox.dart';
import '../shared/widgets/app_select_field.dart';
import '../shared/widgets/labeled_field.dart';
import '../state/app_state.dart';
import 'engine_identity.dart';
import 'codex_profile_field.dart';
import 'remote_folder_picker.dart';

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

/// Opens the New agent dialog for [machineId].
///
/// [source] names the door it was opened by — `machine_row`, `rail_empty`,
/// `pane_empty` or `shortcut` — and is required rather than defaulted, so a
/// fifth entry point has to say which one it is instead of quietly filing
/// itself under an existing name.
Future<void> showNewAgentDialog(
  BuildContext context,
  AppNotifier notifier,
  String machineId, {
  required String source,
  // Injectable only so a test can drive a real Create click without a network call — the same seam
  // GridNetworksController/GridModelsController already expose. Production never passes one, so
  // _submit's resolveGridAgentOverride falls back to its own default (real) client.
  @visibleForTesting GridApiClient? gridApiClient,
}) {
  // Reported here rather than at each call site: the doors are four and
  // growing, and one that forgets to track is a hole in the funnel that only
  // shows up as a number quietly being too small.
  analytics.newAgentOpened(source: source);
  return showDialog<void>(
    context: context,
    builder: (context) => _NewAgentDialog(
      notifier: notifier,
      machineId: machineId,
      gridApiClient: gridApiClient,
    ),
  );
}

class _NewAgentDialog extends StatefulWidget {
  final AppNotifier notifier;
  final String machineId;
  final GridApiClient? gridApiClient;

  const _NewAgentDialog({
    required this.notifier,
    required this.machineId,
    this.gridApiClient,
  });

  @override
  State<_NewAgentDialog> createState() => _NewAgentDialogState();
}

class _NewAgentDialogState extends State<_NewAgentDialog> {
  late String _engine = allEngines.first.id;
  String? _folder;
  LocalCodexProfile? _codexProfile;
  bool _codexProfilesBusy = true;
  bool _bypassPermission = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // Which engines this machine actually has. Asked here rather than at
    // connect because the answer costs the far side one interactive shell per
    // engine and is only ever read on this screen. Deferred a frame so the
    // probe's first notifyListeners() does not land mid-build.
    //
    // `force`, every time this dialog opens. A cached answer is worth nothing
    // here: engines arrive and leave through a terminal this app never sees —
    // `npm i -g opencode-ai`, `npm uninstall -g`, a venv deleted out from under
    // a symlink — and an install this very dialog started makes its own stored
    // answer stale the moment it finishes. Re-asking is bounded (one sweep, on
    // a deliberate user action) and the stored rows keep rendering until the new
    // answer lands, so nothing blanks.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.notifier.probeEngines(widget.machineId, force: true));
    });
  }

  /// What this machine said about the selected engine, or null while the probe
  /// is still out (or when the machine could not answer).
  ///
  /// Null is deliberately not "missing": until the machine has spoken, this
  /// dialog behaves exactly as it did before the probe existed. Claiming an
  /// engine is absent on no evidence would send someone to install one they
  /// already have.
  EngineAvailability? _availability(String engine) {
    final machine = widget.notifier.stateOf(widget.machineId);
    if (machine == null || !machine.engines.loaded) return null;
    return machine.engines[engine];
  }

  /// The row's note about installation, or null when there is nothing to say —
  /// which covers both "it is here" and "the machine has not answered yet".
  ///
  /// Those two produce the same absent note on purpose. A row cannot say
  /// "not installed" on the strength of a probe that has not returned; the
  /// dialog's own preflight panel is where the settled answer is stated, and it
  /// arrives a moment later without moving anything.
  String? _engineInstallNote(String engine) {
    final entry = _availability(engine);
    if (entry == null || entry.installed) return null;
    // Only the state Harness cannot fix keeps words. It is rare, it is the one
    // the reader has to act on themselves, and a glyph for "we cannot help you
    // here" would be a glyph nobody decodes in time.
    return entry.installable ? null : 'not installed';
  }

  /// The one caveat worth printing beside an engine's name, or none.
  ///
  /// Stated in the row rather than discovered after picking: each of these
  /// changes what the engine can do, and finding out by watching the checkbox
  /// vanish — or by reading `command not found` out of a pane — is a worse way
  /// to learn it. One note per row, so the row stays a name with a caveat
  /// rather than a sentence.
  ///
  /// The grid note wins when it applies, because an engine that cannot be
  /// pointed at a grid is refused outright: saying "will install" there would
  /// promise a launch that is still going to be refused. But it applies ONLY
  /// with a grid actually chosen — with none, every engine runs on its own
  /// account and its grid-capability decides nothing, so printing a caveat
  /// about grids down half the list is a warning about a feature the reader
  /// has not opted into.
  ///
  /// It says "grid not supported", never "no grid": those two words are what
  /// the picker calls the deliberate choice to use none, and the same words for
  /// "this engine cannot" and "you asked for none" is how one is read as the
  /// other.
  String? _engineNote(String engine, bool gridChosen) {
    if (gridChosen && !kGridCapableEngines.contains(engine)) {
      return 'grid not supported';
    }
    return _engineInstallNote(engine) ??
        (kEngineBypassPermissionFlag.containsKey(engine)
            ? null
            : 'no bypass flag');
  }

  /// This engine is absent and Harness would install it before launching.
  bool _willInstallEngine(String engine) {
    final entry = _availability(engine);
    return entry != null && !entry.installed && entry.installable;
  }

  /// The engine will have to be installed before it can run.
  bool get _willInstall => _willInstallEngine(_engine);

  /// The machine was ASKED which engines it has, and could not answer.
  ///
  /// Distinct from the probe still being out, which is the ordinary first
  /// second of this dialog and says nothing worth printing. This one is
  /// settled, and it is what stands between the panel and every claim below:
  /// a remote box on an older CLI does not know `engines_probe` — and does not
  /// refuse it either, it simply never replies, so this arrives 30s later —
  /// and until it is rendered the panel says "Ready to launch" over an engine
  /// nobody checked for, which the create then fails on at the far end.
  bool get _engineCheckFailed {
    final machine = widget.notifier.stateOf(widget.machineId);
    if (machine == null) return false;
    return !machine.engines.loaded && machine.engines.error != null;
  }

  /// The engine is missing but this machine cannot safely auto-install it — for
  /// example, an explicit ENGINE_PATH override points at a missing file, or an
  /// older CLI has no recipe. Stated rather than silently offered, because the
  /// create WILL fail and the person needs to fix that machine first.
  bool get _missingAndUnfixable {
    final entry = _availability(_engine);
    return entry != null && !entry.installed && !entry.installable;
  }

  /// The system panel is modal and slow enough to notice. Without this the
  /// button stays live and a second click stacks a second panel behind the
  /// first — on macOS that leaves one the user cannot reach until they dismiss
  /// the one on top.
  bool _picking = false;
  bool _folderHovered = false;
  bool _bypassHovered = false;
  String? _error;

  /// Whether the machine this agent will run on is the computer the app is
  /// running on, which is what decides where the folder is picked.
  ///
  /// Read per build rather than cached: `localOnly`/`localEndpoint` are settled
  /// by `_refreshMachines`, which can land while this dialog is open.
  bool get _machineIsThisComputer =>
      widget.notifier.stateOf(widget.machineId)?.isLocalMachine ?? false;

  bool get _waitingForCodexProfile =>
      _engine == 'codex' &&
      !gridSelectionStore.value.hasGrid &&
      _availability('codex')?.supportsCodexHome == true &&
      _codexProfilesBusy;

  /// [Machine.displayName], not `name` — the latter is nullable and a machine
  /// that never got one would title the dialog "New agent on null".
  String get _machineName =>
      widget.notifier.stateOf(widget.machineId)?.machine.displayName ??
      'this machine';

  Future<void> _browse() async {
    if (_picking) return;
    // The agent runs on the MACHINE, so the folder has to exist on the machine
    // — which is the whole reason this branches.
    //
    // On this computer that is the OS's own panel (`getDirectoryPath` is
    // NSOpenPanel on macOS, IFileDialog on Windows, the desktop's file-chooser
    // portal on Linux): it is the picker the user already knows, it can reach
    // sidebar favourites, iCloud and network mounts that `fs_list_dir` never
    // enumerates, and the app is not sandboxed (`macos/Runner/*.entitlements`
    // declares no `com.apple.security.app-sandbox`) so the path it returns is
    // one the CLI can actually open — no security-scoped bookmark to hand over.
    //
    // On any other machine a native panel is not merely wrong but actively
    // misleading: it browses THIS Mac and hands back a path that does not exist
    // over there, so the agent would fail to start in a folder the user watched
    // themselves select. That case keeps the in-app browser, which walks the
    // remote filesystem over the `fs_list_dir` RPC.
    setState(() => _picking = true);
    try {
      final picked = _machineIsThisComputer
          ? await getDirectoryPath(initialDirectory: _folder)
          : await showRemoteFolderPicker(
              context,
              notifier: widget.notifier,
              machineId: widget.machineId,
              initialPath: _folder,
            );
      if (!mounted) return;
      setState(() {
        _picking = false;
        if (picked != null) _folder = picked;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _picking = false;
        _error = 'Could not open the folder picker: $error';
      });
    }
  }

  Future<void> _submit() async {
    final folder = _folder;
    if (folder == null || _submitting || _waitingForCodexProfile) return;
    final engine = _engine;
    final profile = _codexProfile;
    final selection = gridSelectionStore.value;
    final bypassPermission =
        _bypassPermission && kEngineBypassPermissionFlag.containsKey(engine);
    setState(() {
      _submitting = true;
      _error = null;
    });
    // A relay key is minted per launch, so it is fetched here rather than held
    // in the store. Null when no grid is picked, which leaves the frame exactly
    // as it was before this feature existed.
    //
    // No model is passed: a new agent always launches on Auto — the grid picks
    // the model, and nothing goes on the wire. Changing it afterwards is the
    // agent view's own header menu (see AgentModelMenu).
    final GridAgentOverride? gridOverride;
    try {
      gridOverride = await resolveGridAgentOverride(
        client: widget.gridApiClient,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        // Named rather than swallowed: falling back to the engine's own
        // account would silently run the agent somewhere the user did not
        // choose.
        _error =
            'Could not get a key for '
            '${gridSelectionStore.value.label}: $error';
      });
      return;
    }
    if (!mounted) return;
    if (gridSelectionStore.value != selection) {
      setState(() {
        _submitting = false;
        _error = 'The provider changed. Review the account and try again.';
      });
      return;
    }
    final error = await widget.notifier.createAgent(
      widget.machineId,
      engine: engine,
      folder: folder,
      bypassPermission: bypassPermission,
      grid: gridOverride,
      // Keep the explicit choice even if machine discovery changes mid-submit.
      // The notifier must reject a now-remote target, never use its default login.
      codexHome: engine == 'codex' && gridOverride == null
          ? profile?.path
          : null,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _submitting = false;
        _error = error;
      });
      return;
    }
    // Tracked here, not in `createAgent`: this is the only place that can tell
    // Auto from the engine's own login. Both reach the notifier as a null
    // override, and `onGrid` is what separates them downstream.
    analytics.agentCreated(
      engine: engine,
      onGrid: gridOverride != null,
      bypassPermission: bypassPermission,
      model: gridOverride?.model,
      networkId: gridOverride?.networkId,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Reads colour tokens, and lives in an Overlay — a top-down rebuild never
    // reaches it, so it has to watch for itself or it strands on the palette it
    // opened with.
    grid.AppTheme.watch(context);
    return ListenableBuilder(
      listenable: widget.notifier,
      builder: (context, _) => _buildDialog(context),
    );
  }

  Widget _buildDialog(BuildContext context) {
    final bypassFlag = kEngineBypassPermissionFlag[_engine];

    return ValueListenableBuilder<GridSelection>(
      valueListenable: gridSelectionStore,
      builder: (context, chosen, _) {
        // The CLI refuses an engine it cannot point at a grid rather than
        // quietly running it on its own account, so the dialog already knows this
        // launch will fail. Gating the button here is what stops a round trip
        // that only ever ends in an error the user was already warned about.
        //
        // The escape hatch is the sidebar's grid picker set to "No grid", which
        // sends `gridOverride: null` — the same frame the CLI accepts for ANY
        // engine — and which the summary's refusal note names.
        final refused =
            chosen.hasGrid && !kGridCapableEngines.contains(_engine);
        final canCreate =
            _folder != null &&
            !refused &&
            !_submitting &&
            !_waitingForCodexProfile;

        return AlertDialog(
          title: Text('New agent on $_machineName'),
          titleTextStyle: Theme.of(context).textTheme.titleMedium,
          // Scrollable because the content grows: the summary's refusal note,
          // the permissions block and an error line can all be present at once,
          // and a short window would otherwise clip the actions.
          content: SizedBox(
            width: _dialogWidth,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final choices = AbsorbPointer(
                        absorbing: _submitting,
                        child: _choices(bypassFlag, chosen.hasGrid),
                      );
                      final summary = _NewAgentSummary(
                        engine: _engine,
                        folder: _folder,
                        machineName: _machineName,
                        machineIsThisComputer: _machineIsThisComputer,
                        bypassFlag: _bypassPermission ? bypassFlag : null,
                        selection: chosen,
                        refused: refused,
                        installCommand: _willInstall
                            ? _availability(_engine)?.installCommand
                            : null,
                        missingWithoutRecipe: _missingAndUnfixable,
                        checkFailed: _engineCheckFailed,
                        codexProfile: _engine == 'codex' && !chosen.hasGrid
                            ? _codexProfile
                            : null,
                      );
                      // Below this the two columns would each be too narrow to
                      // hold a path, so the summary goes back on top of the
                      // choices instead of beside them.
                      if (constraints.maxWidth < _stackBelow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            summary,
                            const SizedBox(height: _gapField),
                            choices,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: choices),
                          const SizedBox(width: _gapColumns),
                          SizedBox(width: _summaryWidth, child: summary),
                        ],
                      );
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: _gapBlock),
                    Text(
                      _error!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
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
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: canCreate ? _submit : null,
              child: _submitting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create agent'),
            ),
          ],
        );
      },
    );
  }

  /// The left column: what the user actually decides.
  ///
  /// [gridChosen] only gates the grid note — see [_engineNote]. It is passed in
  /// rather than read off the store here because `build` is already inside the
  /// [ValueListenableBuilder] that watches it, and a second listener would be a
  /// second answer to the same question.
  Widget _choices(String? bypassFlag, bool gridChosen) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Engine'),
        // The app's own picker, not `DropdownButtonFormField`.
        //
        // Material's dropdown renders its own popup, anchors it OVER the field
        // instead of under it, forces the panel to the field's width, and comes
        // out square-cornered and edge-to-edge whatever you pass it — while
        // ignoring both `menuTheme` and `popupMenuTheme`, so it could not be
        // made to match any other menu in this app.
        AppSelectField<String>(
          key: const Key('new-agent-engine-field'),
          value: _engine,
          options: [
            for (final identity in allEngines)
              SelectOption(
                value: identity.id,
                label: identity.label,
                note: _engineNote(identity.id, gridChosen),
                leading: () => EngineMark(engine: identity.id, size: 14),
                // "will install" said in words repeated down a third of the
                // list, and a column of the same two words is a column the eye
                // has to read to discover it says nothing new. The glyph is
                // scanned once; the sentence moves to its tooltip and to the
                // preflight panel, which names the exact command anyway.
                trailing: _willInstallEngine(identity.id)
                    ? () => _InstallMark(engine: identity.id)
                    : null,
              ),
          ],
          onChanged: (value) => setState(() {
            _engine = value;
            _codexProfile = null;
            _codexProfilesBusy = true;
            if (!kEngineBypassPermissionFlag.containsKey(value)) {
              _bypassPermission = false;
            }
          }),
        ),
        if (_engine == 'codex' && !gridChosen) ...[
          const SizedBox(height: _gapField),
          if (_availability('codex')?.supportsCodexHome == true)
            CodexProfileField(
              notifier: widget.notifier,
              machineId: widget.machineId,
              machineIsThisComputer: _machineIsThisComputer,
              value: _codexProfile,
              observedPaths: {
                for (final agent
                    in widget.notifier.stateOf(widget.machineId)!.agents)
                  if (agent.engine == 'codex' && agent.codexHome != null)
                    agent.codexHome!,
              },
              onChanged: (profile) => setState(() => _codexProfile = profile),
              onBusyChanged: (busy) {
                if (_codexProfilesBusy != busy) {
                  setState(() => _codexProfilesBusy = busy);
                }
              },
            )
          else
            Text(
              _availability('codex') == null
                  ? _engineCheckFailed
                        ? 'Could not check Codex profiles. Reopen this dialog to retry.'
                        : 'Checking whether this computer supports Codex profiles…'
                  : 'Update Harness CLI to choose a local Codex profile.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
        const SizedBox(height: _gapField),
        const FieldLabel('Working folder'),
        _FolderControl(
          folder: _folder,
          machineName: _machineName,
          machineIsThisComputer: _machineIsThisComputer,
          picking: _picking,
          hovered: _folderHovered,
          onHover: (value) => setState(() => _folderHovered = value),
          onPressed: _browse,
        ),
        const SizedBox(height: _gapField),
        const FieldLabel('Permissions'),
        if (bypassFlag != null)
          _BypassCheck(
            value: _bypassPermission,
            flag: bypassFlag,
            hovered: _bypassHovered,
            onHover: (value) => setState(() => _bypassHovered = value),
            onChanged: (value) => setState(() => _bypassPermission = value),
          )
        else
          // Not silence: an engine with no checkbox looks identical to one whose
          // checkbox the user simply missed.
          Text(
            '${engineIdentity(_engine).label} has no permission flag this app '
            'can pass — it asks in the terminal.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

/// Wide enough for two columns that both hold a path without wrapping every
/// line; the summary takes [_summaryWidth] and the choices take the rest.
///
/// The summary is the wider of the two, and deliberately: the choices column
/// holds controls that ellipsize cleanly, while the summary holds three strings
/// that must be read whole — a flag as long as
/// `--dangerously-bypass-approvals-and-sandbox`, a hostname, and a path. At an
/// even split the longest flag broke across two lines mid-word.
///
/// 352 is measured, not chosen: the longest flag any engine here passes is
/// `--dangerously-bypass-approvals-and-sandbox` (Codex, 42 characters), which at
/// the 12pt mono this card sets needs ~318px once its two-space continuation
/// indent is counted — plus the card's 12px padding on each side.
const double _dialogWidth = 712;
const double _summaryWidth = 352;

/// The width a string inside the summary actually gets, once the card's own
/// padding is taken off. Exposed so the test that guards the longest flag
/// measures against the real number rather than a copy of it.
@visibleForTesting
const double summaryContentWidth = _summaryWidth - _summaryPad * 2;

const double _summaryPad = 12;

/// The advance of one character at the 12pt SF Mono the summary sets — the face
/// is 0.6em wide, like every monospaced face in this family.
///
/// Used to decide whether a command fits on one line. Measured arithmetically
/// rather than with a `TextPainter`: this runs on every rebuild, and a layout
/// pass to answer a question this cheap is a poor trade.
const double _monoAdvance = 12 * 0.6;

/// Whether `\$ <engine> <flag>` still fits the summary's one line.
bool _fitsOneLine(String engine, String flag) =>
    ('\$ $engine $flag'.length) * _monoAdvance <= summaryContentWidth;

/// A path shortened from its HEAD, so the leaf survives.
///
/// `/Users/macbookpro/Desktop/A` truncated the ordinary way keeps the part
/// every path on the machine shares and drops the only part that identifies it.
/// This drops whole leading segments instead and marks the cut with `…/`, the
/// same shorthand a shell prompt uses:
///
/// ```
/// /Users/macbookpro/work/harness/autonomous-harness-desktop
/// …/harness/autonomous-harness-desktop
/// ```
///
/// Segment-wise rather than character-wise: cutting mid-name reads as a typo,
/// while a dropped segment reads as a path someone abbreviated. Windows paths
/// come back untouched — they are separated by `\`, and a wrong guess about the
/// separator would mangle the string rather than shorten it.
String _ellipsizeHead(String path, double maxWidth) {
  final fits = path.length * _monoAdvance <= maxWidth;
  if (fits || !path.contains('/')) return path;
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  // Never below the leaf: a control too narrow for even that shows the leaf and
  // lets the Text's own ellipsis take the rest.
  for (var drop = 1; drop < segments.length; drop++) {
    final candidate = '…/${segments.skip(drop).join('/')}';
    if (candidate.length * _monoAdvance <= maxWidth) return candidate;
  }
  return '…/${segments.last}';
}

/// Below this the columns stack. Derived from the summary's own width plus the
/// gap and the narrowest a select field stays usable at.
const double _stackBelow = _summaryWidth + _gapColumns + 190;

/// A path or a flag, in the face the user chose for code.
///
/// Built from [grid.AppFont] rather than a literal family so it follows Settings
/// ▸ Terminal, and carries `monoFallback` — without it a user whose chosen face
/// lacks a glyph gets Roboto for that one character.
///
/// One size for every mono string here, taken off the ramp rather than picked
/// per call: the path, the flag under the checkbox and the flag in the command
/// are the same kind of text, and three hand-set sizes is how they stop looking
/// like it. `labelSmall`'s 12 is a step under the 13 of the controls around
/// them, which is where a monospaced face has to sit to read at the same size.
TextStyle _mono({required Color color}) => TextStyle(
  fontFamily: grid.AppFont.mono,
  fontFamilyFallback: grid.AppFont.monoFallback,
  fontSize: 12,
  color: color,
);

/// Wide enough for the longest key the summary states ("Inference"), so the
/// three values line up on one left edge.
const double _factKeyWidth = 62;

// The dialog's spacing scale. Four steps, named, rather than the run of
// 3/6/7/8/10/12/14/16/18 this file grew — a column whose gaps are all slightly
// different is what "the padding feels off" actually is.
//
// `FieldLabel` already carries its own 6px gap to the control it names, so a
// caption never takes a step from here; these are the gaps BETWEEN things.

/// A label and the line it belongs to — the flag under its title.
const double _gapTight = 4;

/// Blocks inside one card: the command, the facts, the reason.
const double _gapBlock = 12;

/// One field and the next, down the choices column.
const double _gapField = 16;

/// The choices column and the summary beside it.
const double _gapColumns = 18;

/// The folder control: one target, not a text box with a button beside it.
///
/// The old shape put a read-only `InputDecorator` next to a `Browse…` button,
/// which read as a field you could type in and as the loudest control in the
/// dialog. Here the whole row is the button — the path is what it displays, and
/// the trailing word says what clicking does.
class _FolderControl extends StatelessWidget {
  const _FolderControl({
    required this.folder,
    required this.machineName,
    required this.machineIsThisComputer,
    required this.picking,
    required this.hovered,
    required this.onHover,
    required this.onPressed,
  });

  final String? folder;
  final String machineName;
  final bool machineIsThisComputer;
  final bool picking;
  final bool hovered;
  final ValueChanged<bool> onHover;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final theme = Theme.of(context);
    final chosen = folder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // [MouseRegion] + [AnimatedContainer], the shape every hoverable control
        // in this app takes — not `InkWell`, whose ripple is a phone idiom and
        // whose hover is instant where the app's is [AppMotion.hover].
        MouseRegion(
          cursor: picking
              ? SystemMouseCursors.progress
              : SystemMouseCursors.click,
          onEnter: (_) => onHover(true),
          onExit: (_) => onHover(false),
          child: GestureDetector(
            onTap: picking ? null : onPressed,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: grid.AppMotion.hover,
              curve: grid.AppMotion.curve,
              constraints: BoxConstraints(
                minHeight: grid.AppControl.heightFieldScaled,
              ),
              // The select field's own padding, so the two controls stacked in
              // this column share one left edge and one right edge.
              padding: const EdgeInsets.only(left: 10, right: 8),
              decoration: BoxDecoration(
                // §1: depth from fill, never a rim. [AppSurface.recess] is the
                // same well [AppSelectField] sits in — a folder is picked the
                // same way an engine is, so it looks the same at rest.
                color: hovered && !picking
                    ? grid.AppSurface.recessHover
                    : grid.AppSurface.recess,
                borderRadius: BorderRadius.circular(grid.AppControl.radius),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: grid.AppControl.iconSize,
                    color: grid.AppPalette.textFaint,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    key: const Key('new-agent-folder-text'),
                    // Aligned left like every other control's content.
                    //
                    // This used to set `TextDirection.rtl` to make a long path
                    // ellipsize from its head, keeping the leaf visible. But
                    // direction drives ALIGNMENT too, so the whole string was
                    // shoved to the trailing edge and left a hole after the
                    // folder glyph — wider the shorter the path, which is why a
                    // remote `/home/node/work` looked worst of all.
                    //
                    // Truncation is a job for the string, not the layout, so the
                    // head is now trimmed in [_ellipsizeHead] and the Text stays
                    // plain LTR.
                    child: LayoutBuilder(
                      builder: (context, constraints) => Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          picking
                              ? 'Waiting for the folder picker…'
                              // Not "on $machineName": the title says which
                              // machine and so does the summary, and a hostname
                              // like `MacBooks-MacBook-Pro.local` spent the
                              // whole control repeating it, then truncated.
                              : chosen == null
                              ? 'Choose a folder…'
                              : _ellipsizeHead(chosen, constraints.maxWidth),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: chosen != null && !picking
                              ? _mono(color: grid.AppPalette.textPrimary)
                              : theme.textTheme.labelMedium?.copyWith(
                                  color: grid.AppPalette.textFaint,
                                ),
                        ),
                      ),
                    ),
                  ),
                  if (!picking) ...[
                    const SizedBox(width: 8),
                    Text(
                      chosen == null ? 'Browse…' : 'Change',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: grid.AppPalette.accentOnSurface,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        // Only the case that needs explaining gets a line. On this computer the
        // OS panel is what everyone expects and saying so is noise; on another
        // machine the in-app browser is the surprising half, so that is the half
        // that speaks.
        if (!machineIsThisComputer) ...[
          const SizedBox(height: _gapTight),
          Text(
            '$machineName is another computer — this browses its folders '
            "through the CLI, not this Mac's.",
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

/// The bypass checkbox, in the app's own row shape.
///
/// Not `CheckboxListTile`: that was the only Material list tile left in the app,
/// and its `dense`/`contentPadding` combination left the box floating well clear
/// of the text it labels and out of line with the fields above it.
class _BypassCheck extends StatelessWidget {
  const _BypassCheck({
    required this.value,
    required this.flag,
    required this.hovered,
    required this.onHover,
    required this.onChanged,
  });

  final bool value;
  final String flag;
  final bool hovered;
  final ValueChanged<bool> onHover;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: GestureDetector(
        onTap: () => onChanged(!value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: grid.AppMotion.hover,
          curve: grid.AppMotion.curve,
          // Bled out to the left so the row's fill lines up with the fields
          // above it, and the text still starts on their left edge once the
          // box and its gap are counted.
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: hovered ? grid.AppSurface.hoverFill : Colors.transparent,
            borderRadius: BorderRadius.circular(grid.AppControl.radius),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Nudged down onto the label's own line: the row is top-aligned
              // so the two-line block reads from its title, and a 16px box
              // centred on a 13pt cap sits a hair proud of it.
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: AppCheckbox(
                  value: value,
                  hovered: hovered,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Bypass permission prompts',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: grid.AppPalette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: _gapTight),
                    Text(flag, style: _mono(color: grid.AppPalette.textFaint)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What this launch actually is, stated before it happens.
///
/// The dialog's four inputs each answer a different question, and the one they
/// add up to — *what will be running, where, on whose account* — was the one
/// thing the old dialog never said. It matters most for the two settings that
/// reach outside this window: a bypass flag turns off an engine's own guardrails
/// on a machine that may not be this one, and a grid sends every token somewhere
/// other than the engine's own account.
///
/// Read-only on purpose, and shaped so: it takes the recessed inset fill, never
/// a field's, so nothing here invites a click.
class _NewAgentSummary extends StatelessWidget {
  const _NewAgentSummary({
    required this.engine,
    required this.folder,
    required this.machineName,
    required this.machineIsThisComputer,
    required this.bypassFlag,
    required this.selection,
    required this.refused,
    this.installCommand,
    this.missingWithoutRecipe = false,
    this.checkFailed = false,
    this.codexProfile,
  });

  final String engine;
  final LocalCodexProfile? codexProfile;
  final String? folder;
  final String machineName;
  final bool machineIsThisComputer;

  /// Non-null only when the box is actually ticked — this states what WILL run,
  /// not what could.
  final String? bypassFlag;
  final GridSelection selection;
  final bool refused;

  /// The line this machine will run before the engine, when the engine is not
  /// there yet. Named in full rather than summarised: installing software on a
  /// computer — and this reaches remote ones — is not something to do behind a
  /// button that says "Create agent".
  final String? installCommand;

  /// The engine is absent and Harness has no install line for it. Distinct from
  /// [installCommand] being null, which is also the state while the machine has
  /// not answered — this one is a settled "we know, and we cannot fix it".
  final bool missingWithoutRecipe;

  /// The machine could not say which engines it has. The opposite settled
  /// answer to [missingWithoutRecipe]: not "we know and cannot fix it" but
  /// "we do not know", which is the one thing this panel may not round off to
  /// "Ready to launch".
  final bool checkFailed;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final theme = Theme.of(context);
    final warn = grid.AppPalette.warn;
    final flag = bypassFlag;
    final install = refused ? null : installCommand;
    final ready = folder != null && !refused;

    final Color dot;
    final String heading;
    if (refused) {
      dot = warn;
      heading = 'Will be refused';
    } else if (missingWithoutRecipe && ready) {
      // Not "refused": the app is not the thing saying no. The create will
      // reach the machine and fail there, and the only useful thing to say is
      // which half is missing.
      dot = warn;
      heading = 'Not installed on this machine';
    } else if (install != null && ready) {
      dot = grid.AppPalette.accentOnSurface;
      heading = 'Will install, then launch';
    } else if (checkFailed && ready) {
      // Faint, not the accent: the accent dot is a claim, and there is nothing
      // here to claim. Not the warning colour either — nothing is wrong with
      // the launch, we simply could not look, and painting an absence of
      // information as a problem would cry wolf on every older remote box.
      dot = grid.AppPalette.textFaint;
      heading = 'Could not check this machine';
    } else if (ready) {
      dot = grid.AppPalette.accentOnSurface;
      heading = 'Ready to launch';
    } else {
      dot = grid.AppPalette.textFaint;
      heading = 'Pick a folder to continue';
    }

    return AnimatedContainer(
      duration: grid.AppMotion.swap,
      curve: grid.AppMotion.curve,
      padding: const EdgeInsets.all(_summaryPad),
      decoration: BoxDecoration(
        // §1: depth comes from fill, and the one rim this app allows belongs to
        // the menu panel — so the refused state is a WASH, not a border. It has
        // to carry on its own in both themes, which a hairline at 45% opacity
        // never did: in light it read as a box someone forgot to finish.
        color: refused ? warn.withValues(alpha: 0.10) : grid.AppSurface.recess,
        borderRadius: BorderRadius.circular(grid.AppControl.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Sized and animated like the status dots elsewhere in the app:
              // the colour is what carries the state, so it moves on
              // [AppMotion.swap] rather than snapping.
              AnimatedContainer(
                duration: grid.AppMotion.swap,
                curve: grid.AppMotion.curve,
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  heading,
                  // Sentence case at [labelSmall]. The tracked 10.5pt caps this
                  // replaced are the web-dashboard idiom `FieldLabel` was made
                  // to retire — see its note; a heading inside the app should
                  // not wear a costume the captions above it just took off.
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: grid.AppPalette.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: _gapBlock),
          // The command, so a flag that disables an engine's prompts is read in
          // the shape it will be typed — and in the warning colour, which is the
          // only place accent-vs-warning carries meaning in this dialog.
          //
          // One line where it fits — which is three of the four engines that take
          // a flag at all — and a wrap only for the one that cannot: Codex's
          // `--dangerously-bypass-approvals-and-sandbox` is 42 characters and
          // overruns this column at any width this dialog can reasonably take.
          // Breaking the other three to keep the long one company would leave
          // most of the card's width empty to no purpose.
          //
          // The break is a real newline the flag carries, not a wrap: a wrap
          // would land mid-word, on a `-` inside the flag, and split the one
          // string here that has to be read whole.
          //
          // No `\` continuation, deliberately. This is not a command anyone can
          // copy — the CLI builds the real one, with a working directory and a
          // tmux session this string never shows — so a shell's line-continuation
          // mark would dress it up as something you could paste and run. The
          // indent alone carries the same "this belongs to the line above".
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '\$ ',
                  style: TextStyle(color: grid.AppPalette.textFaint),
                ),
                TextSpan(text: engine),
                if (flag != null)
                  TextSpan(
                    text: _fitsOneLine(engine, flag) ? ' $flag' : '\n  $flag',
                    style: TextStyle(color: warn),
                  ),
              ],
            ),
            style: _mono(color: grid.AppPalette.textPrimary)
                .copyWith(height: 1.5),
          ),
          const SizedBox(height: _gapBlock),
          _fact(
            context,
            'Folder',
            folder ?? 'not chosen',
            faint: folder == null,
          ),
          _fact(
            context,
            'Machine',
            machineName,
            // Its own line, not a "· " appended to the name. A hostname like
            // `MacBooks-MacBook-Pro.local` fills this column on its own, and
            // the qualifier then wrapped at a hyphen mid-name — a deliberate
            // second line reads as structure where an accidental one reads as
            // a bug.
            note: machineIsThisComputer ? 'this computer' : 'remote',
          ),
          _fact(
            context,
            'Inference',
            // Always Auto: a new agent pins no model, so the grid picks one.
            refused || !selection.hasGrid
                ? codexProfile?.label ??
                      "${engineIdentity(engine).label}'s own account"
                : '${selection.label} · Auto',
            note: codexProfile?.path,
          ),
          if (refused) ...[
            const SizedBox(height: _gapBlock),
            Container(
              padding: const EdgeInsets.only(top: _gapBlock),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: warn.withValues(alpha: 0.28)),
                ),
              ),
              child: Text(
                '${engineIdentity(engine).label} cannot be pointed at a grid — '
                'it offers no way to change where it sends inference. Choose '
                "another engine, or set the sidebar's grid picker to "
                '\u201cNo grid\u201d.',
                style: theme.textTheme.bodySmall?.copyWith(color: warn),
              ),
            ),
          ],
          if (!refused && missingWithoutRecipe) ...[
            const SizedBox(height: _gapBlock),
            Container(
              padding: const EdgeInsets.only(top: _gapBlock),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: warn.withValues(alpha: 0.28)),
                ),
              ),
              child: Text(
                '${engineIdentity(engine).label} is not on $machineName, and '
                'Harness has no install line for it. Install it there first, '
                'or choose another engine.',
                style: theme.textTheme.bodySmall?.copyWith(color: warn),
              ),
            ),
          ],
          if (!refused && checkFailed) ...[
            const SizedBox(height: _gapBlock),
            Container(
              padding: const EdgeInsets.only(top: _gapBlock),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: grid.AppPalette.textFaint.withValues(alpha: 0.28),
                  ),
                ),
              ),
              // Faint like the rule above it, not the warning colour the two
              // blocks before this wear. Those name something that WILL go
              // wrong; this names something nobody could find out. Reading the
              // same as a real refusal would teach the reader to skip both.
              child: Text(
                '$machineName did not say which engines it has, so Harness '
                'could not check for '
                '${engineIdentity(engine).label} before offering to launch it. '
                'The create will still run — if the engine is missing there, '
                'that will only show up when it fails. Updating the Harness '
                'CLI on $machineName lets this be checked first.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: grid.AppPalette.textSecondary,
                ),
              ),
            ),
          ],
          if (install != null) ...[
            const SizedBox(height: _gapBlock),
            Container(
              padding: const EdgeInsets.only(top: _gapBlock),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: grid.AppPalette.textFaint.withValues(alpha: 0.28),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${engineIdentity(engine).label} is not on $machineName '
                    'yet. The terminal runs this first:',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: grid.AppPalette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: _gapTight),
                  // Verbatim, in the engine's own type. A summarised or
                  // prettified command is one the reader cannot check against
                  // what they would have typed, which defeats showing it.
                  SelectableText(
                    install,
                    style: _mono(color: grid.AppPalette.textPrimary)
                        .copyWith(height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fact(
    BuildContext context,
    String key,
    String value, {
    String? note,
    bool faint = false,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: _gapTight + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _factKeyWidth,
            child: Text(
              key,
              style: theme.textTheme.labelSmall?.copyWith(
                color: grid.AppPalette.textFaint,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: faint
                        ? grid.AppPalette.textFaint
                        : grid.AppPalette.textPrimary,
                  ),
                ),
                if (note != null)
                  Text(
                    note,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: grid.AppPalette.textFaint,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Not here yet — Harness will fetch it first."
///
/// A download arrow rather than the words, because this state recurs down the
/// engine list and a repeated two-word phrase stops being read. The tooltip
/// carries the meaning for a first encounter; the preflight panel carries the
/// actual command, which is the thing worth reading.
///
/// Drawn in [AppPalette.textFaint] — the ink the row's own qualifiers use. This
/// is a fact about the engine, not a warning about the choice: installing is a
/// normal outcome of picking it, and an amber glyph would say otherwise.
class _InstallMark extends StatelessWidget {
  const _InstallMark({required this.engine});

  final String engine;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Tooltip(
      message:
          '${engineIdentity(engine).label} is not on this machine — '
          'Harness installs it before launching',
      child: Icon(
        LucideIcons.download300,
        // A shade under the note text beside it: the glyph reads heavier than
        // type at the same nominal size, and matching the number makes it
        // louder than the words it replaced.
        size: 12,
        color: grid.AppPalette.textFaint,
      ),
    );
  }
}
