import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/share_page_theme.dart';
import '../context_length.dart';
import '../grid_cli.dart';
import '../local_models.dart';
import '../model_pull.dart';
import '../node_identity.dart';
import '../share_controller.dart';
import '../share_discovery.dart';
import 'share_fields.dart';
import 'share_form_parts.dart';

/// Serve a GGUF on this computer's own hardware.
///
/// The form in the design, in its order: which model, what to call it on the
/// grid, what to call this computer, and how much of a conversation it should
/// hold. Everything but the first has a working default, so the fast path is
/// pick a model and press.
class ServeLocalForm extends StatefulWidget {
  const ServeLocalForm({
    super.key,
    required this.controller,
    required this.pull,
    required this.cli,
  });

  final ShareController controller;
  final ModelPullController pull;
  final GridCli cli;

  @override
  State<ServeLocalForm> createState() => _ServeLocalFormState();
}

class _ServeLocalFormState extends State<ServeLocalForm> {
  final _advertise = TextEditingController();
  final _nodeName = TextEditingController(text: thisComputerName);

  String? _model;

  /// Which model [_advertise] was filled from. Keeps a manual edit while the
  /// same model stays picked, and re-derives the moment another is chosen.
  String? _filledFor;

  /// The picked model's ceiling, and the value under it. Null while the ceiling
  /// is still being read — the slider is drawn disabled rather than guessing a
  /// maximum and snapping the user's choice to it a moment later.
  int? _maxContext;
  int? _contextSize;

  bool _showDownloads = false;

  @override
  void initState() {
    super.initState();
    _selectDefault();
  }

  @override
  void didUpdateWidget(ServeLocalForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selectDefault();
  }

  @override
  void dispose() {
    _advertise.dispose();
    _nodeName.dispose();
    super.dispose();
  }

  List<LocalModel> get _models => widget.controller.capabilities.models;

  /// Open on the largest model on disk, which is the one somebody downloaded on
  /// purpose. Never on nothing when there is something to pick.
  void _selectDefault() {
    if (_model != null || _models.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _model == null && _models.isNotEmpty) {
        _pickModel(_models.first.file);
      }
    });
  }

  Future<void> _pickModel(String file) async {
    setState(() {
      _model = file;
      _maxContext = null;
      _contextSize = null;
      if (_filledFor != file) {
        _filledFor = file;
        _advertise.text = deriveAdvertiseName(file);
      }
    });
    final max = await readMaxContext(widget.cli, file);
    if (!mounted || _model != file) return;
    setState(() {
      _maxContext = max;
      _contextSize = defaultContextLength(max);
    });
  }

  LocalModel? get _picked {
    final file = _model;
    if (file == null) return null;
    for (final model in _models) {
      if (model.file == file) return model;
    }
    return null;
  }

  Future<void> _start() async {
    final file = _model;
    if (file == null) return;
    await widget.controller.startLocal(
      modelFile: file,
      nodeName: _nodeName.text,
      advertiseAs: _advertise.text,
      contextSize: _contextSize,
    );
  }

  Future<void> _download(String label) async {
    final ok = await widget.pull.pull(label);
    if (!ok || !mounted) return;
    await widget.controller.refresh(widget.controller.gridId ?? '');
    if (!mounted) return;
    setState(() => _showDownloads = false);
    _selectDefault();
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final picked = _picked;
    final max = _maxContext;
    final size = _contextSize;
    final starting = widget.controller.status == ShareStatus.starting;
    final incomplete = picked != null && !picked.isComplete;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SharePlate(
          children: [
            ShareField(
              label: 'Model',
              child: ShareSelect(
                value: _model,
                badge: picked == null
                    ? null
                    : modelSizeLabel(picked.sizeBytes),
                placeholder: _models.isEmpty
                    ? 'Nothing downloaded yet'
                    : 'Choose a model',
                options: [
                  for (final model in _models)
                    ShareOption(
                      model.file,
                      badge: modelSizeLabel(model.sizeBytes),
                      note: model.isComplete
                          ? null
                          : 'Unfinished · ${model.parts} of '
                                '${model.expectedParts} parts',
                    ),
                ],
                onSelected: _pickModel,
                enabled: !starting,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () =>
                    setState(() => _showDownloads = !_showDownloads),
                style: TextButton.styleFrom(
                  foregroundColor: SharePalette.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  minimumSize: const Size(0, 26),
                  textStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: grid.AppFont.semibold,
                  ),
                ),
                child: Text(
                  _showDownloads
                      ? 'Hide downloads'
                      : 'Download or manage models →',
                ),
              ),
            ),
            if (_showDownloads || _models.isEmpty)
              DownloadBlock(pull: widget.pull, onDownload: _download),
          ],
        ),
        if (_models.isNotEmpty) ...[
          const SizedBox(height: 14),
          SharePlate(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ShareField(
                      label: 'Shown on the grid as',
                      child: ShareTextField(controller: _advertise),
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
              ContextSlider(
                max: max,
                value: size,
                onChanged: (tokens) => setState(() => _contextSize = tokens),
              ),
            ],
          ),
          const SizedBox(height: 18),
          StartRow(
            label: 'Start sharing',
            note: 'You can stop at any time.',
            // A split model missing a shard cannot be loaded. Refusing here
            // beats a join that fails inside llama.cpp a minute later.
            onPressed: _model == null || starting || incomplete ? null : _start,
            busy: starting,
          ),
          if (incomplete) ...[
            const SizedBox(height: 8),
            Text(
              'This model is missing part of its download, so it cannot be '
              'loaded yet.',
              style: ShareType.note,
            ),
          ],
        ],
      ],
    );
  }
}
