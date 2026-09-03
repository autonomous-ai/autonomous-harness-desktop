import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/share_page_theme.dart';

/// The controls the share page's forms are built from.
///
/// The design's field is a visible 1px rim at radius 9 on a light fill, where
/// this app's own idiom is a borderless capsule. Rather than hand every form
/// the same six arguments, the shape lives here once — so the model picker,
/// every name box, the endpoint field and the context ladder cannot drift apart
/// by a pixel.
///
/// Every control here answers the same three questions the rest of the app's
/// controls do: is the pointer on me, is the keyboard on me, and am I the
/// current choice. The first version of this file answered none of them.

/// A label over its control.
class ShareField extends StatelessWidget {
  const ShareField({
    super.key,
    required this.label,
    required this.child,
    this.note,
  });

  final String label;
  final Widget child;

  /// A line under the control, for what the control itself cannot say.
  final String? note;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: ShareType.fieldLabel),
        const SizedBox(height: 7),
        child,
        if (note != null) ...[
          const SizedBox(height: 6),
          Text(note!, style: ShareType.note),
        ],
      ],
    );
  }
}

/// The rim, fill and radius every control on the page sits in — and its three
/// states.
///
/// The ring on focus is drawn OUTSIDE the box rather than as a thicker border,
/// so a focused field is exactly as tall as an idle one. A border that grows on
/// focus shifts every field under it by a pixel, which is the sort of movement
/// that reads as a rendering fault.
class ShareFieldSkin extends StatelessWidget {
  const ShareFieldSkin({
    super.key,
    required this.child,
    this.onTap,
    this.hovered = false,
    this.focused = false,
    this.enabled = true,
    this.height = ShareMetrics.controlHeight,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool hovered;
  final bool focused;
  final bool enabled;
  final double height;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final live = enabled && (hovered || focused);
    final decorated = AnimatedContainer(
      duration: grid.AppMotion.hover,
      curve: grid.AppMotion.curve,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: live ? SharePalette.fieldFillHover : SharePalette.fieldFill,
        border: Border.all(
          color: focused
              ? SharePalette.fieldRimFocus
              : hovered && enabled
              ? SharePalette.fieldRimHover
              : SharePalette.fieldRim,
        ),
        borderRadius: BorderRadius.circular(ShareMetrics.fieldRadius),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: SharePalette.fieldRingFocus,
                  blurRadius: 0,
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
      alignment: Alignment.centerLeft,
      child: child,
    );
    final opaque = enabled
        ? decorated
        : Opacity(opacity: 0.55, child: decorated);
    if (onTap == null || !enabled) return opaque;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: opaque),
    );
  }
}

/// A plain typed value: a name to advertise, this computer's name, an address.
///
/// ⚠️ `filled: false` and `isCollapsed: true` are load-bearing, not tidying.
/// The app's global [InputDecorationTheme] sets `filled: true` with the app's
/// own surface and a `minHeight` sized for a 32px control — so every field on
/// this page was drawing a second, lighter box behind its text, in the app's
/// warm grey, floating inside this page's cooler one. It is visible in any
/// screenshot of the pane taken before this comment existed. A field that
/// brings its own skin has to switch Material's off.
class ShareTextField extends StatefulWidget {
  const ShareTextField({
    super.key,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.leading,
    this.trailing,
  });

  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// A glyph before the text that says what the field is for — the magnifier on
  /// a search box. Decoration, not a control: it takes no press.
  final IconData? leading;

  /// A glyph inside the box, on the text's own line — the eye that reveals a
  /// key. Never a second tap target stacked on top of the field.
  final Widget? trailing;

  @override
  State<ShareTextField> createState() => _ShareTextFieldState();
}

class _ShareTextFieldState extends State<ShareTextField> {
  final _focus = FocusNode();
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.text
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: ShareFieldSkin(
        hovered: _hovered,
        focused: _focus.hasFocus,
        enabled: widget.enabled,
        child: Row(
          children: [
            if (widget.leading != null) ...[
              Icon(widget.leading, size: 15, color: SharePalette.eyebrow),
              const SizedBox(width: 9),
            ],
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                enabled: widget.enabled,
                obscureText: widget.obscure,
                onChanged: widget.onChanged,
                onSubmitted: widget.onSubmitted,
                style: ShareType.fieldValue,
                cursorColor: SharePalette.accent,
                cursorWidth: 1.5,
                decoration: InputDecoration(
                  // See the class comment: the app's theme fills and pads a
                  // field for a control this page does not draw.
                  filled: false,
                  fillColor: Colors.transparent,
                  isCollapsed: true,
                  constraints: const BoxConstraints(),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: widget.hint,
                  hintStyle: ShareType.fieldPlaceholder,
                ),
              ),
            ),
            if (widget.trailing != null) ...[
              const SizedBox(width: 6),
              widget.trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A press that is only a glyph — the eye that reveals a key, the × that closes
/// the model manager, the bin beside a model on disk.
///
/// Not an [IconButton]: that one brings a 40px tap target and a ripple, which
/// inside a 38px field either overflows it or forces the field taller than
/// every other control on the page, and in a dialog header pushes the title off
/// its own baseline. Sized to the glyph, hover on the glyph.
class ShareGlyphButton extends StatefulWidget {
  const ShareGlyphButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 15,
    this.danger = false,
  });

  final IconData icon;

  /// Null draws the glyph dimmed and refuses the press.
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  /// Turns red under the pointer — for the press that destroys something.
  final bool danger;

  @override
  State<ShareGlyphButton> createState() => _ShareGlyphButtonState();
}

class _ShareGlyphButtonState extends State<ShareGlyphButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final enabled = widget.onPressed != null;
    final button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: widget.size + 11,
          height: widget.size + 11,
          child: Icon(
            widget.icon,
            size: widget.size,
            color: !enabled
                ? SharePalette.dim
                : _hovered
                ? (widget.danger ? SharePalette.danger : SharePalette.ink)
                : SharePalette.eyebrow,
          ),
        ),
      ),
    );
    return widget.tooltip == null
        ? button
        : Tooltip(message: widget.tooltip!, child: button);
  }
}

/// One choice out of a list, with an optional chip beside the value — a model's
/// size on disk, a provider's name.
///
/// Built on [MenuAnchor] for the same reason [AppSelectField] is: Material's
/// `DropdownButton` anchors its popup over the field, forces the panel to the
/// field's width, and ignores both `menuTheme` and `popupMenuTheme`, so it
/// cannot be made to match anything else here. The panel follows the app's own
/// menu recipe — rows with a reserved tick slot, a hover pill, a wash on the
/// current choice — in this page's palette.
class ShareSelect extends StatefulWidget {
  const ShareSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onSelected,
    this.placeholder = 'Choose one',
    this.badge,
    this.enabled = true,
  });

  /// What is selected, or null for nothing yet.
  final String? value;

  /// The rows, each a value and the chip that goes with it.
  final List<ShareOption> options;
  final ValueChanged<String> onSelected;
  final String placeholder;

  /// The chip drawn on the closed field. Separate from [options] so a caller
  /// can show something the list does not carry.
  final String? badge;
  final bool enabled;

  @override
  State<ShareSelect> createState() => _ShareSelectState();
}

class _ShareSelectState extends State<ShareSelect> {
  final _controller = MenuController();
  bool _hovered = false;

  bool get _usable => widget.enabled && widget.options.isNotEmpty;

  /// Tall enough for the list, capped so a long one scrolls rather than running
  /// off the window.
  double get _panelHeight => math.min(
    widget.options.length * ShareMetrics.menuRowExtent +
        ShareMetrics.menuPadding.vertical,
    ShareMetrics.menuMaxHeight,
  );

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    // The panel is measured against the FIELD: a menu narrower than the control
    // it drops out of reads as an unrelated box that opened nearby.
    return LayoutBuilder(
      builder: (context, constraints) =>
          _anchor(constraints.maxWidth.isFinite ? constraints.maxWidth : null),
    );
  }

  Widget _anchor(double? fieldWidth) {
    final selected = widget.value;
    return MenuAnchor(
      controller: _controller,
      alignmentOffset: const Offset(0, 5),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(SharePalette.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(10),
        shadowColor: WidgetStatePropertyAll(
          Colors.black.withValues(alpha: 0.28),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ShareMetrics.cardRadius),
            side: BorderSide(color: SharePalette.rim),
          ),
        ),
        padding: WidgetStatePropertyAll(ShareMetrics.menuPadding),
        maximumSize: WidgetStatePropertyAll(
          Size(double.infinity, _panelHeight),
        ),
      ),
      menuChildren: [
        for (final option in widget.options)
          SizedBox(
            width: math.max(fieldWidth ?? 0, ShareMetrics.menuMinWidth),
            child: _OptionRow(
              option: option,
              selected: option.value == selected,
              onPressed: () {
                _controller.close();
                widget.onSelected(option.value);
              },
            ),
          ),
      ],
      builder: (context, controller, _) => MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: ShareFieldSkin(
          enabled: _usable,
          hovered: _hovered,
          focused: controller.isOpen,
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selected ?? widget.placeholder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: selected == null
                      ? ShareType.fieldPlaceholder
                      : ShareType.fieldValue,
                ),
              ),
              if (widget.badge != null) ...[
                const SizedBox(width: 8),
                ShareBadge(widget.badge!),
              ],
              const SizedBox(width: 8),
              Icon(
                LucideIcons.chevronDown300,
                size: 15,
                color: _hovered || controller.isOpen
                    ? SharePalette.ink
                    : SharePalette.eyebrow,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row of a [ShareSelect].
class ShareOption {
  const ShareOption(this.value, {this.badge, this.note});

  final String value;
  final String? badge;

  /// A second line under the value, for something the value cannot say — that
  /// a split model is missing a shard, say.
  final String? note;
}

class _OptionRow extends StatefulWidget {
  const _OptionRow({
    required this.option,
    required this.selected,
    required this.onPressed,
  });

  final ShareOption option;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_OptionRow> createState() => _OptionRowState();
}

class _OptionRowState extends State<_OptionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final option = widget.option;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            constraints: BoxConstraints(
              minHeight: option.note == null
                  ? ShareMetrics.menuRowExtent
                  : ShareMetrics.menuRowExtent + 12,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: widget.selected
                  ? SharePalette.selectedFill
                  : _hovered
                  ? SharePalette.hoverFill
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(ShareMetrics.menuRowRadius),
            ),
            child: Row(
              children: [
                // The tick's slot is reserved on every row, so a label does not
                // shift sideways when it becomes the choice — and an unpicked
                // row keeps an EMPTY slot rather than an outlined box, which
                // would turn a pick-one list into what reads as checkboxes.
                SizedBox(
                  width: 20,
                  child: widget.selected
                      ? Icon(
                          LucideIcons.check300,
                          size: 13,
                          color: SharePalette.accent,
                        )
                      : null,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        option.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ShareType.menuRow.copyWith(
                          fontWeight: widget.selected
                              ? grid.AppFont.semibold
                              : FontWeight.w400,
                        ),
                      ),
                      if (option.note != null) ...[
                        const SizedBox(height: 2),
                        Text(option.note!, style: ShareType.note),
                      ],
                    ],
                  ),
                ),
                if (option.badge != null) ...[
                  const SizedBox(width: 10),
                  ShareBadge(option.badge!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A model this key is, or is not, offering to the grid.
///
/// The state is a **box**, not a tint. The version before this wrote it into
/// the label — `gpt-5.5 · on` — which was right about the problem and wrong
/// about the fix: the words were the same length either way, so a row of four
/// still had to be read one at a time.
///
/// The box is an outline with a tick in it, not a filled green square. Four
/// filled squares on one line is a row of traffic lights on a page whose whole
/// palette is two greys and a blue, and green here means *live on the grid* —
/// which these are not, until the share starts.
class ShareToggleChip extends StatefulWidget {
  const ShareToggleChip({
    super.key,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  State<ShareToggleChip> createState() => _ShareToggleChipState();
}

class _ShareToggleChipState extends State<ShareToggleChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final on = widget.on;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Semantics(
          button: true,
          selected: on,
          label: '${widget.label} · ${on ? 'on' : 'off'}',
          child: AnimatedContainer(
            duration: grid.AppMotion.hover,
            curve: grid.AppMotion.curve,
            height: ShareMetrics.controlHeightSmall,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: on
                  ? (_hovered
                        ? SharePalette.fieldFillHover
                        : SharePalette.fieldFill)
                  : (_hovered ? SharePalette.hoverFill : Colors.transparent),
              border: Border.all(
                color: _hovered
                    ? SharePalette.fieldRimHover
                    : on
                    ? SharePalette.fieldRim
                    : SharePalette.rim,
              ),
              borderRadius: BorderRadius.circular(ShareMetrics.menuRowRadius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 13,
                  height: 13,
                  child: on
                      ? Icon(
                          LucideIcons.check300,
                          size: 13,
                          color: SharePalette.accent,
                        )
                      : DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: SharePalette.fieldRim),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: on ? grid.AppFont.semibold : FontWeight.w400,
                    color: on ? SharePalette.ink : SharePalette.dim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One answer in a list of them, as a radio.
///
/// Its own widget rather than Material's: `Radio` draws a 40px tap target with
/// a ripple, in the app's accent, and sits a whole control's worth taller than
/// the line of text it belongs to.
class ShareRadio extends StatelessWidget {
  const ShareRadio({super.key, required this.selected, this.hovered = false});

  final bool selected;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return AnimatedContainer(
      duration: grid.AppMotion.hover,
      curve: grid.AppMotion.curve,
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? Colors.transparent : SharePalette.fieldFill,
        border: Border.all(
          color: selected
              ? SharePalette.accent
              : hovered
              ? SharePalette.fieldRimHover
              : SharePalette.fieldRim,
          width: selected ? 5 : 1.5,
        ),
      ),
    );
  }
}

/// A quiet chip: a model's size, a context window's value.
class ShareBadge extends StatelessWidget {
  const ShareBadge(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: SharePalette.badgeFill,
        borderRadius: BorderRadius.circular(ShareMetrics.badgeRadius),
      ),
      child: Text(text, style: ShareType.badge),
    );
  }
}
