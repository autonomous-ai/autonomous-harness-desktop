import 'usage_window.dart';

/// How close a rate-limit window is to being spent.
///
/// Two thresholds, one meaning each. [warn] is the point the app changes
/// *colour* at — the reader is looking at the figure anyway, and a hue costs
/// them nothing. [critical] is the point the app is willing to speak
/// *unprompted*, which is a far more expensive thing to do and so is a far
/// higher bar. A third shade between them would be one nobody could name.
enum UsagePressure {
  calm,

  /// Amber. The window is worth noticing on the way past.
  warn,

  /// Red, and worth offering a way out of — see `usageAlerts`.
  critical,
}

/// Where a window starts reading amber.
///
/// The figure beside it is already exact, so this number is not carrying the
/// quantity — it is carrying the moment the quantity starts to matter.
const double kUsageWarnPercent = 80;

/// Where the app is willing to say something the reader did not ask for.
const double kUsageCriticalPercent = 90;

/// How long a dismissal lasts when the vendor never said when the window
/// resets.
///
/// Long enough not to nag, short enough that a silence can never become
/// permanent — the one failure mode a dismissal with no expiry has.
const Duration kUsageDismissGrace = Duration(hours: 6);

UsagePressure usagePressureOf(double usedPercent) {
  if (usedPercent >= kUsageCriticalPercent) return UsagePressure.critical;
  if (usedPercent >= kUsageWarnPercent) return UsagePressure.warn;
  return UsagePressure.calm;
}

extension UsageWindowPressure on UsageWindow {
  UsagePressure get pressure => usagePressureOf(usedPercent);
}

/// One window that has crossed [kUsageCriticalPercent], and the account it
/// belongs to.
class UsageAlert {
  const UsageAlert({required this.provider, required this.window});

  final UsageProvider provider;
  final UsageWindow window;

  /// How a dismissal names this alert.
  ///
  /// ⚠️ Deliberately WITHOUT the reset time. Both vendors recompute their reset
  /// field on every answer, so a key that carried it would change under a poll
  /// that runs once a minute — the dismissal would then belong to a window that
  /// no longer exists by that name and the strip would come straight back, one
  /// minute after being closed. What separates one cycle from the next is the
  /// dismissal's own EXPIRY instead: see [dismissedUntil].
  String get key => '${provider.name}|${window.label}';

  /// When a dismissal of this alert should lapse: the moment the window it was
  /// about starts over.
  DateTime dismissedUntil({DateTime? now}) =>
      window.resetsAt ?? (now ?? DateTime.now()).add(kUsageDismissGrace);
}

/// Every window worth interrupting for, the most spent first.
///
/// A list rather than the single tightest window, because the caller filters it
/// against what has already been dismissed: with one account's session window
/// closed for this cycle, the other account's weekly window is still worth
/// saying — and a function that had already picked the tightest would have
/// thrown it away.
List<UsageAlert> usageAlerts(List<ProviderUsage> readings) {
  final alerts = <UsageAlert>[
    for (final reading in readings)
      if (reading.hasFigures)
        for (final window in reading.windows)
          if (window.pressure == UsagePressure.critical)
            UsageAlert(provider: reading.provider, window: window),
  ];
  alerts.sort((a, b) => b.window.usedPercent.compareTo(a.window.usedPercent));
  return alerts;
}
