import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../grid/grid_network.dart';
import '../../grid/grid_networks_controller.dart';
import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/share_page_theme.dart';
import '../share_controller.dart';
import '../share_target_store.dart';
import 'share_fields.dart';

/// One grid this computer could serve.
@immutable
class ShareTargetOption {
  const ShareTargetOption({required this.networkId, required this.label});

  final String networkId;

  /// What the row says. Not always [GridNetwork.displayName] — see
  /// [shareTargetOptions].
  final String label;
}

/// The rows of the picker, from the grids this account is on.
///
/// Two grids may carry the same name — nothing stops an account joining
/// `research` at two different companies — and a picker with two identical rows
/// is one where the reader cannot tell which one they just chose. Where a name
/// repeats, and only there, the tail of the id is appended: an ugly row is a
/// far smaller problem than an ambiguous one, and a name that is already unique
/// is left exactly as the user wrote it.
///
/// Deliberately NOT filtered by Settings ▸ Providers' switches. That switch
/// means "do not offer me this one" for grids this machine *takes* work from;
/// sharing is what it *gives*, and a grid you never send agents to is a
/// perfectly ordinary one to lend a GPU. Filtering here would also make the one
/// thing this picker exists for — being independent of that page — quietly
/// untrue.
List<ShareTargetOption> shareTargetOptions(List<GridNetwork> networks) {
  final byName = <String, int>{};
  for (final network in networks) {
    byName[network.displayName] = (byName[network.displayName] ?? 0) + 1;
  }
  return [
    for (final network in networks)
      ShareTargetOption(
        networkId: network.networkId,
        label: (byName[network.displayName] ?? 0) > 1
            ? '${network.displayName} · ${_shortId(network.networkId)}'
            : network.displayName,
      ),
  ];
}

/// Enough of an id to tell two same-named grids apart, without printing all 22
/// characters of it in a 396px rail.
String _shortId(String networkId) {
  final tail = networkId.split('-').last;
  return tail.length <= 6 ? tail : tail.substring(0, 6);
}

/// What the picker says when it has no rows to offer, or null when it has.
///
/// Every one of these is a different problem with a different fix, and the
/// version that printed "No grids" at all four made the account with none look
/// identical to the one whose fetch had failed.
String? shareTargetPlaceholder(GridNetworksState state) => switch (state) {
  GridNetworksIdle() || GridNetworksLoading() => 'Loading your grids…',
  GridNetworksSignedOut() => 'Sign in to Grid in Settings ▸ Providers',
  GridNetworksFailed(:final message) => message,
  GridNetworksReady(:final me) =>
    me.networks.isEmpty ? 'This account is on no grids' : null,
};

/// Which grid this computer serves — chosen here, and only here.
///
/// The block exists because the answer used to be a side effect of a setting on
/// another screen. It carries a sentence saying so in every state it can be in:
/// a reader looking at `bubu1` on this page has to be able to tell, without
/// leaving it, whether the agents they start are on `bubu1` too. See
/// [ShareTargetStore].
class ShareTargetPicker extends StatelessWidget {
  const ShareTargetPicker({
    super.key,
    required this.target,
    required this.providersDefaultLabel,
    required this.state,
    required this.status,
    required this.onPick,
    required this.onFollowDefault,
  });

  /// The grid a share would join right now, and where that came from.
  final ResolvedShareTarget target;

  /// What Settings ▸ Providers points at, for the sentence that compares them.
  /// Empty when Providers has no default at all.
  final String providersDefaultLabel;

  final GridNetworksState state;

  /// The picker locks while an engine is up — see [_locked].
  final ShareStatus status;

  final void Function(String networkId, String networkName) onPick;
  final VoidCallback onFollowDefault;

  /// An engine is detached and joined to ONE grid. Letting the picker move
  /// while one is up would leave it serving a grid this page no longer shows —
  /// still answering questions, still costing whatever it costs, and with no
  /// Stop button anywhere for it, because Stop only ever leaves the grid the
  /// page is currently on. Locking is the honest version of a limit this app
  /// already has.
  bool get _locked =>
      status == ShareStatus.live ||
      status == ShareStatus.starting ||
      status == ShareStatus.stopping;

  List<ShareTargetOption> get _options => switch (state) {
    GridNetworksReady(:final me) => shareTargetOptions(me.networks),
    _ => const [],
  };

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final options = _options;
    // A plate, and the same recipe as the status block directly under it
    // (`share_rail.dart`): surface on the rail's ground, one hairline, the same
    // radius and padding. Loose on the rail it read as the quietest thing on a
    // page it is the most consequential control on — it decides which grid gets
    // this machine's GPU and keys. Deliberately NOT the accent: on this page
    // blue means "the thing to press", and a picker wearing it would compete
    // with the button that actually starts the share. Making it a matched pair
    // with the status block is the lift, because the two are one thought — who
    // this computer answers, and what it is doing about it.
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: SharePalette.surface,
        border: Border.all(color: SharePalette.rim),
        borderRadius: BorderRadius.circular(ShareMetrics.statusRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // The settings row's own glyph, so the block is tied to the page
              // it belongs to rather than wearing a new symbol nobody has seen.
              Icon(
                LucideIcons.share2300,
                size: 12.5,
                color: SharePalette.labelInk,
              ),
              const SizedBox(width: 6),
              // A step brighter than a plain eyebrow — this is the block's
              // title, not a caption over a form field.
              Text(
                'GRID TO SHARE WITH',
                style: ShareType.eyebrow.copyWith(color: SharePalette.labelInk),
              ),
            ],
          ),
          const SizedBox(height: 9),
          // ⚠️ The SizedBox is load-bearing, not tidying. [ShareSelect] measures
          // itself with a `LayoutBuilder` so its panel is never narrower than the
          // field — and a LayoutBuilder cannot answer an intrinsic query, which
          // is exactly what the rail asks of every child: it wraps its column in
          // an `IntrinsicHeight` so the footnote can be pushed to the bottom by a
          // `Spacer`. Dropping the select in bare threw
          // "LayoutBuilder does not support returning intrinsic dimensions" and
          // took the whole page down to a blank pane. A tight height stops the
          // query at this box — `RenderConstrainedBox` answers from its own
          // constraints without descending — and costs nothing, because the field
          // is already exactly this tall (`ShareFieldSkin.height`).
          SizedBox(
            height: ShareMetrics.controlHeight,
            child: ShareSelect(
              key: const Key('share-target-select'),
              value: _selectedLabel(options),
              options: [
                for (final option in options) ShareOption(option.label),
              ],
              placeholder:
                  shareTargetPlaceholder(state) ??
                  'Choose a grid to share with',
              enabled: !_locked,
              // The grid's name is the answer this whole block exists to give,
              // so it carries more weight than the boxes in the forms opposite.
              valueStyle: ShareType.fieldValue.copyWith(
                fontWeight: grid.AppFont.semibold,
              ),
              onSelected: (label) {
                for (final option in options) {
                  if (option.label != label) continue;
                  onPick(option.networkId, option.label);
                  return;
                }
              },
            ),
          ),
          const SizedBox(height: 9),
          _Explanation(
            target: target,
            providersDefaultLabel: providersDefaultLabel,
            locked: _locked,
            missing: _pinnedIsGone(options),
            onFollowDefault: onFollowDefault,
          ),
        ],
      ),
    );
  }

  /// The row to tick, matched on the id and falling back to the remembered
  /// name.
  ///
  /// Matching on the id and not the label matters exactly where the label is
  /// not the name — a grid disambiguated by [shareTargetOptions] would
  /// otherwise show as nothing selected, on the one screen where "which grid"
  /// is the whole question.
  String? _selectedLabel(List<ShareTargetOption> options) {
    if (!target.hasGrid) return null;
    for (final option in options) {
      if (option.networkId == target.networkId) return option.label;
    }
    return target.label.isEmpty ? null : target.label;
  }

  /// A pin naming a grid this account is no longer on.
  ///
  /// Only ever asked of a list that really landed: a failed or pending fetch
  /// says nothing about membership, and treating it as though it did would
  /// accuse the user of having left a grid because their wifi dropped.
  bool _pinnedIsGone(List<ShareTargetOption> options) {
    if (target.followsDefault || !target.hasGrid) return false;
    if (state is! GridNetworksReady) return false;
    return !options.any((option) => option.networkId == target.networkId);
  }
}

/// The sentence under the picker: what this choice does, and — the part people
/// get wrong — what it does NOT do.
class _Explanation extends StatelessWidget {
  const _Explanation({
    required this.target,
    required this.providersDefaultLabel,
    required this.locked,
    required this.missing,
    required this.onFollowDefault,
  });

  final ResolvedShareTarget target;
  final String providersDefaultLabel;
  final bool locked;
  final bool missing;
  final VoidCallback onFollowDefault;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_message, style: ShareType.note),
        // Offered only when it would change something. A "Follow the default"
        // link on a page that is already following it is a control whose only
        // effect is to make the reader wonder what they were doing wrong.
        if (!target.followsDefault) ...[
          const SizedBox(height: 6),
          _FollowDefaultLink(onPressed: onFollowDefault),
        ],
      ],
    );
  }

  String get _message {
    // Ordered by how badly the reader needs it. A pin pointing at a grid that
    // is gone will fail at the CLI with a message about an id nobody typed, so
    // it outranks every other thing this line could be saying.
    if (missing) {
      return 'This grid is not on your account any more, so a share would be '
          'refused. Pick another, or go back to the Providers default.';
    }
    if (locked) {
      return 'Locked while this computer is sharing. Stop sharing first to '
          'point it at a different grid.';
    }
    if (target.followsDefault) {
      return providersDefaultLabel.isEmpty
          ? 'No grid is chosen. Settings ▸ Providers has no default either, so '
                'pick one here to share with.'
          : 'Following the default in Settings ▸ Providers. Choose a different '
                'grid here and only this computer moves — the agents you start '
                'stay on $providersDefaultLabel.';
    }
    // Pinned. The comparison is the whole point of the sentence, so it names
    // both grids rather than saying "the default" and making the reader go and
    // look it up.
    if (providersDefaultLabel.isEmpty) {
      return 'Chosen here, not inherited. Settings ▸ Providers has no default, '
          'so this affects nothing but what this computer serves.';
    }
    if (target.label == providersDefaultLabel) {
      return 'Chosen here, not inherited — so this computer stays on '
          '${target.label} even if the Providers default moves.';
    }
    return 'This computer serves ${target.label}. Agents you start still use '
        '$providersDefaultLabel, the default in Settings ▸ Providers.';
  }
}

/// Back to inheriting the grid from Providers.
///
/// A text press rather than a button: the page already has one blue button, the
/// one that starts the share, and a second filled control beside a picker would
/// compete with it for the reader's eye at the exact moment they are meant to
/// be choosing a route.
class _FollowDefaultLink extends StatefulWidget {
  const _FollowDefaultLink({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_FollowDefaultLink> createState() => _FollowDefaultLinkState();
}

class _FollowDefaultLinkState extends State<_FollowDefaultLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Text(
          'Follow the Providers default',
          style: ShareType.note.copyWith(
            color: _hovered ? SharePalette.accentHover : SharePalette.accent,
            decoration: _hovered ? TextDecoration.underline : null,
            decorationColor: SharePalette.accentHover,
          ),
        ),
      ),
    );
  }
}
