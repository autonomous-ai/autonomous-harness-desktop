import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/share_page_theme.dart';
import '../backend_detector.dart';
import '../context_ladder.dart';
import '../context_length.dart';
import '../node_identity.dart';
import '../share_controller.dart';
import '../share_discovery.dart';
import '../share_route.dart';
import 'share_fields.dart';
import 'share_form_parts.dart';
import 'share_steps.dart';

/// Share an OpenAI-compatible engine already running on this computer.
///
/// The version before this put two blue buttons on one pane — Launch & share on
/// the found engine, Start engine under the typed form — separated by an OR
/// rule that had to carry the whole distinction. Two primaries is one too many:
/// the reader has to work out which of them their case belongs to before they
/// can press anything.
///
/// So the found engine and the typed address become what they always were: two
/// answers to step 2's one question, picked like any other pair of options. The
/// press lives in step 3, where it does on every route, and a stopped engine is
/// started on the way through — the same single intention Launch & share had,
/// without a second button to spend it on.
class ServeServerForm extends StatefulWidget {
  const ServeServerForm({
    super.key,
    required this.controller,
    required this.gridName,
  });

  final ShareController controller;
  final String gridName;

  @override
  State<ServeServerForm> createState() => _ServeServerFormState();
}

class _ServeServerFormState extends State<ServeServerForm> {
  final _endpoint = TextEditingController();
  final _model = TextEditingController();
  final _advertise = TextEditingController();
  final _nodeName = TextEditingController(text: thisComputerName);

  int _context = defaultContextLength(defaultServerContextCeiling);

  /// Which engine step 2 is answering with: a detected backend's kind, or null
  /// for the typed address. Starts on whatever was found, because a machine
  /// with Ollama on it is one press from sharing and should not have to type
  /// an address it already has.
  BackendKind? _kind;

  /// A detected engine is being started, so the button can say so.
  bool _launching = false;
  String? _launchError;

  @override
  void initState() {
    super.initState();
    _endpoint.addListener(_onEdited);
    _model.addListener(_onEdited);
    _kind = _external.firstOrNull?.kind;
  }

  void _onEdited() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(ServeServerForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A probe that lands after the first frame brings the engine with it.
    _kind ??= _external.firstOrNull?.kind;
  }

  @override
  void dispose() {
    _endpoint.removeListener(_onEdited);
    _model.removeListener(_onEdited);
    _endpoint.dispose();
    _model.dispose();
    _advertise.dispose();
    _nodeName.dispose();
    super.dispose();
  }

  List<DetectedBackend> get _external => [
    for (final backend in widget.controller.capabilities.backends)
      if (backend.isExternal) backend,
  ];

  DetectedBackend? get _chosen {
    final kind = _kind;
    if (kind == null) return null;
    for (final backend in _external) {
      if (backend.kind == kind) return backend;
    }
    return null;
  }

  bool get _typedReady =>
      _endpoint.text.trim().isNotEmpty && _model.text.trim().isNotEmpty;

  bool get _ready => _chosen != null || _typedReady;

  /// Start the share, whichever answer step 2 holds.
  ///
  /// A stopped engine is started first and then shared — one press for one
  /// intention, which is what Launch & share got right and what splitting the
  /// pane in two got wrong.
  Future<void> _start() async {
    final backend = _chosen;
    if (backend == null) {
      await widget.controller.startExternal(
        endpoint: _endpoint.text.trim(),
        model: _model.text.trim(),
        advertiseAs: _advertise.text,
        nodeName: _nodeName.text,
        contextLength: _context,
      );
      return;
    }
    setState(() {
      _launching = true;
      _launchError = null;
    });
    if (!backend.running) {
      final up = await startOllamaServer();
      if (!mounted) return;
      if (!up) {
        setState(() {
          _launching = false;
          _launchError =
              '${backend.label} did not come up. Start it yourself and this '
              'page will find it.';
        });
        return;
      }
      await widget.controller.refresh(widget.controller.gridId ?? '');
      if (!mounted) return;
    }
    // Re-read it: a server that has just started reports its models, and it is
    // those we share rather than a name typed from memory.
    final live = _external
        .where((found) => found.kind == backend.kind && found.running)
        .firstOrNull;
    setState(() => _launching = false);
    if (live == null || live.models.isEmpty) {
      // It is up but serving nothing, which the typed answer can fix.
      setState(() {
        _kind = null;
        _endpoint.text = backend.baseUrl;
        _launchError =
            '${backend.label} is answering but has no model loaded. Name one '
            'below.';
      });
      return;
    }
    await widget.controller.startExternal(
      endpoint: live.baseUrl,
      model: live.models.first,
      advertiseAs: _advertise.text,
      nodeName: _nodeName.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ShareSteps(
      children: [
        routeChosenStep(ShareRoute.server),
        _engineStep(),
        _startStep(),
      ],
    );
  }

  Widget _engineStep() {
    final busy = widget.controller.status == ShareStatus.starting || _launching;
    final found = _external;
    return ShareStep(
      index: 2,
      state: _ready ? ShareStepState.done : ShareStepState.current,
      title: found.isEmpty ? 'The engine to point at' : 'Engine to point at',
      blurb: found.isEmpty
          ? 'Nothing was detected on the ports this app probes, so name the '
                'address yourself — a llama.cpp you started on your own port '
                'is exactly who this is for.'
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_launchError != null) ...[
            const SizedBox(height: 13),
            ShareErrorNote(
              message: _launchError!,
              onDismiss: () => setState(() => _launchError = null),
            ),
          ],
          const SizedBox(height: 13),
          for (final backend in found) ...[
            _EngineOption(
              selected: _kind == backend.kind,
              enabled: !busy,
              onTap: () => setState(() => _kind = backend.kind),
              title: backend.label,
              tag: backend.running ? null : 'Stopped',
              line: backend.running
                  ? 'Answering on this computer with ${backend.models.length} '
                        '${backend.models.length == 1 ? 'model' : 'models'}. '
                        'Shared exactly as configured.'
                  : 'Installed on this computer. It gets started for you when '
                        'you press Start sharing, and keeps running after.',
            ),
            const SizedBox(height: 9),
          ],
          if (found.isEmpty)
            SharePlate(children: [_typedFields()])
          else
            _EngineOption(
              selected: _kind == null,
              enabled: !busy,
              onTap: () => setState(() => _kind = null),
              title: 'Another endpoint',
              line:
                  'Any OpenAI-compatible server on this computer — your own '
                  'llama.cpp on a port we do not probe.',
              child: _kind == null
                  ? Padding(
                      padding: const EdgeInsets.only(top: 13),
                      child: _typedFields(),
                    )
                  : null,
            ),
        ],
      ),
    );
  }

  Widget _typedFields() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: ShareField(
          label: 'Endpoint',
          child: ShareTextField(
            controller: _endpoint,
            hint: 'http://localhost:8080/v1',
          ),
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: ShareField(
          label: 'Model id',
          child: ShareTextField(
            controller: _model,
            hint: 'The id the server answers to',
          ),
        ),
      ),
    ],
  );

  Widget _startStep() {
    final joining = widget.controller.status == ShareStatus.starting;
    final busy = joining || _launching;
    final backend = _chosen;
    return ShareStep(
      index: 3,
      isLast: true,
      state: ShareStepState.current,
      title: 'Name it and start sharing',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 13),
          SharePlate(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ShareField(
                      label: 'Shown on the grid as',
                      child: ShareTextField(
                        controller: _advertise,
                        hint: 'Optional, defaults to the model id',
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ShareField(
                      label: "This computer's name",
                      child: ShareTextField(controller: _nodeName),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // A ladder, where the local route gets a slider, and the label is
              // the local route's so the two read as the same setting. The
              // control differs because the question does: a server's window is
              // a number it was *launched* with, so this asks which one that
              // was rather than how much the reader would like.
              ShareField(
                label: 'Memory for context',
                child: ShareSelect(
                  value: formatContextLength(_context),
                  options: [
                    for (final rung in contextLadder(
                      max: defaultServerContextCeiling,
                      current: _context,
                    ))
                      ShareOption(formatContextLength(rung)),
                  ],
                  onSelected: (label) => setState(() {
                    _context =
                        contextLadder(
                          max: defaultServerContextCeiling,
                          current: _context,
                        ).firstWhere(
                          (rung) => formatContextLength(rung) == label,
                          orElse: () => _context,
                        );
                  }),
                  enabled: !busy,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'What you tell the grid this engine can hold. Claim more than '
                'it serves and questions come back empty.',
                style: ShareType.note,
              ),
            ],
          ),
          const SizedBox(height: 18),
          StartRow(
            label: 'Start sharing',
            // The helper says what is *missing* while it is, because a disabled
            // button with a general sentence beside it is a puzzle.
            note: switch ((_ready, backend, backend?.running)) {
              (false, _, _) => 'Add an endpoint and a model id to continue.',
              (_, final found?, false) =>
                'Starts ${found.label}, then puts it on ${widget.gridName}.',
              (_, final found?, _) =>
                'Puts ${found.label} on ${widget.gridName}, with its models, '
                    'quantization and flags exactly as they are.',
              _ => 'Its models, quantization and flags are shared as they are.',
            },
            onPressed: _ready && !busy ? _start : null,
            busy: busy,
          ),
        ],
      ),
    );
  }
}

/// One answer to "which engine": a detected one, or the typed address.
class _EngineOption extends StatefulWidget {
  const _EngineOption({
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.title,
    required this.line,
    this.tag,
    this.child,
  });

  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final String title;
  final String line;

  /// A state the title cannot carry: Ollama, stopped.
  final String? tag;

  /// What picking this reveals — the endpoint fields.
  final Widget? child;

  @override
  State<_EngineOption> createState() => _EngineOptionState();
}

class _EngineOptionState extends State<_EngineOption> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final selected = widget.selected;
    final live = widget.enabled && _hovered;
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
          decoration: BoxDecoration(
            color: selected
                ? SharePalette.optionFill
                : live
                ? SharePalette.hoverFill
                : SharePalette.surface,
            border: Border.all(
              color: selected
                  ? SharePalette.optionRim
                  : live
                  ? SharePalette.fieldRimHover
                  : SharePalette.rim,
            ),
            borderRadius: BorderRadius.circular(ShareMetrics.plateRadius),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 12),
                child: ShareRadio(selected: selected, hovered: live),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(widget.title, style: ShareType.cardTitle),
                        ),
                        if (widget.tag != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: SharePalette.tagFill,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              widget.tag!.toUpperCase(),
                              style: ShareType.tag,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(widget.line, style: ShareType.note),
                    ?widget.child,
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
