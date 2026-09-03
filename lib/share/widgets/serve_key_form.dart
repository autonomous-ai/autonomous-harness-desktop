import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/share_page_theme.dart';
import '../api_providers.dart';
import '../node_identity.dart';
import '../share_controller.dart';
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
  });

  final ShareController controller;
  final List<KeyProviderOffer> offers;

  @override
  State<ServeKeyForm> createState() => _ServeKeyFormState();
}

class _ServeKeyFormState extends State<ServeKeyForm> {
  final _key = TextEditingController();
  final _nodeName = TextEditingController(text: thisComputerName);

  late KeyProviderOffer _offer = widget.offers.first;

  /// Which models to advertise. Empty means every one the key can see, which is
  /// the CLI's own default and the right one: a key that can serve five models
  /// serving one of them is a choice, not a starting point.
  final Set<String> _models = {};

  @override
  void dispose() {
    _key.dispose();
    _nodeName.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    await widget.controller.startKey(
      kind: _offer.provider.kind,
      envVar: _offer.provider.envVar,
      apiKey: _key.text.trim(),
      nodeName: _nodeName.text,
      models: _models.toList(),
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
                    _models.clear();
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
                hint: provider.keyHint,
                // Obscured because it is over somebody's shoulder that a key
                // usually leaves a machine.
                obscure: true,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    // True, and worth saying plainly: the key is handed to the
                    // CLI in the process environment, never on a command line
                    // and never to this app's own servers.
                    'The key goes to the Grid CLI on this computer and stays '
                    'here. Leave it blank to reuse the one already stored.',
                    style: ShareType.note,
                  ),
                ),
                if (provider.keyHelpUrl != null)
                  TextButton(
                    onPressed: () => launchUrl(Uri.parse(provider.keyHelpUrl!)),
                    style: TextButton.styleFrom(
                      foregroundColor: SharePalette.accent,
                      minimumSize: const Size(0, 26),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: const Text('Get a key →'),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            ShareField(
              label: "This computer's name",
              child: ShareTextField(controller: _nodeName),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SharePlate(
          children: [
            Text('Models to offer', style: ShareType.fieldLabel),
            const SizedBox(height: 3),
            Text(
              _models.isEmpty
                  ? 'Everything this key can reach.'
                  : '${_models.length} of ${_offer.models.length} chosen.',
              style: ShareType.note,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final model in _offer.models)
                  _ModelChip(
                    label: model.vendorName,
                    selected: _models.contains(model.advertised),
                    onTap: () => setState(() {
                      if (!_models.remove(model.advertised)) {
                        _models.add(model.advertised);
                      }
                    }),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        StartRow(
          label: 'Start sharing',
          note: 'What the grid uses is billed to your ${provider.label} '
              'account.',
          onPressed: joining ? null : _share,
          busy: joining,
        ),
      ],
    );
  }
}

class _ModelChip extends StatelessWidget {
  const _ModelChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? SharePalette.accentRing : SharePalette.fieldFill,
            border: Border.all(
              color: selected ? SharePalette.accent : SharePalette.fieldRim,
            ),
            borderRadius: BorderRadius.circular(ShareMetrics.fieldRadius),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? grid.AppFont.semibold : FontWeight.w400,
              color: selected ? SharePalette.accent : SharePalette.labelInk,
            ),
          ),
        ),
      ),
    );
  }
}
