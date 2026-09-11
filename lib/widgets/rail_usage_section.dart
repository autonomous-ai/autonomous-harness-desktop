import 'package:flutter/widgets.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../usage/usage_controller.dart';
import '../usage/usage_pressure.dart';
import '../usage/usage_window.dart';
import 'engine_identity.dart';
import 'status_rail/grid_stat_panels.dart';
import 'status_rail/rail_figure.dart';
import 'status_rail/usage_ink.dart';
import 'status_rail/usage_panel.dart';

/// What the agent accounts on this machine have spent, as a section of the rail.
///
/// It used to be two figures on a strip along the bottom of the window — a
/// surface the width of the whole app, carrying two readings and nothing else,
/// taking its height from the terminals. The readings moved here and the strip
/// went with them.
///
/// ONE LINE PER ACCOUNT, and the line carries both the shape and the figure: a
/// bar for "nearly out" and a number for "how nearly". A bar alone makes the
/// exact figure a hover away; a number alone has no scale beside it, so 78%
/// reads as a fact rather than as a warning. On a strip there was room for one
/// of them. In a 258px rail there is room for both.
///
/// Hovering a line opens that line's own panel — every window the account
/// reports, not just the one the line prints. That split is deliberate: the
/// line answers "am I about to be stopped", the panel answers "by what, and
/// when does it lift".
class RailUsageSection extends StatefulWidget {
  const RailUsageSection({super.key, required this.usage});

  /// The shell's controller, shared with whatever else reads it. Not created
  /// here and not disposed here.
  final UsageController usage;

  @override
  State<RailUsageSection> createState() => _RailUsageSectionState();
}

class _RailUsageSectionState extends State<RailUsageSection> {
  /// One anchor per account: a [LayerLink] attaches to a single target, so the
  /// lines cannot share one.
  final Map<UsageProvider, RailFigureAnchor> _anchors = {
    for (final provider in UsageProvider.values)
      provider: newRailFigureAnchor(),
  };

  final _portal = OverlayPortalController();
  final Object _tapGroup = Object();
  UsageProvider? _open;

  void _enter(UsageProvider provider) {
    setState(() => _open = provider);
    _portal.show();
  }

  /// Closes only if the pointer has not already landed on another line.
  ///
  /// The panel is an overlay child, so moving from a line INTO its own panel is
  /// an exit as far as the line is concerned. Without the identity check the
  /// panel would close the moment anyone tried to read it.
  void _exit(UsageProvider provider) {
    if (_open != provider) return;
    setState(() => _open = null);
    if (_portal.isShowing) _portal.hide();
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ListenableBuilder(
      listenable: widget.usage,
      builder: (context, _) {
        final readings = widget.usage.readings
            .where((r) => r.railWindow != null)
            .toList(growable: false);
        // Nothing to say yet, or nothing to say at all: no header standing over
        // an empty space. The section appears with its first figure.
        if (readings.isEmpty) return const SizedBox.shrink();
        return OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) {
            final provider = _open;
            if (provider == null) return const SizedBox.shrink();
            final reading = widget.usage.readings.firstWhere(
              (r) => r.provider == provider,
              orElse: () => ProviderUsage.loading(provider),
            );
            final anchor = _anchors[provider]!;
            return GridStatPanel(
              link: anchor.link,
              anchorKey: anchor.key,
              tapGroupId: _tapGroup,
              onEnter: () => _enter(provider),
              onExit: () => _exit(provider),
              width: 248,
              child: UsagePanelContent(reading: reading),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
                child: Text(
                  'USAGE',
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 0.9,
                    fontWeight: grid.AppFont.medium,
                    color: grid.AppPalette.textFaint,
                  ),
                ),
              ),
              for (final reading in readings)
                RailHoverTarget<UsageProvider>(
                  kind: reading.provider,
                  anchor: _anchors[reading.provider]!,
                  semantics:
                      '${reading.provider.label} usage, '
                      '${reading.railWindow!.usedPercent.round()} percent used',
                  onEnter: _enter,
                  onExit: _exit,
                  child: _UsageLine(reading: reading),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One account: its mark, its name, how full it is, and by how much.
class _UsageLine extends StatelessWidget {
  const _UsageLine({required this.reading});

  final ProviderUsage reading;

  @override
  Widget build(BuildContext context) {
    final window = reading.railWindow!;
    // Amber past 80, red past 90 — the same threshold the strip used. The
    // figure is exact either way, so the colour is not carrying the number: it
    // carries the moment the number starts to matter, which is the only reason
    // anyone looks at this unprompted.
    // The FILL wears the provider's own colour while everything is calm, so the
    // bar and the mark beside it are visibly the same account. Pressure takes it
    // over past 80: at that point the bar has stopped being an identity and
    // started being a warning, and the warning outranks the identity.
    final identity = engineIdentity(reading.provider.engineId).color;
    final ink = usagePressureInk(
      window.pressure,
      grid.AppPalette.textSecondary,
    );
    final fill = usagePressureInk(window.pressure, identity);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          EngineMark(engine: reading.provider.engineId, size: 14),
          const SizedBox(width: 8),
          Text(
            reading.provider.label,
            style: TextStyle(
              fontSize: 12.5,
              color: grid.AppPalette.textPrimary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 4,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(color: grid.AppGlass.hair),
                    ),
                    // Positioned.fill around the fraction, not just inside it.
                    //
                    // A Stack gives its unpositioned children LOOSE constraints,
                    // and a ColoredBox with no child takes constraints.smallest
                    // under those — which is zero high. The track was visible
                    // and the fill was not, at every percentage, because it was
                    // being painted four pixels wide and none tall. Positioned
                    // .fill hands down a tight box, so the fraction has a height
                    // to take a share of.
                    Positioned.fill(
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        // Clamped, and not only for tidiness: a provider that
                        // reports over 100 would otherwise paint past its own
                        // track and the bar would stop meaning anything.
                        widthFactor: (window.usedPercent / 100).clamp(0.0, 1.0),
                        child: ColoredBox(color: fill),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          SizedBox(
            // Wide enough for "100%", which is the widest this can ever be —
            // and the one value it was NOT sized for. At 32 the figure wrapped
            // onto a second line the moment an account was actually spent,
            // which is precisely when someone is looking at it.
            width: 38,
            child: Text(
              '${window.usedPercent.round()}%',
              textAlign: TextAlign.right,
              // Belt as well as braces: a font the width was measured against
              // is not the font every machine resolves, and a figure that wraps
              // silently changes the height of the whole section.
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: grid.AppFont.medium,
                color: ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
