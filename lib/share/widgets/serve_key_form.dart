import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/share_page_theme.dart';
import '../api_providers.dart';
import '../share_controller.dart';
import '../stored_keys.dart';
import 'share_fields.dart';
import 'share_form_parts.dart';

/// Lend a vendor key to the grid.
///
/// Nothing is downloaded and nothing runs here: the grid forwards questions to
/// the provider using this key, and what it spends is billed to the account the
/// key belongs to. That sentence is the whole reason this route reads
/// differently from the other two, so the pane says it before the field.
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

  Future<void> _share() async {
    await widget.controller.startKey(
      kind: _offer.provider.kind,
      envVar: _offer.provider.envVar,
      apiKey: _key.text.trim(),
      nodeName: '',
      models: _models,
    );
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final joining = widget.controller.status == ShareStatus.starting;
    final provider = _offer.provider;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
              child: ShareFieldSkin(
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _key,
                        // Hidden by default: a key usually leaves a machine
                        // over somebody's shoulder. Revealable, because a
                        // mistyped one fails minutes later with a vendor error
                        // nobody can connect back to a typo.
                        obscureText: !_revealed,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: SharePalette.ink,
                        ),
                        cursorColor: SharePalette.accent,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          hintText: _hasStoredKey
                              ? 'Using the key already on this computer'
                              : provider.keyHint,
                          hintStyle: TextStyle(
                            fontSize: 13.5,
                            color: SharePalette.helper,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _revealed = !_revealed),
                      icon: Icon(
                        _revealed ? LucideIcons.eyeOff300 : LucideIcons.eye300,
                        size: 15,
                      ),
                      color: SharePalette.eyebrow,
                      tooltip: _revealed ? 'Hide' : 'Show',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 26,
                        height: 26,
                      ),
                      splashRadius: 14,
                    ),
                  ],
                ),
              ),
            ),
            if (provider.keyHelpUrl != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => launchUrl(Uri.parse(provider.keyHelpUrl!)),
                  style: TextButton.styleFrom(
                    foregroundColor: SharePalette.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    minimumSize: const Size(0, 26),
                    textStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: grid.AppFont.semibold,
                    ),
                  ),
                  child: const Text('Where to find your key →'),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Divider(height: 1, color: SharePalette.innerRule),
            const SizedBox(height: 16),
            Text("Models you're willing to share", style: ShareType.fieldLabel),
            const SizedBox(height: 3),
            Text(
              'Only the ones left on get offered to the grid.',
              style: ShareType.note,
            ),
            const SizedBox(height: 11),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final model in _offer.models)
                  _ModelToggle(
                    // The state is IN the label, not only in the colour: a row
                    // of chips where the difference is a tint asks the reader
                    // to compare two greys to find out what they picked.
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
          ],
        ),
        const SizedBox(height: 18),
        StartRow(
          label: 'Start cloud engine',
          note: switch ((_ready, _hasStoredKey && _key.text.trim().isEmpty)) {
            (false, _) =>
              'Enter a valid API key to start sharing cloud models.',
            // Honest about which key is about to be used, which Grid's own form
            // cannot say because it never looks.
            (_, true) => 'Reusing the ${provider.label} key already on this '
                'computer.',
            _ => 'What the grid uses is billed to your ${provider.label} '
                'account.',
          },
          onPressed: _ready && !joining ? _share : null,
          busy: joining,
        ),
      ],
    );
  }
}

/// One model, and whether it is on offer.
class _ModelToggle extends StatelessWidget {
  const _ModelToggle({
    required this.label,
    required this.on,
    required this.onTap,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: on ? SharePalette.accentRing : SharePalette.fieldFill,
            border: Border.all(
              color: on ? SharePalette.accent : SharePalette.fieldRim,
            ),
            borderRadius: BorderRadius.circular(ShareMetrics.fieldRadius),
          ),
          child: Text(
            '$label · ${on ? 'on' : 'off'}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: on ? grid.AppFont.semibold : FontWeight.w400,
              color: on ? SharePalette.accent : SharePalette.helper,
            ),
          ),
        ),
      ),
    );
  }
}
