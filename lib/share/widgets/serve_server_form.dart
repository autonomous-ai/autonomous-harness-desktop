import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/share_page_theme.dart';
import '../backend_detector.dart';
import '../node_identity.dart';
import '../share_controller.dart';
import '../share_discovery.dart';
import 'share_fields.dart';
import 'share_form_parts.dart';

/// Share an OpenAI-compatible engine already running on this computer.
///
/// The address is typed rather than only picked, because this route is the one
/// that has to work when nothing was detected — somebody running their own
/// llama.cpp on a port we do not probe is exactly who this is for.
class ServeServerForm extends StatefulWidget {
  const ServeServerForm({super.key, required this.controller});

  final ShareController controller;

  @override
  State<ServeServerForm> createState() => _ServeServerFormState();
}

class _ServeServerFormState extends State<ServeServerForm> {
  final _endpoint = TextEditingController();
  final _model = TextEditingController();
  final _nodeName = TextEditingController(text: thisComputerName);

  /// Starting a detected-but-stopped server, so the button can say so.
  bool _starting = false;
  String? _startError;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _model.dispose();
    _nodeName.dispose();
    super.dispose();
  }

  List<DetectedBackend> get _external => [
    for (final backend in widget.controller.capabilities.backends)
      if (backend.isExternal) backend,
  ];

  DetectedBackend? get _running {
    for (final backend in _external) {
      if (backend.running) return backend;
    }
    return null;
  }

  /// Open on what is actually answering, and on the first model it reported.
  /// A form that made somebody retype an address the app had just detected
  /// would be asking them to prove it.
  void _prefill() {
    final live = _running ?? _external.firstOrNull;
    if (live == null || _endpoint.text.isNotEmpty) return;
    _endpoint.text = live.baseUrl;
    if (live.models.isNotEmpty) _model.text = live.models.first;
  }

  Future<void> _startServer() async {
    setState(() {
      _starting = true;
      _startError = null;
    });
    final up = await startOllamaServer();
    if (!mounted) return;
    if (!up) {
      setState(() {
        _starting = false;
        _startError =
            'Ollama did not come up. Start it yourself and this page will '
            'find it.';
      });
      return;
    }
    await widget.controller.refresh(widget.controller.gridId ?? '');
    if (!mounted) return;
    setState(() => _starting = false);
    _prefill();
  }

  Future<void> _share() async {
    await widget.controller.startExternal(
      endpoint: _endpoint.text.trim(),
      model: _model.text.trim(),
      nodeName: _nodeName.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final joining = widget.controller.status == ShareStatus.starting;
    final stopped = _running == null ? _external.firstOrNull : null;
    final live = _running;
    final ready =
        _endpoint.text.trim().isNotEmpty && _model.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stopped != null) ...[
          SharePlate(
            children: [
              Text(
                '${stopped.label} is installed here but is not answering yet. '
                'Start it and it can be shared exactly as it is.',
                style: ShareType.paneBody,
              ),
              const SizedBox(height: 14),
              StartRow(
                label: 'Start ${stopped.label}',
                note: 'It keeps running after this.',
                onPressed: _starting ? null : _startServer,
                busy: _starting,
              ),
              if (_startError != null) ...[
                const SizedBox(height: 12),
                ShareErrorNote(message: _startError!),
              ],
            ],
          ),
          const SizedBox(height: 14),
        ],
        SharePlate(
          children: [
            ShareField(
              label: 'Address',
              child: ShareTextField(
                controller: _endpoint,
                hint: 'http://localhost:11434/v1',
                onSubmitted: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'The OpenAI-compatible base URL — the one that answers on '
              '/models.',
              style: ShareType.note,
            ),
            const SizedBox(height: 18),
            ShareField(
              label: 'Model to share',
              child: live != null && live.models.isNotEmpty
                  ? ShareSelect(
                      value: _model.text.isEmpty ? null : _model.text,
                      options: [
                        for (final model in live.models) ShareOption(model),
                      ],
                      onSelected: (value) =>
                          setState(() => _model.text = value),
                      enabled: !joining,
                    )
                  : ShareTextField(
                      controller: _model,
                      hint: 'The model id the server answers to',
                      onSubmitted: (_) => setState(() {}),
                    ),
            ),
            const SizedBox(height: 18),
            ShareField(
              label: "This computer's name",
              child: ShareTextField(controller: _nodeName),
            ),
          ],
        ),
        const SizedBox(height: 18),
        StartRow(
          label: 'Start sharing',
          // No context window is sent for this route, and that is deliberate —
          // see `externalJoinArgs`. Saying so here is the difference between a
          // missing field and a decision.
          note: 'Its models, quantization and flags are shared as they are.',
          onPressed: ready && !joining ? _share : null,
          busy: joining,
        ),
      ],
    );
  }
}
