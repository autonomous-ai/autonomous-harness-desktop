import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../grid/grid_access.dart';
import '../../grid/grid_network.dart';
import '../../grid/grid_selection_store.dart';
import '../../shared/theme/app_theme.dart' as grid;

/// The grid new agents launch against, drawn as the pane's headline.
///
/// This replaces the one-line strip that used to sit here. The strip said the
/// right thing but said it at the same weight as everything under it, so the
/// question the pane exists to answer — "where do my agents run right now" —
/// was a line you read only if you went looking. Here it is the first thing on
/// the screen, at a size nothing else competes with.
///
/// It also gives the grid's own actions somewhere to live. Share, Rename and
/// Delete used to be reachable only by opening a row's drawer; the chosen grid
/// carries them at the top instead, and a row's drawer keeps them for the
/// others.
///
/// [network] is null in the two states that are not a grid: no grid picked
/// (agents run on each engine's own account), or the chosen grid has not
/// arrived in the fetched list yet. [chosen] still names it in the second case,
/// which is what lets the headline print a name on the first frame instead of
/// waiting for the network.
class GridHero extends StatelessWidget {
  const GridHero({
    super.key,
    required this.chosen,
    required this.network,
    required this.owned,
    this.onShare,
    this.onRename,
    this.onDelete,
    this.deleting = false,
  });

  final GridSelection chosen;

  /// The chosen grid as the control plane describes it, when the list has
  /// arrived and still holds it.
  final GridNetwork? network;

  /// Whether this account owns [network] — what decides if Rename and Delete
  /// are drawn at all. The server refuses a non-owner anyway, and an action
  /// that can only fail is worse than one that is not offered.
  final bool owned;

  final VoidCallback? onShare;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final bool deleting;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final on = chosen.hasGrid;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 15, 14, 15),
      decoration: BoxDecoration(
        // With a grid: the accent wash, because this block IS the live target.
        //
        // Without one: a slate wash — a colour, but pointedly not the accent's.
        //
        // Grey was tried twice and failed twice. `AppSurface.recess` is a well
        // pressed INTO the page, and `cardBg` measures #1e1e1e against the
        // table's #202020 — darker than the thing it sits above, so the block
        // sank and read as disabled or unloaded. Neither is what this state is:
        // running on each engine's own account is a setting somebody chose, the
        // way the app worked before grids.
        //
        // [AppSurface.neutralWash] says "a state, and not the live one" in a
        // hue of its own. Its doc records which colours were NOT available and
        // why.
        color: on ? grid.AppSurface.accentWash : grid.AppSurface.neutralWash,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: on
              ? grid.AppPalette.accent.withValues(alpha: 0.26)
              : grid.AppSurface.neutralRim,
        ),
      ),
      // ⚠️ ONE height, whatever is inside.
      //
      // This block sits directly above the list you pick from, so any height it
      // gains on selection shoves that list down — out from under the pointer
      // that just clicked it, on the one gesture this pane exists for. An
      // earlier build grew from 77px to 170px the moment a grid was chosen,
      // which moved every row 93px mid-click.
      //
      // The floor is what the fuller state needs; both states then fill it.
      // `grid_hero_test.dart` measures this.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _contentHeight),
        child: on
            ? _Chosen(
                chosen: chosen,
                network: network,
                owned: owned,
                onShare: onShare,
                onRename: onRename,
                onDelete: onDelete,
                deleting: deleting,
              )
            : const _NoGrid(),
      ),
    );
  }

  /// What the taller of the two states occupies, less the container's padding.
  ///
  /// MEASURED off the chosen-grid layout — kicker, title, facts, rule, actions
  /// — not derived from the type ramp, for the reason `AppMenuRowMetrics` gives
  /// about its own row: a line box rounds up to the font's metrics rather than
  /// taking `fontSize × height` literally, so arithmetic lands a pixel or two
  /// short and the block twitches on selection. `grid_hero_test.dart` fails if
  /// this and the real layout drift apart.
  static const double _contentHeight = 140;
}

/// The headline with a grid in it: what it is, what it admits, what you can do
/// to it.
class _Chosen extends StatelessWidget {
  const _Chosen({
    required this.chosen,
    required this.network,
    required this.owned,
    required this.onShare,
    required this.onRename,
    required this.onDelete,
    required this.deleting,
  });

  final GridSelection chosen;
  final GridNetwork? network;
  final bool owned;
  final VoidCallback? onShare;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final bool deleting;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Kicker(on: true),
        const SizedBox(height: 7),
        _Title(text: chosen.targetLabel, muted: false, id: network?.networkId),
        if (network case final GridNetwork grid_) ...[
          const SizedBox(height: 12),
          _Facts(network: grid_, owned: owned),
          const SizedBox(height: 13),
          Divider(height: 1, color: grid.AppPalette.divider),
          const SizedBox(height: 11),
          _Actions(
            owned: owned,
            onShare: onShare,
            onRename: onRename,
            onDelete: onDelete,
            deleting: deleting,
          ),
        ],
      ],
    );
  }
}

/// The headline with no grid in it.
///
/// Not the chosen-grid layout with its contents removed — that left a title, a
/// lone pill and a divider ruling off an empty half, which reads as a card that
/// failed to load. This says the one thing that is true instead: agents run on
/// each engine's own account, and what picking a grid would change.
///
/// It also does NOT repeat the words "No grid". The list below already carries
/// a row by that name, marked as chosen, and the same two words twice on one
/// screen is how a reader comes to wonder whether they are two settings.
class _NoGrid extends StatelessWidget {
  const _NoGrid();

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Kicker(on: false),
        const SizedBox(height: 7),
        Text(
          'Each engine\u2019s own account',
          style: TextStyle(
            color: grid.AppPalette.textPrimary,
            fontFamily: grid.AppFont.sans,
            fontSize: 23,
            fontWeight: grid.AppFont.semibold,
            letterSpacing: -0.45,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 9),
        // ONE sentence, and it says what the title cannot.
        //
        // Three rules it is written to. **No engine is named**: seven are
        // grid-capable (see `kGridCapableEngines`) and naming Claude Code —
        // which an earlier draft did — tells six other users the line is not
        // about them. **It does not restate the title**: "each engine signs in
        // with its own account" is the heading in other words, and the row for
        // this state in the list below already carries that sentence, so a
        // third copy would be the same fact three times on one screen. **It
        // does not instruct**: a line reading "pick a grid below…" belonged to
        // a different question than the one this block answers, which is only
        // ever "what is running now".
        //
        // What is left is the consequence — where the models and the bill come
        // from — which is the half a person actually weighs when choosing.
        Text(
          'Models and billing come from each engine\u2019s own account, the way '
          'the app worked before grids.',
          style: TextStyle(
            color: grid.AppPalette.textSecondary,
            fontFamily: grid.AppFont.sans,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

/// `⚡ NEW AGENTS USE` — the label, with a live dot when a grid is actually
/// carrying the work.
class _Kicker extends StatelessWidget {
  const _Kicker({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          LucideIcons.zap300,
          size: 13,
          color: on ? grid.AppPalette.accentOnSurface : grid.AppPalette.textFaint,
        ),
        const SizedBox(width: 7),
        Text(
          'NEW AGENTS USE',
          style: TextStyle(
            color: on
                ? grid.AppPalette.accentOnSurface
                : grid.AppPalette.textFaint,
            fontFamily: grid.AppFont.sans,
            fontSize: 10,
            fontWeight: grid.AppFont.semibold,
            letterSpacing: 0.9,
          ),
        ),
      ],
    );
  }
}

/// The grid's name at headline size, with its id trailing in mono.
///
/// The id is on the same baseline rather than under the name: it is a fact you
/// copy, not a subtitle you read, and stacking it would give the block a second
/// line of weight it has not earned.
class _Title extends StatelessWidget {
  const _Title({required this.text, required this.muted, this.id});

  final String text;
  final bool muted;
  final String? id;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 11,
      runSpacing: 3,
      children: [
        Text(
          text,
          style: TextStyle(
            color: muted
                ? grid.AppPalette.textSecondary
                : grid.AppPalette.textPrimary,
            fontFamily: grid.AppFont.sans,
            fontSize: 23,
            fontWeight: grid.AppFont.semibold,
            letterSpacing: -0.45,
            height: 1.1,
          ),
        ),
        if (id != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              id!,
              style: TextStyle(
                color: grid.AppPalette.textFaint,
                fontFamily: grid.AppFont.mono,
                fontFamilyFallback: grid.AppFont.monoFallback,
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }
}

/// The three facts that differ between grids, as pills.
///
/// Deliberately not the six the drawer shows: this block answers "what am I
/// pointed at", and signaling URLs and status codes are things you look up
/// rather than things you keep an eye on.
class _Facts extends StatelessWidget {
  const _Facts({required this.network, required this.owned});

  final GridNetwork network;
  final bool owned;

  @override
  Widget build(BuildContext context) {
    final grid_ = network;
    final rule = gridAccessRule(grid_);
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        if (rule != null) _Pill(label: 'JOIN', value: rule.label),
        _Pill(
          label: 'ROUTER',
          value: grid_.routerEnabled
              ? _routerValue(grid_.routerAdvisors.length)
              : 'Off',
          dim: !grid_.routerEnabled,
        ),
        _Pill(
          label: owned ? 'OWNER' : 'OWNED BY',
          value: owned ? 'You' : grid_.ownerEmail,
        ),
      ],
    );
  }

  /// One advisor is a name, not a total — but at this size the count is what
  /// fits, and the drawer still prints them.
  static String _routerValue(int advisors) => switch (advisors) {
    0 => 'On',
    1 => 'On · 1 model',
    _ => 'On · $advisors models',
  };
}

/// A `LABEL value` pill — the label in micro-caps, the value in reading ink.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.value, this.dim = false});

  final String label;
  final String value;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 5, 11, 5),
      decoration: BoxDecoration(
        color: grid.AppSurface.recess,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: grid.AppGlass.hair),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: grid.AppPalette.textFaint,
              fontFamily: grid.AppFont.sans,
              fontSize: 9.5,
              fontWeight: grid.AppFont.semibold,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: dim
                    ? grid.AppPalette.textSecondary
                    : grid.AppPalette.textPrimary,
                fontFamily: grid.AppFont.sans,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Share · Rename · Delete for the grid in the headline.
///
/// Rename and Delete appear only on a grid this account owns; the line at the
/// end says who owns it when that is somebody else, so the absence explains
/// itself instead of reading as a missing button.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.owned,
    required this.onShare,
    required this.onRename,
    required this.onDelete,
    required this.deleting,
  });

  final bool owned;
  final VoidCallback? onShare;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final bool deleting;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Row(
      children: [
        if (onShare != null)
          FilledButton.icon(
            onPressed: onShare,
            style: FilledButton.styleFrom(
              // Even setting only a size, `styleFrom` replaces the theme's
              // style and takes the hover wash with it. See `_textButtonStyle`.
              overlayColor: const Color(0x1FFFFFFF),
              minimumSize: const Size(0, grid.AppControl.heightSmall),
              padding: grid.AppControl.paddingSmallIcon,
            ),
            icon: const Icon(
              LucideIcons.userPlus300,
              size: grid.AppControl.iconSize,
            ),
            label: const Text('Share'),
          ),
        if (owned && onRename != null) ...[
          const SizedBox(width: 6),
          TextButton.icon(
            key: const Key('grid-hero-rename'),
            onPressed: onRename,
            style: _quiet(context),
            icon: const Icon(
              LucideIcons.pencil300,
              size: grid.AppControl.iconSize,
            ),
            label: const Text('Rename'),
          ),
        ],
        if (owned && onDelete != null) ...[
          const SizedBox(width: 2),
          TextButton.icon(
            key: const Key('grid-hero-delete'),
            onPressed: deleting ? null : onDelete,
            style: TextButton.styleFrom(
              foregroundColor: grid.AppPalette.dangerFill,
              overlayColor: grid.AppPalette.dangerFill,
              minimumSize: const Size(0, grid.AppControl.heightSmall),
              padding: grid.AppControl.paddingSmallIcon,
              textStyle: TextStyle(
                fontFamily: grid.AppFont.sans,
                fontSize: 12.5,
              ),
            ),
            icon: deleting
                ? const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    LucideIcons.trash2300,
                    size: grid.AppControl.iconSize,
                  ),
            label: Text(deleting ? 'Deleting…' : 'Delete'),
          ),
        ],
        // Nothing is said about the actions a non-owner does not get. The
        // OWNED BY pill above already names whose grid this is, which is the
        // fact; spelling out the consequence tells somebody they cannot do a
        // thing they had not asked to do, in a row that is otherwise theirs.
      ],
    );
  }

  /// ⚠️ `overlayColor` is restated here on purpose.
  ///
  /// `styleFrom` builds a whole ButtonStyle and REPLACES the theme's, so a
  /// button that sets `foregroundColor` this way silently drops the hover wash
  /// `_textButtonStyle` declares — and with `NoSplash` app-wide there is then
  /// nothing at all under the pointer. Every `styleFrom` in this pane carries
  /// its own; the Delete button beside this one carries the danger tint for the
  /// same reason.
  ButtonStyle _quiet(BuildContext context) => TextButton.styleFrom(
    foregroundColor: grid.AppPalette.textSecondary,
    overlayColor: grid.AppSurface.hoverFill,
    minimumSize: const Size(0, grid.AppControl.heightSmall),
    padding: grid.AppControl.paddingSmallIcon,
    textStyle: TextStyle(fontFamily: grid.AppFont.sans, fontSize: 12.5),
  );
}
