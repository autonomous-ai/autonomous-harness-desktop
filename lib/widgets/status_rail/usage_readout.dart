import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/widgets/skeleton.dart';
import '../../usage/usage_accounts.dart';
import '../../usage/usage_pressure.dart';
import '../../usage/usage_window.dart';
import '../engine_identity.dart';
import 'rail_figure.dart';
import 'usage_ink.dart';

/// What the agent accounts on this machine have spent, along the status rail.
///
/// Stands where the grid figures stand, and appears exactly when they cannot:
/// with no grid chosen the strip used to read "No grid chosen", which is a
/// sentence that tells someone what they already know and gives them nothing.
/// These figures are true whether or not a grid is picked, because a rate limit
/// belongs to an *account*, not to a grid.
///
/// Generic over what a figure opens so it can hand the rail back its own panel
/// kind without that enum having to leave the rail.
class UsageReadout<T> extends StatelessWidget {
  const UsageReadout({
    super.key,
    required this.accounts,
    required this.loading,
    required this.anchorFor,
    required this.kindFor,
    required this.onEnter,
    required this.onExit,
  });

  /// One per ACCOUNT, this computer's first — see `groupUsageAccounts`. A
  /// remote machine on this same subscription is folded into this computer's
  /// figure; one on a different subscription is a figure of its own.
  final List<UsageAccount> accounts;

  /// The first cycle has not landed yet and nothing has ever been shown.
  final bool loading;

  final RailFigureAnchor Function(UsageProvider) anchorFor;
  final T Function(UsageProvider) kindFor;
  final void Function(T) onEnter;
  final void Function(T) onExit;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    // Blank at the size of the answer, so the strip does not assemble itself
    // one account at a time. Only before the first reading: once figures exist
    // they stay through every refresh.
    if (loading) {
      return const Align(
        alignment: Alignment.centerRight,
        child: _UsageSkeleton(),
      );
    }
    // One hover target per PROVIDER, holding a figure for each of its
    // accounts. The rail's panels are keyed by provider, and one Claude panel
    // that lists two accounts reads better than two Claude panels fighting over
    // one anchor.
    final byProvider = <UsageProvider, List<UsageAccount>>{};
    for (final account in accounts) {
      // An account nobody signed into is left out rather than printed as a row
      // of blanks: the rail is for figures, and the reason there are none
      // belongs in the panel, where there is room to say it.
      if (!account.reading.hasFigures) continue;
      byProvider.putIfAbsent(account.provider, () => []).add(account);
    }
    if (byProvider.isEmpty) return const SizedBox.shrink();
    // Right, at the strip's far end. These figures are the one thing on it
    // that is nobody's *setting* — the pill at the other end is what you
    // press, and furniture you only read belongs at the edge you are not
    // reaching for.
    return Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final MapEntry(key: provider, value: shown)
              in byProvider.entries)
            RailHoverTarget<T>(
              kind: kindFor(provider),
              anchor: anchorFor(provider),
              semantics: _semantics(provider, shown),
              onEnter: onEnter,
              onExit: onExit,
              child: _ProviderFigures(provider: provider, accounts: shown),
            ),
        ],
      ),
    );
  }

  static String _semantics(UsageProvider provider, List<UsageAccount> shown) {
    final figures = [
      for (final account in shown)
        '${account.reading.railWindow?.usedPercent.round() ?? 0} percent used'
            '${account.isLocal ? '' : ' on ${account.machines.join(', ')}'}',
    ];
    return '${provider.label} usage, ${figures.join('; ')}';
  }
}

/// One provider's accounts, as the strip prints them: its mark once, then a
/// figure per account.
class _ProviderFigures extends StatelessWidget {
  const _ProviderFigures({required this.provider, required this.accounts});

  final UsageProvider provider;
  final List<UsageAccount> accounts;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: grid.AppPalette.textSecondary,
      fontSize: 11.5,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        EngineMark(engine: provider.engineId, size: 12),
        const SizedBox(width: 5),
        for (final (index, account) in accounts.indexed) ...[
          if (index > 0)
            Text(
              ' · ',
              style: style.copyWith(color: grid.AppPalette.textFaint),
            ),
          _AccountFigure(account: account, style: style),
        ],
      ],
    );
  }
}

/// One account's figure: its weekly window, and — when it is not this
/// computer's — the machine it was read on.
class _AccountFigure extends StatelessWidget {
  const _AccountFigure({required this.account, required this.style});

  final UsageAccount account;
  final TextStyle style;

  /// A hostname can be long, and the strip is 26px of furniture. The panel
  /// behind the figure names every machine in full.
  static const double _labelMaxWidth = 110;

  @override
  Widget build(BuildContext context) {
    // ⚠️ ONE window, not every window this account reports — see
    // [ProviderUsage.railWindow]. Claude answers with three and Codex with one,
    // so printing them all made one account three figures wide and the other
    // one: two readouts that read as different KINDS of thing rather than the
    // same thing about two accounts.
    final window = account.reading.railWindow;
    if (window == null) return const SizedBox.shrink();
    final faint = style.copyWith(color: grid.AppPalette.textFaint);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${window.usedPercent.round()}% used',
          // Amber past 80, red past 90. The figure is exact either way, so the
          // colour is not carrying the number — it is carrying the moment the
          // number starts to matter, which is the whole reason somebody would
          // look down here unprompted. `19% used` and `92% used` used to print
          // identically.
          style: style.copyWith(
            fontWeight: grid.AppFont.medium,
            color: usagePressureInk(
              window.pressure,
              grid.AppPalette.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 4),
        // The countdown when there is one, and the window's own name when there
        // is not — so the figure is always followed by something that says
        // which limit it belongs to.
        Text(window.resetsInLabel() ?? window.label, style: faint),
        // This computer's figure is never labelled: it is the one a person
        // reads as "mine" without being told. Every OTHER account is, because
        // two Claude figures side by side are a riddle without it.
        if (!account.isLocal && account.machines.isNotEmpty) ...[
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _labelMaxWidth),
            child: Text(
              account.machines.length == 1
                  ? account.machines.first
                  : '${account.machines.first} +${account.machines.length - 1}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: faint,
            ),
          ),
        ],
      ],
    );
  }
}

/// The readout before the first answer: the same padding a live figure's hover
/// region takes, so the strip is the same width before and after.
class _UsageSkeleton extends StatelessWidget {
  const _UsageSkeleton();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: RailHoverTarget.gap,
      vertical: 4,
    ),
    child: SkeletonText(
      // Measured against what lands here — one figure per account, an engine
      // mark and a countdown each. A placeholder wider than its answer is the
      // jump a skeleton exists to prevent, in the other direction.
      style: TextStyle(fontSize: 11.5, fontWeight: grid.AppFont.medium),
      width: 84,
    ),
  );
}
