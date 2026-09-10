import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/share_page_theme.dart';
import '../backend_detector.dart';
import '../context_ladder.dart';
import '../context_length.dart';
import '../engine_endpoint.dart';
import '../engine_reachability.dart';
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
    this.fetch,
  });

  final ShareController controller;
  final String gridName;

  /// How the typed address is asked what it serves. Null in the app, which
  /// means a real request; a test passes one so every branch of the check can
  /// be driven without a socket.
  final EngineFetch? fetch;

  @override
  State<ServeServerForm> createState() => _ServeServerFormState();
}

class _ServeServerFormState extends State<ServeServerForm> {
  final _endpoint = TextEditingController();
  final _model = TextEditingController();
  final _advertise = TextEditingController();
  final _nodeName = TextEditingController(text: thisComputerName);

  /// The window the reader chose, or null while they have not chosen one.
  ///
  /// Nullable so "untouched" is a state the code can see. A server that reports
  /// `max_model_len` settles the question for an untouched field — but a number
  /// somebody picked on purpose is not ours to move.
  int? _contextChoice;

  /// How long to sit still before asking the server anything.
  ///
  /// Somebody typing an address passes through a dozen strings that are not an
  /// address yet, so a check per keystroke would be a burst of requests at
  /// whatever machine they eventually name.
  static const _typingPause = Duration(milliseconds: 600);

  Timer? _debounce;

  /// True from the moment a check is scheduled until its answer lands — the
  /// debounce included, so Start never flickers to "ready" in the gap between
  /// the last keystroke and the request.
  bool _checking = false;

  /// The last answer, and the base it was about. The pair is what makes a
  /// result trustworthy: an answer for an address the user has since edited
  /// says nothing about the one now in the field.
  EngineReach? _reach;
  String? _checkedBase;

  /// Rises with every check started, so an answer that arrives after a newer
  /// check began is dropped instead of overwriting it.
  int _checkToken = 0;

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
    _endpoint.addListener(_onEndpointEdited);
    _model.addListener(_onEdited);
    _kind = _external.firstOrNull?.kind;
  }

  void _onEdited() {
    if (mounted) setState(() {});
  }

  void _onEndpointEdited() {
    if (!mounted) return;
    setState(() {});
    _scheduleCheck();
  }

  /// Ask the server what it serves, as soon as the address looks like one.
  ///
  /// **Not** on Start, which is where this began in the Grid app and where it
  /// deadlocked: the button is blocked until a model is chosen, and the model
  /// list only exists once the server has been asked. Nothing could ever run.
  void _scheduleCheck() {
    final address = readEngineAddress(_endpoint.text);
    _debounce?.cancel();
    if (address is! EngineAddressReady) {
      // Half-typed or refused: drop whatever a previous address answered, and
      // make sure an in-flight reply cannot land on top of it.
      _checkToken++;
      setState(() {
        _checking = false;
        _reach = null;
        _checkedBase = null;
      });
      return;
    }
    if (address.base == _checkedBase) return;
    setState(() => _checking = true);
    _debounce = Timer(_typingPause, () => unawaited(_check(address)));
  }

  /// One look at [address], recorded only if it is still the address on screen.
  Future<void> _check(EngineAddressReady address) async {
    final token = ++_checkToken;
    final reach = await probeEngine(address, fetch: widget.fetch);
    if (!mounted || token != _checkToken) return;
    setState(() {
      _checking = false;
      _reach = reach;
      _checkedBase = address.base;
    });
    _adoptAnswers(reach);
  }

  /// Fill in what the server just told us, without touching what the reader has
  /// already typed — a prefill that overwrites is worse than no prefill.
  void _adoptAnswers(EngineReach reach) {
    if (reach is! EngineReachable) return;
    // One model is not a choice, it is the answer.
    if (reach.models.length == 1 &&
        reach.canOfferModels &&
        _model.text.trim().isEmpty) {
      _model.text = reach.models.single;
    }
    // A server that states its window has settled the question: the ladder's
    // ceiling becomes what it serves, and the value lands inside it.
    if (reach.contextLength case final served? when _contextChoice == null) {
      setState(() => _contextChoice = defaultContextLength(served));
    }
  }

  /// The answer that is about the address currently in the field, or null.
  ///
  /// Guarding on the base is what stops a stale reply describing a server the
  /// reader has since typed away from.
  EngineReach? get _reachForCurrent {
    final address = readEngineAddress(_endpoint.text);
    if (address is! EngineAddressReady) return null;
    return address.base == _checkedBase ? _reach : null;
  }

  /// The most this engine can be told it holds.
  ///
  /// The server's own figure when it gave one, so the ladder cannot offer more
  /// than it actually serves. Otherwise a plain ceiling: nothing here knows the
  /// real limit, and a ladder still has to end somewhere.
  int get _contextMax => switch (_reachForCurrent) {
    EngineReachable(:final contextLength?) => contextLength,
    _ => defaultServerContextCeiling,
  };

  /// The window that will be sent, clamped into what the server admits to.
  int get _context => (_contextChoice ?? defaultContextLength(_contextMax))
      .clamp(minContextTokens, _contextMax);

  /// The names the Model field can offer, or empty for the text box.
  List<String> get _offeredModels => switch (_reachForCurrent) {
    EngineReachable(:final models, :final canOfferModels) when canOfferModels =>
      models,
    _ => const [],
  };

  @override
  void didUpdateWidget(ServeServerForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A probe that lands after the first frame brings the engine with it.
    _kind ??= _external.firstOrNull?.kind;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _endpoint.removeListener(_onEndpointEdited);
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

  bool get _typedReady => _typedBlockedReason() == null;

  bool get _ready => _chosen != null || _typedReady;

  /// Why Start cannot be pressed for the typed address, or null when it can.
  ///
  /// The address is judged by the same reader the field itself uses, so the
  /// button and the line under the field can never disagree about whether an
  /// address is usable.
  ///
  /// Start needs a server that **answered**, not merely an address that parses.
  /// That is the fail-closed half of this screen: `grid join --at` will happily
  /// take an address nothing is listening on, and the node it registers then
  /// fails every message while looking perfectly healthy — green in the list,
  /// model advertised, and every request answering `404`.
  String? _typedBlockedReason() {
    if (_checking) return 'Checking the server…';
    return switch (readEngineAddress(_endpoint.text)) {
      EngineAddressEmpty() => 'Fill in the server address to start.',
      EngineAddressRejected(:final message) => message,
      EngineAddressReady() => switch (_reachForCurrent) {
        // The detail is already spelled out under the field; repeating it on
        // the button would say the same sentence twice on one screen.
        EngineUnreachable() => "The grid couldn't reach that server.",
        EngineReachable() when _model.text.trim().isEmpty =>
          'Choose the model this server runs.',
        EngineReachable() => null,
        // No answer yet and not checking — reachable only for the instant
        // between the address becoming valid and the check being scheduled.
        null => 'Checking the server…',
      },
    };
  }

  /// Start the share, whichever answer step 2 holds.
  ///
  /// A stopped engine is started first and then shared — one press for one
  /// intention, which is what Launch & share got right and what splitting the
  /// pane in two got wrong.
  Future<void> _start() async {
    final backend = _chosen;
    if (backend == null) {
      // The BASE, never the raw text. This is the invariant the whole check
      // rests on: the address that was asked `/models` is the address that gets
      // joined. Sending `_endpoint.text.trim()` here would let a green tick sit
      // over a URL nothing had verified — which is exactly the bug this file
      // was changed to close.
      final address = readEngineAddress(_endpoint.text);
      if (address is! EngineAddressReady) return;
      await widget.controller.startExternal(
        endpoint: address.base,
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

  Widget _typedFields() {
    final offered = _offeredModels;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ShareField(
            label: 'Endpoint',
            note: _addressNote(),
            child: ShareTextField(
              key: const Key('server-endpoint-field'),
              controller: _endpoint,
              hint: 'http://localhost:8080/v1',
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ShareField(
            label: 'Model id',
            // A picker only for an engine whose body was recognised — see
            // [EngineReachable.canOfferModels]. Everything else keeps the text
            // box it always had.
            child: offered.isEmpty
                ? ShareTextField(
                    key: const Key('server-model-field'),
                    controller: _model,
                    hint: 'The id the server answers to',
                  )
                : ShareSelect(
                    key: const Key('server-model-select'),
                    value: _model.text.trim().isEmpty
                        ? null
                        : _model.text.trim(),
                    options: [for (final id in offered) ShareOption(id)],
                    placeholder: 'Choose one of its models',
                    onSelected: (id) => _model.text = id,
                  ),
          ),
        ),
      ],
    );
  }

  /// The line under the Endpoint field: what the app made of what was typed.
  ///
  /// Three things it can say that the field never said before — the URL the
  /// grid will actually call, echoed as you type so it is comparable against
  /// your own server's docs; why an address was refused; and, on a failure, the
  /// URL that was really requested. Nothing server-side records that last one,
  /// so support has had nothing to ask but "what did you type?".
  String? _addressNote() {
    final address = readEngineAddress(_endpoint.text);
    return switch (address) {
      EngineAddressEmpty() => null,
      EngineAddressRejected(:final message) => message,
      EngineAddressReady() => switch ((_checking, _reachForCurrent)) {
        (true, _) => 'Asking ${address.modelsUrl}…',
        (_, EngineUnreachable(:final message)) => message,
        (_, EngineReachable(:final models)) when models.isEmpty =>
          'Answered, but named no models. The grid will call '
              '${address.chatUrl}',
        (_, EngineReachable()) => 'The grid will call ${address.chatUrl}',
        _ => null,
      },
    };
  }

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
                      max: _contextMax,
                      current: _context,
                    ))
                      ShareOption(formatContextLength(rung)),
                  ],
                  onSelected: (label) => setState(() {
                    _contextChoice =
                        contextLadder(
                          max: _contextMax,
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
              Text(switch (_reachForCurrent) {
                // The server settled it, so the ladder stops where it does
                // and the sentence says whose number that is.
                EngineReachable(:final contextLength?) =>
                  'This server reports it serves '
                      '${formatContextLength(contextLength)}, so that is as '
                      'high as this goes.',
                _ =>
                  'What you tell the grid this engine can hold. Claim more '
                      'than it serves and questions come back empty.',
              }, style: ShareType.note),
            ],
          ),
          const SizedBox(height: 18),
          StartRow(
            label: 'Start sharing',
            // The helper says what is *missing* while it is, because a disabled
            // button with a general sentence beside it is a puzzle.
            note: switch ((backend, backend?.running, _typedBlockedReason())) {
              (final found?, false, _) =>
                'Starts ${found.label}, then puts it on ${widget.gridName}.',
              (final found?, _, _) =>
                'Puts ${found.label} on ${widget.gridName}, with its models, '
                    'quantization and flags exactly as they are.',
              // Named, not general: a disabled button beside "something is
              // missing" is a puzzle, and the reason is already known here.
              (_, _, final reason?) => reason,
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
          duration: grid.AppMotion.hover,
          curve: grid.AppMotion.curve,
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
