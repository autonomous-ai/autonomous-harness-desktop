import 'package:flutter/material.dart';

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
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: SharePalette.accent,
            inactiveTrackColor: SharePalette.track,
            thumbColor: Colors.white,
            overlayColor: SharePalette.accentRing,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 8,
              elevation: 2,
            ),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            trackShape: const RoundedRectSliderTrackShape(),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${formatContextLength(minContextTokens)} · lightest',
              style: ShareType.eyebrow.copyWith(letterSpacing: 0),
            ),
            if (ceiling != null)
              Text(
                '${formatContextLength(ceiling)} · heaviest',
                style: ShareType.eyebrow.copyWith(letterSpacing: 0),
              ),
          ],
        ),
      ],
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
        FilledButton.icon(
          onPressed: busy ? null : onPressed,
          icon: busy
              ? const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.play_arrow_rounded, size: 18),
          label: Text(busy ? 'Starting…' : label),
          style: FilledButton.styleFrom(
            backgroundColor: SharePalette.accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: SharePalette.accent.withValues(alpha: 0.4),
            disabledForegroundColor: Colors.white70,
            minimumSize: const Size(0, ShareMetrics.buttonHeight),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ShareMetrics.fieldRadius),
            ),
            textStyle: TextStyle(
              fontSize: 13.5,
              fontWeight: grid.AppFont.semibold,
            ),
          ),
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
