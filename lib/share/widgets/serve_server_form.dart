import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/share_page_theme.dart';
import '../backend_detector.dart';
import '../context_ladder.dart';
import '../context_length.dart';
import '../node_identity.dart';
import '../share_controller.dart';
import '../share_discovery.dart';
import 'share_fields.dart';
import 'share_form_parts.dart';

/// Share an OpenAI-compatible engine already running on this computer.
///
/// Two ways in, in the order somebody would take them. What was *found* here
/// comes first as a card with one button: an engine that is installed and
/// stopped is the state most machines are in, and "start it, then share it" is
/// one intention, not two — pressing Launch does both. Under it, the typed
/// address, because this is the one route that has to work when nothing was
/// detected: somebody running their own llama.cpp on a port we do not probe is
/// exactly who that half is for.
class ServeServerForm extends StatefulWidget {
  const ServeServerForm({super.key, required this.controller});

  final ShareController controller;

  @override
  State<ServeServerForm> createState() => _ServeServerFormState();
}

class _ServeServerFormState extends State<ServeServerForm> {
  final _endpoint = TextEditingController();
  final _model = TextEditingController();
  final _advertise = TextEditingController();
  final _nodeName = TextEditingController(text: thisComputerName);

  int _context = defaultContextLength(defaultServerContextCeiling);

  /// A detected engine is being launched, so its card can say so.
  bool _launching = false;
  String? _launchError;

  @override
  void initState() {
    super.initState();
    _endpoint.addListener(_onEdited);
    _model.addListener(_onEdited);
  }

  void _onEdited() {
    if (mounted) setState(() {});
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

  /// Launch a detected engine if it needs it, then share it — one press.
  Future<void> _launchAndShare(DetectedBackend backend) async {
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
      // It is up but serving nothing, which the typed half below can fix.
      setState(() {
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
      nodeName: _nodeName.text,
    );
  }

  Future<void> _shareTyped() async {
    await widget.controller.startExternal(
      endpoint: _endpoint.text.trim(),
      model: _model.text.trim(),
      advertiseAs: _advertise.text,
      nodeName: _nodeName.text,
      contextLength: _context,
    );
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final joining = widget.controller.status == ShareStatus.starting;
    final busy = joining || _launching;
    final ready =
        _endpoint.text.trim().isNotEmpty && _model.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final backend in _external) ...[
          _FoundEngine(
            backend: backend,
            busy: busy,
            onPressed: () => _launchAndShare(backend),
          ),
          const SizedBox(height: 10),
        ],
        if (_launchError != null) ...[
          ShareErrorNote(
            message: _launchError!,
            onDismiss: () => setState(() => _launchError = null),
          ),
          const SizedBox(height: 10),
        ],
        if (_external.isNotEmpty) const _OrRule(),
        SharePlate(
          children: [
            ShareField(
              label: 'Endpoint, any OpenAI-compatible server',
              child: ShareTextField(
                controller: _endpoint,
                hint: 'http://localhost:8080/v1',
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ShareField(
                    label: 'Model id',
                    child: ShareTextField(
                      controller: _model,
                      hint: 'The id the server answers to',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ShareField(
                    label: 'Shown on the grid as',
                    child: ShareTextField(
                      controller: _advertise,
                      hint: 'Optional, defaults to the model id',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ShareField(
                    label: 'Context window',
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
                        _context = contextLadder(
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
          ],
        ),
        const SizedBox(height: 18),
        StartRow(
          label: 'Start engine',
          // The helper says what is *missing* while it is, because a disabled
          // button with a general sentence beside it is a puzzle.
          note: ready
              ? 'Its models, quantization and flags are shared as they are.'
              : 'Add an endpoint and a model id to continue.',
          onPressed: ready && !busy ? _shareTyped : null,
          busy: joining,
        ),
      ],
    );
  }
}

/// An engine found on this computer, and the one press that shares it.
class _FoundEngine extends StatelessWidget {
  const _FoundEngine({
    required this.backend,
    required this.busy,
    required this.onPressed,
  });

  final DetectedBackend backend;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: SharePalette.accentRing,
        border: Border.all(color: SharePalette.accent.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(ShareMetrics.plateRadius),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.server300, size: 19, color: SharePalette.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(backend.label, style: ShareType.cardTitle),
                const SizedBox(height: 2),
                Text(
                  backend.running
                      ? 'Answering on this computer with '
                            '${backend.models.length} '
                            '${backend.models.length == 1 ? 'model' : 'models'}.'
                      : 'Installed on this computer, not running yet.',
                  style: ShareType.note,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: busy ? null : onPressed,
            icon: busy
                ? const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.play_arrow_rounded, size: 18),
            // One verb for one intention: a stopped engine is started and then
            // shared, and splitting that into two presses only asks the reader
            // to remember why they pressed the first one.
            label: Text(backend.running ? 'Share it' : 'Launch & share'),
            style: FilledButton.styleFrom(
              backgroundColor: SharePalette.accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: SharePalette.accent.withValues(
                alpha: 0.4,
              ),
              disabledForegroundColor: Colors.white70,
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ShareMetrics.fieldRadius),
              ),
              textStyle: TextStyle(
                fontSize: 13,
                fontWeight: grid.AppFont.semibold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The seam between what was found and what can be typed.
class _OrRule extends StatelessWidget {
  const _OrRule();

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Divider(height: 1, color: SharePalette.innerRule)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('OR POINT AT ANOTHER ENDPOINT', style: ShareType.eyebrow),
          ),
          Expanded(child: Divider(height: 1, color: SharePalette.innerRule)),
        ],
      ),
    );
  }
}
