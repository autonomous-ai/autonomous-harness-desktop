/// What an agent account has spent of its rate limits, and when that resets.
///
/// The vendors answer in different shapes — Claude names its windows, Codex
/// numbers them — so both are mapped onto this one model before anything draws
/// them. A rail that had to know which provider it was printing would grow a
/// branch per provider in every widget.
library;

/// Which account a reading belongs to.
///
/// Only the two whose usage endpoints are known. The other five grid-capable
/// engines (copilot, grok, hermes, opencode, pi) publish nothing comparable, so
/// they are absent rather than listed as perpetually unavailable — a row that
/// can only ever say "unsupported" is a row that costs a glance and returns
/// nothing.
enum UsageProvider {
  claude('Claude'),
  codex('Codex');

  const UsageProvider(this.label);

  /// How the provider is named on screen.
  final String label;

  /// The engine id this account's agents run under, which is also how
  /// `EngineMark` finds the logo the machine rail already draws beside every
  /// agent. The enum's own name is that id — spelled the same on purpose, so
  /// there is no second mapping to keep in step.
  String get engineId => name;
}

/// Why a provider's figures are, or are not, on screen.
///
/// [signedOut] is deliberately kept apart from [failed]: signing in fixes the
/// first and retrying fixes the second, and offering a Retry for a missing
/// session fails identically forever. The same split Grid draws between
/// `GridNetworksSignedOut` and `GridNetworksFailed`.
enum UsageStatus { loading, ok, signedOut, failed }

/// One rate-limit window: how much of it is spent, and when it starts over.
class UsageWindow {
  const UsageWindow({
    required this.label,
    required this.usedPercent,
    this.resetsAt,
  });

  /// What the window is called on screen — `Session`, `Weekly`, `Fable`.
  final String label;

  /// How much of the window is spent, 0–100.
  final double usedPercent;

  /// When it starts over, or null when the vendor did not say.
  ///
  /// **Null is not zero here.** A window with no reset time prints no
  /// countdown; printing "resets in 0m" for an answer we never got would be a
  /// measurement invented out of a silence.
  final DateTime? resetsAt;

  /// The countdown as the rail prints it — `4h 34m`, `5d 11h`, `43m` — or null
  /// when there is no reset time or it has already passed.
  ///
  /// Minute granularity on purpose: the poll behind this runs once a minute, so
  /// a seconds figure would be wrong for most of its life and would need a
  /// second timer to stop being wrong.
  String? resetsInLabel({DateTime? now}) {
    final at = resetsAt;
    if (at == null) return null;
    final left = at.difference(now ?? DateTime.now());
    if (left.isNegative || left.inMinutes < 1) return null;
    if (left.inHours < 1) return '${left.inMinutes}m';
    if (left.inDays < 1) {
      return '${left.inHours}h ${left.inMinutes % 60}m';
    }
    return '${left.inDays}d ${left.inHours % 24}h';
  }
}

/// One account's reading: every window it reports, or why there is none.
class ProviderUsage {
  const ProviderUsage({
    required this.provider,
    required this.status,
    this.windows = const [],
    this.message,
    this.fetchedAt,
  });

  /// The state a provider is in before it has ever answered.
  const ProviderUsage.loading(this.provider)
    : status = UsageStatus.loading,
      windows = const [],
      message = null,
      fetchedAt = null;

  final UsageProvider provider;
  final UsageStatus status;

  /// Every window this account reports, in the order it should be read:
  /// shortest window first, because that is the one about to bite.
  final List<UsageWindow> windows;

  /// Why there are no figures. Set for [UsageStatus.signedOut] and
  /// [UsageStatus.failed], null otherwise.
  final String? message;

  /// When these figures were read. Null until the first answer lands.
  final DateTime? fetchedAt;

  bool get hasFigures => status == UsageStatus.ok && windows.isNotEmpty;

  /// The window the rail prints when it has room for only one: the one closest
  /// to being spent, since that is the limit that will actually stop the work.
  UsageWindow? get tightest {
    if (windows.isEmpty) return null;
    return windows.reduce((a, b) => b.usedPercent > a.usedPercent ? b : a);
  }
}

/// Reads a vendor's reset timestamp, which arrives as an ISO string, epoch
/// seconds, or epoch milliseconds depending on the vendor and the field.
///
/// 1e10 is the discriminator: it sits above any plausible seconds epoch (year
/// 2286) and below any plausible milliseconds one (year 2001), so the unit can
/// be told from the magnitude without the vendor having to label it.
DateTime? parseResetTimestamp(Object? value) {
  if (value is num) {
    if (!value.isFinite) return null;
    final ms = value > 10000000000 ? value : value * 1000;
    return DateTime.fromMillisecondsSinceEpoch(ms.round());
  }
  if (value is! String || value.trim().isEmpty) return null;
  final numeric = num.tryParse(value.trim());
  if (numeric != null) return parseResetTimestamp(numeric);
  return DateTime.tryParse(value);
}

/// Reads a vendor's utilization figure, clamped to the 0–100 the UI draws.
///
/// The vendors disagree on the field name, so the caller passes each candidate
/// in turn; the first that is actually a number wins.
double? parseUsedPercent(List<Object?> candidates) {
  for (final candidate in candidates) {
    final value = candidate is num
        ? candidate.toDouble()
        : double.tryParse('$candidate');
    if (value != null && value.isFinite) return value.clamp(0, 100).toDouble();
  }
  return null;
}
