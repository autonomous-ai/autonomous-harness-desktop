/// The model picker's furniture: its title bar, its search field, its group
/// headers, its footer — and the measurements the panel is laid out by.
///
/// Split from `model_picker_dialog.dart` so that file is the picker's BEHAVIOUR
/// (what is in the list, what the keyboard does to it, what Enter returns) and
/// this one is its shape. Nothing here holds state or decides anything; every
/// piece takes what it draws.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../grid/model_picker_options.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_menu.dart';
import '../shortcuts/key_cap.dart';

/// The panel's name, and the key that closes it.
class ModelPickerTitleBar extends StatelessWidget {
  const ModelPickerTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      child: Row(
        children: [
          Text(
            'Select model',
            style: TextStyle(
              fontFamily: grid.AppFont.sans,
              fontFamilyFallback: grid.AppFont.sansFallback,
              color: grid.AppPalette.textPrimary,
              fontSize: 14.5,
              fontWeight: grid.AppFont.semibold,
            ),
          ),
          const Spacer(),
          // The way out, drawn as the key that takes it — the same cap the
          // shortcuts sheet uses, so a reader meets one alphabet of keys.
          const KeyCap('esc'),
        ],
      ),
    );
  }
}

/// The search box the panel opens focused on.
///
/// It owns the keyboard for the whole panel: ↑/↓/↵ are handled on its own
/// [FocusNode] (see the dialog's `_onKey`), because a node's own handler runs
/// before the text-editing shortcuts an ancestor would otherwise apply first.
class ModelPickerSearchField extends StatelessWidget {
  const ModelPickerSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: TextField(
        key: const Key('model-picker-search'),
        controller: controller,
        focusNode: focusNode,
        autofocus: true,
        style: grid.kFieldTextStyle,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: 'Search models and providers',
          prefixIcon: Icon(
            LucideIcons.search300,
            size: grid.kFieldIconSize,
            color: grid.AppPalette.textFaint,
          ),
        ),
      ),
    );
  }
}

/// What picking costs, said once at the bottom rather than on every row, beside
/// the keys that drive the list.
class ModelPickerFooter extends StatelessWidget {
  const ModelPickerFooter({super.key});

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Changing the model restarts this agent and resumes the '
              'conversation',
              style: TextStyle(
                fontFamily: grid.AppFont.sans,
                fontFamilyFallback: grid.AppFont.sansFallback,
                color: grid.AppPalette.textFaint,
                fontSize: 11.5,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const KeyCap('↑↓'),
          const SizedBox(width: 4),
          const KeyCap('↵'),
        ],
      ),
    );
  }
}

/// A provider's name over the models it serves — and `Recent` over the picks
/// that came from several.
///
/// Its own small widget rather than `SectionHeading`, which is a screen's 19pt
/// group title: inside a list this size that reads as a new screen starting
/// every few rows.
class ModelPickerGroupHeader extends StatelessWidget {
  const ModelPickerGroupHeader(this.title, {super.key, this.count});

  final String title;

  /// How many rows follow — printed past the rule. See [ModelPickerHeader.count].
  final int? count;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final label = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: grid.AppFont.sans,
        fontFamilyFallback: grid.AppFont.sansFallback,
        color: grid.AppPalette.textFaint,
        fontSize: 11,
        fontWeight: grid.AppFont.semibold,
        letterSpacing: 0.4,
        height: 1.2,
      ),
    );
    return Padding(
      // Aligned with the column a row's own INK starts on — its gutter plus its
      // padding — not with the label column further in.
      //
      // ⚠️ This used to add the empty icon slot and the gap after it, landing
      // the header at 44px on the theory that a header should sit over its
      // labels. On screen that read as a header floating in from the panel's
      // edge: every row draws a hover fill from 6px, so the list has a visible
      // left edge there, and the header was the one thing not on it. A header
      // is the group's own line, not a taller row.
      padding: EdgeInsets.only(
        left: 6 + AppMenuRowMetrics.roomy.padding.left,
        top: 10,
        bottom: 2,
      ),
      // Provider, rule, count — the rule taking whatever the two ends leave.
      //
      // ⚠️ This ran short of the panel's edge for three attempts, and the fix
      // was NOT here: the picker's `ListView` used to sit under Material's
      // automatic desktop [Scrollbar], which RESERVES its channel and so laid
      // every child out narrower than the panel. Padding, negative padding and
      // an [OverflowBox] all chased that missing strip; the dialog now turns
      // the automatic scrollbar off and floats its own over the list, which
      // hands this row the panel's real width. Plain [Expanded] is enough.
      child: Row(
        children: [
          // Capped rather than [Flexible]: a hard ceiling keeps a very long
          // provider name from eating the row, without making the name a
          // second flex child competing with the rule for the gap.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: label,
          ),
          const SizedBox(width: 9),
          // ⚠️ [Expanded], and the rule is the ONLY flexible child on the row.
          //
          // It shared the row with a `Flexible` name for several attempts and
          // came up short every time: two flex children split the free space
          // between them, so the rule only ever got a fraction of the gap it
          // was supposed to fill. The name is laid out at its natural width
          // instead — provider names are short, and one long enough to crowd
          // the count is a better problem than a rule that never reaches.
          Expanded(
            child: SizedBox(
              height: 1,
              child: ColoredBox(color: grid.AppPalette.divider),
            ),
          ),
          if (count case final count?) ...[
            const SizedBox(width: 9),
            Text(
              '$count',
              style: TextStyle(
                fontFamily: grid.AppFont.sans,
                fontFamilyFallback: grid.AppFont.sansFallback,
                color: grid.AppPalette.textFaint,
                fontSize: 11,
                // Lining figures, so a column of counts down a panel of
                // providers lines up digit over digit instead of shuffling.
                fontFeatures: const [FontFeature.tabularFigures()],
                height: 1.2,
              ),
            ),
          ],
          // Ends where a ROW's text ends: its gutter plus its own padding. The
          // count and a model name then sit on one right-hand column.
          SizedBox(width: 6 + AppMenuRowMetrics.roomy.padding.right),
        ],
      ),
    );
  }
}

/// Wider than the dropdown it replaces: this list carries a model id AND the
/// provider it is served by, and the ids are long.
///
/// 460 rather than the 520 it opened at. The longest id the panel actually
/// shows — `DeepSeek-V4-Flash-0731-Vision` — measures about 205px at the row's
/// 14px, which the label column clears with room to spare; the rest was air,
/// and a dialog wider than its content reads as a window rather than a menu.
const double kModelPickerWidth = 460;

/// The list's own cap. The panel is `mainAxisSize.min`, so a short list keeps a
/// short panel and only a long one scrolls.
const double kModelPickerListHeight = 420;

/// What stands in for the list when there is nothing in it — tall enough to
/// read as the same panel rather than as a collapsed one.
const double kModelPickerEmptyHeight = 160;

/// The `vertical: 6` above the first row, which every scroll offset is measured
/// from.
const double kModelPickerListPadding = 6;

/// A note wraps to two lines before it ellipsizes (see [AppMenuNote]), and a
/// failure message is the one that uses them.
const double kModelPickerNoteExtent = 56;

const double _headerExtent = 30;

/// Material's own `Dialog` inset, doubled — the margin the panel is laid out
/// inside.
const double _dialogInset = 80;

/// Roughly what the title bar, the search field and the footer take, so the
/// list's cap leaves room for them rather than pushing them off a short window.
const double _panelChromeHeight = 190;

/// How tall one row lays out — stated rather than measured at layout time so
/// ↑/↓ can scroll the highlight into view by arithmetic: a keyboard-driven list
/// has no built row to call `ensureVisible` on until it is already on screen.
///
/// ⚠️ A row with a [ModelPickerRow.detail] lays out TALLER, and this is the
/// only place that knows it: `itemExtentBuilder` positions every row from these
/// numbers, so a row measured at 40 while it draws at 57.6 puts the list's
/// arithmetic 17.6px out from the first detail row down — which is what
/// `_offsetOf` scrolls the highlight by.
double modelPickerItemExtent(ModelPickerItem item) => switch (item) {
  ModelPickerHeader() => _headerExtent,
  ModelPickerNote() => kModelPickerNoteExtent,
  ModelPickerRow(:final detail) =>
    detail == null
        ? AppMenuRowMetrics.roomy.extent
        : AppMenuRowMetrics.roomy.detailExtent,
};

/// [kModelPickerWidth], or as much of a narrow window as the dialog's own inset
/// leaves — this is a desktop app whose window a person can drag down to a
/// column, and a panel that insisted on its own width would overflow rather
/// than shrink.
double modelPickerWidthIn(BuildContext context) {
  final available = MediaQuery.sizeOf(context).width - _dialogInset;
  return available < kModelPickerWidth ? available : kModelPickerWidth;
}

/// [kModelPickerListHeight], or what is left of a short window after the parts
/// that must not be scrolled away — one of them is the way out.
double modelPickerListHeightIn(BuildContext context) {
  final available =
      MediaQuery.sizeOf(context).height - _dialogInset - _panelChromeHeight;
  return available < kModelPickerListHeight
      ? available
      : kModelPickerListHeight;
}
