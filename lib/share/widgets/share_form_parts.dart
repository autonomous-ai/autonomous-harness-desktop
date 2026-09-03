import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/share_page_theme.dart';
import '../context_length.dart';
import 'share_fields.dart';

/// The card a form's fields sit on.
class SharePlate extends StatelessWidget {
  const SharePlate({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Container(
      padding: ShareMetrics.plateSection,
      decoration: BoxDecoration(
        color: SharePalette.surface,
        border: Border.all(color: SharePalette.rim),
        borderRadius: BorderRadius.circular(ShareMetrics.plateRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// "Memory for context": the name and the value on one row, the slider under
/// it, and what each end of it means.
///
/// A slider rather than a dropdown because the question is "how much would you
/// like", which is a quantity — and the two ends are named in what they cost
/// rather than in tokens, because "256k" tells nobody how much memory they are
/// about to spend.
class ContextSlider extends StatelessWidget {
  const ContextSlider({
    super.key,
    required this.max,
    required this.value,
    required this.onChanged,
  });

  /// The model's own ceiling. Null while it is still being read — the slider is
  /// then drawn inert rather than on a guessed maximum that would snap the
  /// reader's choice a moment after they made it.
  final int? max;
  final int? value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final ceiling = max;
    final current = value;
    final ready = ceiling != null && current != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Memory for context', style: ShareType.fieldLabel),
            ),
            if (ready) ShareBadge('${formatContextLength(current)} tokens'),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          'How much of a conversation the model can hold in mind. More '
          'context, more RAM.',
          style: ShareType.note,
        ),
        // Padding of its own, because Material's Slider reserves a 24px touch
        // slab above and below its track and then centres in it — which set
        // this control 20px away from the label that names it while looking, in
        // the widget tree, like it was 8.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: SharePalette.accent,
              inactiveTrackColor: SharePalette.track,
              // NOT `Colors.white`, which is a white dot on a white track in
              // light mode. The thumb is a raised surface, so it takes the
              // page's raised surface.
              thumbColor: SharePalette.surface,
              disabledThumbColor: SharePalette.surface,
              disabledActiveTrackColor: SharePalette.track,
              disabledInactiveTrackColor: SharePalette.track,
              overlayColor: SharePalette.accentRing,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 8,
                disabledThumbRadius: 8,
                elevation: 2,
              ),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
              trackShape: const RoundedRectSliderTrackShape(),
              padding: EdgeInsets.zero,
            ),
            child: Slider(
              min: minContextTokens.toDouble(),
              max: (ceiling ?? minContextTokens * 2).toDouble(),
              value: ready
                  ? current.clamp(minContextTokens, ceiling).toDouble()
                  : minContextTokens.toDouble(),
              onChanged: ready
                  ? (raw) => onChanged(snapContextLength(raw.round(), ceiling))
                  : null,
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${formatContextLength(minContextTokens)} · lightest',
              style: ShareType.scaleEnd,
            ),
            if (ceiling != null)
              Text(
                '${formatContextLength(ceiling)} · heaviest',
                style: ShareType.scaleEnd,
              ),
          ],
        ),
      ],
    );
  }
}

/// How much weight a button carries.
enum ShareButtonKind {
  /// The one thing to press. At most one per step.
  primary,

  /// Everything else that is still a button rather than a link.
  secondary,
}

/// Every button on this page.
///
/// There were five before this, each with its own `styleFrom` — 34 and 36 and
/// 38 tall, 13 and 13.5pt, Material's `play_arrow_rounded` beside Lucide
/// glyphs everywhere else, and a disabled primary drawn as the accent at 40%
/// opacity, which on a dark ground reads as a muddy blue rectangle rather than
/// as a button that is off.
///
/// A secondary is a real [OutlinedButton] and a primary a real [FilledButton],
/// because the semantics and the focus behaviour are worth keeping — only the
/// skin is ours.
class ShareButton extends StatelessWidget {
  const ShareButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = ShareButtonKind.primary,
    this.icon,
    this.busy = false,
    this.small = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final ShareButtonKind kind;
  final IconData? icon;

  /// Shows a spinner in the glyph's place and refuses the press. The label is
  /// the caller's to change — "Starting…" says more than a spinner alone.
  final bool busy;
  final bool small;

  double get _height =>
      small ? ShareMetrics.controlHeightSmall : ShareMetrics.controlHeight;

  double get _glyph => small ? 13 : 15;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final primary = kind == ShareButtonKind.primary;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy)
          SizedBox(
            width: _glyph,
            height: _glyph,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: primary ? Colors.white : SharePalette.ink,
            ),
          )
        else if (icon != null)
          Icon(icon, size: _glyph),
        if (busy || icon != null) const SizedBox(width: 8),
        Text(label),
      ],
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(
        small ? ShareMetrics.menuRowRadius : ShareMetrics.fieldRadius,
      ),
    );
    final padding = EdgeInsets.symmetric(horizontal: small ? 12 : 18);
    final press = busy ? null : onPressed;
    if (!primary) {
      return OutlinedButton(
        onPressed: press,
        style: OutlinedButton.styleFrom(
          foregroundColor: SharePalette.ink,
          disabledForegroundColor: SharePalette.dim,
          side: BorderSide(color: SharePalette.fieldRim),
          backgroundColor: Colors.transparent,
          minimumSize: Size(0, _height),
          fixedSize: Size.fromHeight(_height),
          padding: padding,
          shape: shape,
          textStyle: ShareType.button,
        ),
        child: child,
      );
    }
    return FilledButton(
      onPressed: press,
      style: FilledButton.styleFrom(
        backgroundColor: SharePalette.accent,
        foregroundColor: Colors.white,
        // A button that is off is a flat, quiet surface — not the accent turned
        // down, which keeps reading as "press me" through the fade.
        disabledBackgroundColor: SharePalette.badgeFill,
        disabledForegroundColor: SharePalette.dim,
        minimumSize: Size(0, _height),
        fixedSize: Size.fromHeight(_height),
        padding: padding,
        shape: shape,
        textStyle: ShareType.button,
      ),
      child: child,
    );
  }
}

/// The button that finishes the job, and the quiet line beside it.
class StartRow extends StatelessWidget {
  const StartRow({
    super.key,
    required this.label,
    required this.note,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final String note;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Row(
      children: [
        ShareButton(
          label: busy ? 'Starting…' : label,
          icon: LucideIcons.play300,
          busy: busy,
          onPressed: onPressed,
        ),
        const SizedBox(width: ShareMetrics.buttonGap),
        Flexible(child: Text(note, style: ShareType.buttonHelper)),
      ],
    );
  }
}

/// What went wrong, said where the thing that went wrong was asked for.
class ShareErrorNote extends StatelessWidget {
  const ShareErrorNote({super.key, required this.message, this.onDismiss});

  final String message;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 9, 11),
      decoration: BoxDecoration(
        color: SharePalette.dangerSoft,
        borderRadius: BorderRadius.circular(ShareMetrics.statusRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              message,
              style: ShareType.note.copyWith(color: SharePalette.danger),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, size: 15),
              color: SharePalette.danger,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 24, height: 24),
              splashRadius: 14,
            ),
        ],
      ),
    );
  }
}
