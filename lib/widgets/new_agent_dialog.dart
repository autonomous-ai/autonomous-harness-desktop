import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../grid/grid_agent_override.dart';
import '../grid/grid_selection_store.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_checkbox.dart';
import '../shared/widgets/app_select_field.dart';
import '../shared/widgets/labeled_field.dart';
import '../state/app_state.dart';
import 'engine_identity.dart';
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
    if (folder == null || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    // A relay key is minted per launch, so it is fetched here rather than held
    // in the store. Null when no grid is picked, which leaves the frame exactly
    // as it was before this feature existed.
    final GridAgentOverride? gridOverride;
    try {
      gridOverride = await resolveGridAgentOverride();
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
      grid: gridOverride,
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
    // Reads colour tokens, and lives in an Overlay — a top-down rebuild never
    // reaches it, so it has to watch for itself or it strands on the palette it
    // opened with.
    grid.AppTheme.watch(context);
    final bypassFlag = kEngineBypassPermissionFlag[_engine];

    return ValueListenableBuilder<GridSelection>(
      valueListenable: gridSelectionStore,
      builder: (context, chosen, _) {
        // The CLI refuses an engine it cannot point at a grid rather than
        // quietly running it on its own login, so the dialog already knows this
        // launch will fail. Gating the button here is what stops a round trip
        // that only ever ends in an error the user was already warned about.
        final refused =
            chosen.hasGrid && !kGridCapableEngines.contains(_engine);
        final canCreate = _folder != null && !refused && !_submitting;

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
                      final choices = _choices(bypassFlag);
                      final summary = _NewAgentSummary(
                        engine: _engine,
                        folder: _folder,
                        machineName: _machineName,
                        machineIsThisComputer: _machineIsThisComputer,
                        bypassFlag: _bypassPermission ? bypassFlag : null,
                        selection: chosen,
                        refused: refused,
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
  Widget _choices(String? bypassFlag) {
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
                // Stated in the row rather than discovered after picking: both
                // of these change what the engine can do, and finding out by
                // watching the checkbox vanish is a worse way to learn it.
                note: !kGridCapableEngines.contains(identity.id)
                    ? 'no grid'
                    : kEngineBypassPermissionFlag.containsKey(identity.id)
                    ? null
                    : 'no bypass flag',
                leading: () => EngineMark(engine: identity.id, size: 14),
              ),
          ],
          onChanged: (value) => setState(() {
            _engine = value;
            if (!kEngineBypassPermissionFlag.containsKey(value)) {
              _bypassPermission = false;
            }
          }),
        ),
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
                    child: Text(
                      picking
                          ? 'Waiting for the folder picker…'
                          // Not "on $machineName": the title says which machine
                          // and so does the summary, and a hostname like
                          // `MacBooks-MacBook-Pro.local` spent the whole control
                          // repeating it and then truncated the sentence anyway.
                          : chosen ?? 'Choose a folder…',
                      maxLines: 1,
                      // From the LEFT, so the leaf — the folder actually being
                      // chosen — is what survives the ellipsis on a deep path.
                      overflow: TextOverflow.ellipsis,
                      textDirection: chosen != null && !picking
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      style: chosen != null && !picking
                          ? _mono(color: grid.AppPalette.textPrimary)
                          : theme.textTheme.labelMedium?.copyWith(
                              color: grid.AppPalette.textFaint,
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
/// other than the engine's own login.
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
  });

  final String engine;
  final String? folder;
  final String machineName;
  final bool machineIsThisComputer;

  /// Non-null only when the box is actually ticked — this states what WILL run,
  /// not what could.
  final String? bypassFlag;
  final GridSelection selection;
  final bool refused;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final theme = Theme.of(context);
    final warn = grid.AppPalette.warn;
    final flag = bypassFlag;
    final ready = folder != null && !refused;

    final Color dot;
    final String heading;
    if (refused) {
      dot = warn;
      heading = 'Will be refused';
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
            style: _mono(
              color: grid.AppPalette.textPrimary,
            ).copyWith(height: 1.5),
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
            refused || !selection.hasGrid
                ? "${engineIdentity(engine).label}'s own login"
                : '${selection.label} · ${selection.model ?? 'Auto'}',
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
                'another engine, or clear the grid in the sidebar.',
                style: theme.textTheme.bodySmall?.copyWith(color: warn),
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
