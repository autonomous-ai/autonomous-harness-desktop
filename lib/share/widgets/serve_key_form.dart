import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/share_page_theme.dart';
import '../api_providers.dart';
import '../node_identity.dart';
import '../share_controller.dart';
import '../share_route.dart';
import '../stored_keys.dart';
import 'share_fields.dart';
import 'share_form_parts.dart';
import 'share_steps.dart';

/// Lend a vendor key to the grid, as the same three steps as the other routes.
///
/// Nothing is downloaded and nothing runs here: the grid forwards questions to
/// the provider using this key, and what it spends is billed to the account the
/// key belongs to. That sentence is the whole reason this route reads
/// differently from the other two, so the pane says it before the field.
///
/// Step 3 is shorter here than on the other routes, and says why: the CLI
/// refuses `--advertise-as` and `--ctx-size` for an API engine, because OpenAI
/// owns both. What is left is this computer's own name, which every route sends
/// — it used to be missing from this one, so a machine lending a key joined
/// under a name the reader never saw.
class ServeKeyForm extends StatefulWidget {
  const ServeKeyForm({
    super.key,
    required this.controller,
    required this.offers,
    this.storedKinds,
  });

  final ShareController controller;
  final List<KeyProviderOffer> offers;

  /// Injected by tests. Null reads `~/.grid/api_keys.toml`.
  final Set<String>? storedKinds;

  @override
  State<ServeKeyForm> createState() => _ServeKeyFormState();
}

class _ServeKeyFormState extends State<ServeKeyForm> {
  final _key = TextEditingController();
  final _nodeName = TextEditingController(text: thisComputerName);

  late KeyProviderOffer _offer = widget.offers.first;
  late final Set<String> _stored = widget.storedKinds ?? readStoredApiKinds();

  /// The models the reader has switched **off**.
  ///
  /// Off rather than on, so "nothing chosen" means everything — which is both
  /// the sensible default and the CLI's own: a key that can serve five models
  /// serving one of them is a decision, not a starting point. It also keeps the
  /// join argument empty in the common case rather than listing five names the
  /// CLI would have found anyway.
  final Set<String> _off = {};

  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _key.addListener(_onEdited);
  }

  void _onEdited() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _key.removeListener(_onEdited);
    _key.dispose();
    _nodeName.dispose();
    super.dispose();
  }

  bool get _hasStoredKey => _stored.contains(_offer.provider.kind);

  bool get _ready => _key.text.trim().isNotEmpty || _hasStoredKey;

  /// What to advertise: nothing when every model is on, which is the CLI's
  /// zero-config default, else exactly the ones left on.
  List<String> get _models => _off.isEmpty
      ? const []
      : [
          for (final model in _offer.models)
            if (!_off.contains(model.advertised)) model.advertised,
        ];

  int get _onCount => _offer.models.length - _off.length;

  Future<void> _share() async {
    await widget.controller.startKey(
      kind: _offer.provider.kind,
      envVar: _offer.provider.envVar,
      apiKey: _key.text.trim(),
      nodeName: _nodeName.text,
      models: _models,
    );
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ShareSteps(
      children: [routeChosenStep(ShareRoute.key), _keyStep(), _startStep()],
    );
  }

  Widget _keyStep() {
    final joining = widget.controller.status == ShareStatus.starting;
    final provider = _offer.provider;
    return ShareStep(
      index: 2,
      state: _ready ? ShareStepState.done : ShareStepState.current,
      title: 'Your ${provider.label} key, and what it may serve',
      blurb:
          "The key goes into the engine's environment and never onto a command "
          'line, so no other process on this Mac can read it.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 13),
          // One plate, with a rule inside it: the key and what it may serve are
          // two halves of one decision, and two cards made them read as two.
          SharePlate(
            children: [
              if (widget.offers.length > 1) ...[
                ShareField(
                  label: 'Provider',
                  child: ShareSelect(
                    value: provider.label,
                    options: [
                      for (final offer in widget.offers)
                        ShareOption(offer.provider.label),
                    ],
                    onSelected: (label) => setState(() {
                      _offer = widget.offers.firstWhere(
                        (offer) => offer.provider.label == label,
                      );
                      _off.clear();
                    }),
                    enabled: !joining,
                  ),
                ),
                const SizedBox(height: 18),
              ],
              ShareField(
                label: '${provider.label} API key',
                child: ShareTextField(
                  controller: _key,
                  // Hidden by default: a key usually leaves a machine over
                  // somebody's shoulder. Revealable, because a mistyped one
                  // fails minutes later with a vendor error nobody can connect
                  // back to a typo.
                  obscure: !_revealed,
                  hint: _hasStoredKey
                      ? 'Using the key already on this computer'
                      : provider.keyHint,
                  // Inside the box, on the text's line — the eye belongs to
                  // this field rather than being a control parked beside it.
                  trailing: ShareGlyphButton(
                    icon: _revealed
                        ? LucideIcons.eyeOff300
                        : LucideIcons.eye300,
                    tooltip: _revealed ? 'Hide' : 'Show',
                    onPressed: () => setState(() => _revealed = !_revealed),
                  ),
                ),
              ),
              if (provider.keyHelpUrl != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: ShareLink(
                    label: 'Where to find your key →',
                    onPressed: () => launchUrl(Uri.parse(provider.keyHelpUrl!)),
                  ),
                ),
              const SizedBox(height: 14),
              Divider(height: 1, color: SharePalette.innerRule),
              const SizedBox(height: 16),
              Text(
                "Models you're willing to share",
                style: ShareType.fieldLabel,
              ),
              const SizedBox(height: 11),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final model in _offer.models)
                    ShareToggleChip(
                      label: model.vendorName,
                      on: !_off.contains(model.advertised),
                      onTap: () => setState(() {
                        if (!_off.remove(model.advertised)) {
                          _off.add(model.advertised);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              // The count is the state said in words, so the row of chips never
              // has to be counted by eye to find out what it is offering.
              Text(
                _off.isEmpty
                    ? 'All ${_offer.models.length} offered to the grid — '
                          '${_offer.provider.label} picks whichever fits the '
                          'question.'
                    : '$_onCount of ${_offer.models.length} offered to the '
                          'grid. Switch them all on to let '
                          '${_offer.provider.label} decide.',
                style: ShareType.note,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _startStep() {
    final joining = widget.controller.status == ShareStatus.starting;
    final provider = _offer.provider;
    return ShareStep(
      index: 3,
      isLast: true,
      // Never `waiting`, unlike the local route's third step. There the name is
      // derived from a model that is not on the disk yet, so the step has
      // nothing to show; here the only field is this computer's name, which can
      // be typed before the key is. What is missing is said on the button's own
      // line instead of greying out a box somebody can legitimately fill in.
      state: ShareStepState.current,
      title: 'Name it and start sharing',
      blurb:
          '${provider.label} owns the model names and the context window, so '
          'there is nothing to rename or resize here — only what this Mac is '
          'called on the grid.',
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
                      label: "This computer's name",
                      child: ShareTextField(controller: _nodeName),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          StartRow(
            label: 'Start sharing',
            note: switch ((_ready, _hasStoredKey && _key.text.trim().isEmpty)) {
              (false, _) =>
                'Enter a valid API key to start sharing cloud models.',
              // Honest about which key is about to be used, which Grid's own
              // form cannot say because it never looks.
              (_, true) =>
                'Reusing the ${provider.label} key already on this computer.',
              _ =>
                'What the grid uses is billed to your ${provider.label} '
                    'account.',
            },
            onPressed: _ready && !joining ? _share : null,
            busy: joining,
          ),
        ],
      ),
    );
  }
}
