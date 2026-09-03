import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/share_page_theme.dart';
import '../context_length.dart';
import '../model_pull.dart';
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

/// The models this computer could download, and the one it is downloading.
///
/// Inline rather than a manager screen: on the machine that needs it there is
/// usually exactly one row, because `grid catalog` answers with what this
/// hardware can actually run rather than with everything that exists.
class DownloadBlock extends StatelessWidget {
  const DownloadBlock({
    super.key,
    required this.pull,
    required this.onDownload,
  });

  final ModelPullController pull;
  final ValueChanged<String> onDownload;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ListenableBuilder(
      listenable: pull,
      builder: (context, _) {
        final busy = pull.pulling;
        if (busy != null) return _Progress(pull: pull, label: busy);
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (pull.error != null) ...[
                ShareErrorNote(message: pull.error!),
                const SizedBox(height: 10),
              ],
              if (pull.catalog.isEmpty)
                Text(
                  'Nothing left to download — this computer already has every '
                  'model the catalogue recommends for it.',
                  style: ShareType.note,
                )
              else
                for (final model in pull.catalog)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(model.file, style: ShareType.cardTitle),
                              if (model.minVramGb > 0)
                                Text(
                                  'Wants ${model.minVramGb} GB of memory',
                                  style: ShareType.note,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: () => onDownload(model.label),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: SharePalette.accent,
                            side: BorderSide(color: SharePalette.fieldRim),
                            minimumSize: const Size(0, 32),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                ShareMetrics.fieldRadius,
                              ),
                            ),
                          ),
                          child: const Text('Download'),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.pull, required this.label});

  final ModelPullController pull;
  final String label;

  @override
  Widget build(BuildContext context) {
    final progress = pull.progress;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: ShareType.cardTitle)),
              if (progress != null) ShareBadge(progress.label),
              const SizedBox(width: 8),
              TextButton(
                onPressed: pull.cancel,
                style: TextButton.styleFrom(
                  foregroundColor: SharePalette.helper,
                  minimumSize: const Size(0, 26),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('Cancel'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              minHeight: 5,
              value: progress == null || progress.isIndeterminate
                  ? null
                  : progress.percent! / 100,
              backgroundColor: SharePalette.track,
              color: SharePalette.accent,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            // Not "you can leave this page": the download is a child of this
            // window and closing it stops the transfer. What it does not lose
            // is the bytes — the CLI keeps a `.part` file and asks for the rest
            // with a Range header next time (shared/models/download.py).
            'Downloading. Closing this page stops it; what has landed is kept, '
            'and a second attempt picks up where it left off.',
            style: ShareType.note,
          ),
        ],
      ),
    );
  }
}
