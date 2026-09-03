import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/share_page_theme.dart';

/// The controls the share page's forms are built from.
///
/// The design's field is a visible 1px rim at radius 9 on a light fill, where
/// this app's own idiom is a borderless capsule. Rather than hand every form
/// the same six arguments, the shape lives here once — so the model picker, both
/// name boxes and the endpoint field cannot drift apart by a pixel.
class ShareField extends StatelessWidget {
  const ShareField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: ShareType.fieldLabel),
        const SizedBox(height: 7),
        child,
      ],
    );
  }
}

/// The rim, fill and radius every control on the page sits in.
class ShareFieldSkin extends StatelessWidget {
  const ShareFieldSkin({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final decorated = Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: SharePalette.fieldFill,
        border: Border.all(color: SharePalette.fieldRim),
        borderRadius: BorderRadius.circular(ShareMetrics.fieldRadius),
      ),
      alignment: Alignment.centerLeft,
      child: child,
    );
    if (onTap == null) return decorated;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: decorated),
    );
  }
}

/// A plain typed value: a name to advertise, this computer's name, an address.
class ShareTextField extends StatelessWidget {
  const ShareTextField({
    super.key,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ShareFieldSkin(
      child: TextField(
        controller: controller,
        obscureText: obscure,
        onSubmitted: onSubmitted,
        style: TextStyle(fontSize: 13.5, color: SharePalette.ink),
        cursorColor: SharePalette.accent,
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          hintText: hint,
          hintStyle: TextStyle(fontSize: 13.5, color: SharePalette.helper),
        ),
      ),
    );
  }
}

/// One choice out of a list, with an optional chip beside the value — a model's
/// size on disk, a provider's name.
class ShareSelect extends StatelessWidget {
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
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final selected = value;
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(SharePalette.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ShareMetrics.cardRadius),
            side: BorderSide(color: SharePalette.rim),
          ),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
      ),
      menuChildren: [
        for (final option in options)
          _OptionRow(
            option: option,
            selected: option.value == selected,
            onPressed: () => onSelected(option.value),
          ),
      ],
      builder: (context, controller, _) => ShareFieldSkin(
        onTap: !enabled || options.isEmpty
            ? null
            : (controller.isOpen ? controller.close : controller.open),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected ?? placeholder,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  color: selected == null
                      ? SharePalette.helper
                      : SharePalette.ink,
                ),
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              ShareBadge(badge!),
            ],
            const SizedBox(width: 6),
            Icon(
              LucideIcons.chevronDown300,
              size: 15,
              color: SharePalette.eyebrow,
            ),
          ],
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

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.selected,
    required this.onPressed,
  });

  final ShareOption option;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return MenuItemButton(
      onPressed: onPressed,
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        overlayColor: WidgetStatePropertyAll(SharePalette.badgeFill),
      ),
      child: SizedBox(
        width: 340,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    option.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected
                          ? grid.AppFont.semibold
                          : FontWeight.w400,
                      color: SharePalette.ink,
                    ),
                  ),
                  if (option.note != null)
                    Text(option.note!, style: ShareType.note),
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
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: grid.AppFont.semibold,
          color: SharePalette.labelInk,
        ),
      ),
    );
  }
}
