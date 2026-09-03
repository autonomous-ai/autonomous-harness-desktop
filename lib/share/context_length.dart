/// The "Memory for context" setting, in tokens.
///
/// Copied value-for-value from Grid's `core/context_length.dart` so the same
/// slider in two apps snaps to the same numbers and labels them the same way.
/// Keep the two in step.
library;

/// Below 4k a model can barely hold a conversation, so this is the floor.
const int minContextTokens = 4096;

/// The slider snaps to 1k, so a dragged value is always a clean "…k" rather
/// than an odd number nobody can read back.
const int _contextStep = 1024;

/// 200k, or the model's maximum when it supports less. The balance between how
/// much of a conversation the model keeps in mind and the memory that costs.
const int _defaultContextTarget = 200 * _contextStep;

int defaultContextLength(int maxContext) =>
    maxContext < _defaultContextTarget ? maxContext : _defaultContextTarget;

/// Snap a raw mid-drag token count to the nearest 1k, inside the floor and
/// [maxContext]. Lets the slider move smoothly while every value it reports
/// lands on a step — including one between the powers of two, like 200k.
int snapContextLength(int tokens, int maxContext) {
  final snapped = (tokens / _contextStep).round() * _contextStep;
  return snapped.clamp(minContextTokens, maxContext);
}

/// 4096 -> `4k`, 204800 -> `200k`, 1048576 -> `1M`.
///
/// A megabyte-scale window switches unit rather than reading "1024k", which is
/// a number the reader has to convert before they can compare it with the "1M"
/// their own engine's flags are written in.
String formatContextLength(int tokens) {
  const perM = 1024 * 1024;
  if (tokens < perM) return '${(tokens / 1024).round()}k';
  final millions = tokens / perM;
  final label = millions == millions.roundToDouble()
      ? '${millions.round()}'
      : millions.toStringAsFixed(1);
  return '${label}M';
}
