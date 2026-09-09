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
  const ModelPickerGroupHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Padding(
      // Aligned with the column an [AppMenuItem]'s label starts on, so a header
      // sits over its rows rather than beside them: the row's own gutter, plus
      // its padding, plus the empty icon slot and the gap after it.
      padding: EdgeInsets.only(
        left:
            6 +
            AppMenuRowMetrics.roomy.padding.left +
            AppMenuRowMetrics.roomy.iconSize +
            9,
        right: 12,
        top: 10,
        bottom: 2,
      ),
      child: Text(
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
      ),
    );
  }
}

/// Wider than the dropdown it replaces: this list carries a model id AND the
/// provider it is served by, and the ids are long.
const double kModelPickerWidth = 520;

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
double modelPickerItemExtent(ModelPickerItem item) => switch (item) {
  ModelPickerHeader() => _headerExtent,
  ModelPickerNote() => kModelPickerNoteExtent,
  ModelPickerRow() => AppMenuRowMetrics.roomy.extent,
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
