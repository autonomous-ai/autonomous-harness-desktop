import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/share_page_theme.dart';
import '../context_length.dart';
import '../grid_cli.dart';
import '../local_models.dart';
import '../model_pull.dart';
import '../node_identity.dart';
import '../recommended_models.dart';
import '../share_controller.dart';
import '../share_discovery.dart';
import '../share_route.dart';
import 'model_manager_dialog.dart';
import 'share_fields.dart';
import 'share_form_parts.dart';
import 'share_steps.dart';

/// Serve a GGUF on this computer's own hardware, as three steps.
///
/// The order is the order the machine imposes: a model has to be on the disk
/// before there is anything to name or size. That is why the old single form
/// collapsed to a picker and a link on a fresh machine — every other control
/// depended on a choice that could not be made yet. Here that dependency is the
/// structure: step 2 is the download, step 3 is everything it unlocks, and both
/// stay on screen so the reader can see what the download is *for*.
class ServeLocalForm extends StatefulWidget {
  const ServeLocalForm({
    super.key,
    required this.controller,
    required this.pull,
    required this.cli,
    required this.gridName,
    this.recommended,
  });

  final ShareController controller;
  final ModelPullController pull;
  final GridCli cli;

  /// Named in step 3's helper, so the press says where this Mac is going.
  final String gridName;

  /// Injected by tests. Null in the app, where it is built from the CLI.
  final RecommendedModelsController? recommended;

  @override
  State<ServeLocalForm> createState() => _ServeLocalFormState();
}

class _ServeLocalFormState extends State<ServeLocalForm> {
  final _advertise = TextEditingController();
  final _nodeName = TextEditingController(text: thisComputerName);

  late final RecommendedModelsController _picks =
      widget.recommended ?? RecommendedModelsController(cli: widget.cli);

  /// Whether [_picks] is ours to dispose. A controller handed in by a test
  /// outlives this widget.
  late final bool _ownsPicks = widget.recommended == null;

  String? _model;

  /// Which model [_advertise] was filled from. Keeps a manual edit while the
  /// same model stays picked, and re-derives the moment another is chosen.
  String? _filledFor;

  /// Whether step 2 is open on its picker rather than collapsed to the answer.
  /// A machine with one model has nothing to choose, so it opens closed; the
  /// Change link is how somebody with four gets back to it.
  bool _picking = false;

  /// The picked model's ceiling, and the value under it. Null while the ceiling
  /// is still being read — the slider is drawn disabled rather than guessing a
  /// maximum and snapping the user's choice to it a moment later.
  int? _maxContext;
  int? _contextSize;

  @override
  void initState() {
    super.initState();
    _selectDefault();
    if (_models.isEmpty) _picks.load();
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
    if (_ownsPicks) _picks.dispose();
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
      _picking = false;
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

  /// Open the shelf. Everything downloadable lives there, including the models
  /// this Mac is specifically recommended — the form is for choosing among what
  /// is already here.
  Future<void> _manage() async {
    await showModelManager(
      context,
      pull: widget.pull,
      cli: widget.cli,
      onChanged: _reloadModels,
    );
    if (mounted) await _reloadModels();
  }

  /// Download one of the CLI's own picks, without leaving the step.
  Future<void> _download(RecommendedPick pick) async {
    if (pick.specs.isEmpty) return;
    final ok = await widget.pull.pull(pick.specs, label: pick.name);
    if (!mounted || !ok) return;
    await _reloadModels();
  }

  Future<void> _reloadModels() async {
    final gridId = widget.controller.gridId;
    if (gridId == null) return;
    await widget.controller.refresh(gridId);
    if (!mounted) return;
    // The model that was picked may have just been deleted.
    if (!_models.any((model) => model.file == _model)) {
      setState(() => _model = null);
    }
    _selectDefault();
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final hasModel = _models.isNotEmpty;
    return ListenableBuilder(
      listenable: Listenable.merge([_picks, widget.pull]),
      builder: (context, _) => ShareSteps(
        children: [
          routeChosenStep(ShareRoute.local),
          hasModel ? _modelStep() : _downloadStep(),
          _startStep(ready: hasModel),
        ],
      ),
    );
  }

  /// Step 2, on a machine with nothing on its disk.
  Widget _downloadStep() {
    final busy = widget.pull.isPulling;
    return ShareStep(
      index: 2,
      state: ShareStepState.current,
      title: 'Get a model onto this disk',
      blurb:
          'Nothing here yet. The catalogue lists what this Mac can actually '
          'run — these are its own picks for this machine.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.pull.isPulling || widget.pull.error != null) ...[
            const SizedBox(height: 13),
            PullBanner(pull: widget.pull),
          ],
          if (_picks.picks.isNotEmpty) ...[
            const SizedBox(height: 13),
            SharePlate(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        'PICKED FOR THIS MAC',
                        style: ShareType.eyebrow,
                      ),
                    ),
                    if (_picks.machine != null)
                      Flexible(
                        child: Text(
                          _picks.machine!,
                          textAlign: TextAlign.right,
                          style: ShareType.note,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final (index, pick) in _picks.picks.indexed) ...[
                  if (index > 0)
                    Divider(height: 19, color: SharePalette.innerRule),
                  _PickRow(
                    pick: pick,
                    busy: busy,
                    onDownload: () => _download(pick),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 15),
          Row(
            children: [
              ShareButton(
                label: 'Browse the catalogue',
                icon: LucideIcons.library300,
                onPressed: busy ? null : _manage,
              ),
              const SizedBox(width: ShareMetrics.buttonGap),
              Flexible(
                child: Text(
                  'Everything the catalogue carries, and everything already on '
                  'this disk.',
                  style: ShareType.buttonHelper,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Step 2, once there is something to serve. Collapsed to the answer, because
  /// the interesting question has moved to step 3.
  Widget _modelStep() {
    final picked = _picked;
    final starting = widget.controller.status == ShareStatus.starting;
    final open = _picking || picked == null;
    return ShareStep(
      index: 2,
      state: open ? ShareStepState.current : ShareStepState.done,
      title: 'Model on this disk',
      said: open
          ? null
          : '${picked.file} · ${modelSizeLabel(picked.sizeBytes)}',
      onChange: open ? null : () => setState(() => _picking = true),
      child: !open
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 13),
                SharePlate(
                  children: [
                    ShareField(
                      label: 'Model',
                      child: ShareSelect(
                        value: _model,
                        badge: picked == null
                            ? null
                            : modelSizeLabel(picked.sizeBytes),
                        placeholder: 'Choose a model',
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
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ShareLink(
                        label: 'Download or manage models →',
                        onPressed: _manage,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  /// Step 3. The same step on all three routes: what this is called, what this
  /// computer is called, and the one button that starts it.
  Widget _startStep({required bool ready}) {
    final picked = _picked;
    final starting = widget.controller.status == ShareStatus.starting;
    final incomplete = picked != null && !picked.isComplete;
    return ShareStep(
      index: 3,
      isLast: true,
      state: ready ? ShareStepState.current : ShareStepState.waiting,
      title: 'Name it and start sharing',
      blurb: ready
          ? 'The name on the left is what the grid calls this model. The one on '
                'the right is what it calls this Mac.'
          : null,
      lockedNote: ready ? null : 'Opens once a model is on this disk.',
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
                max: _maxContext,
                value: _contextSize,
                onChanged: (tokens) => setState(() => _contextSize = tokens),
              ),
            ],
          ),
          if (ready) ...[
            const SizedBox(height: 18),
            StartRow(
              label: 'Start sharing',
              note:
                  'Puts this Mac on ${widget.gridName}. You can stop at any '
                  'time.',
              // A split model missing a shard cannot be loaded. Refusing here
              // beats a join that fails inside llama.cpp a minute later.
              onPressed: _model == null || starting || incomplete
                  ? null
                  : _start,
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
      ),
    );
  }
}

/// One of the CLI's picks: what it is, what it costs, and one press to get it.
class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.pick,
    required this.busy,
    required this.onDownload,
  });

  final RecommendedPick pick;
  final bool busy;
  final VoidCallback onDownload;

  /// `UD-IQ3_S · 16.5 GB on disk · needs 32 GB to run`, with every part that
  /// was actually measured and none that was not.
  String get _meta => [
    if (pick.quant != null) pick.quant!,
    if (pick.sizeBytes != null) '${modelSizeLabel(pick.sizeBytes!)} on disk',
    if (pick.minVramGb != null) 'needs ${pick.minVramGb} GB to run',
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final meta = _meta;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(pick.name, style: ShareType.cardTitle),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(meta, style: ShareType.note),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        ShareButton(
          label: 'Download',
          icon: LucideIcons.download300,
          kind: ShareButtonKind.secondary,
          small: true,
          onPressed: busy ? null : onDownload,
        ),
      ],
    );
  }
}
