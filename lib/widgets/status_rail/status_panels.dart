import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../grid/grid_overview.dart';
import '../../grid/grid_overview_controller.dart';
import '../../shared/theme/app_theme.dart' as grid;

/// The frame every rail panel shares: a card that opens upward from the strip.
class StatusPanel extends StatelessWidget {
  const StatusPanel({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.width = 300,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final double width;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        constraints: const BoxConstraints(maxHeight: 340),
        decoration: BoxDecoration(
          color: grid.AppPalette.cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: grid.AppGlass.hair),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 22,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 11, 13, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: grid.AppPalette.textPrimary,
                      fontSize: 12.5,
                      fontWeight: grid.AppFont.semibold,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: grid.AppPalette.textSecondary,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: grid.AppGlass.hair),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(13, 9, 13, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One `label … value` line.
class PanelRow extends StatelessWidget {
  const PanelRow({
    super.key,
    required this.label,
    required this.value,
    this.dim = false,
  });

  final String label;
  final String value;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: grid.AppPalette.textSecondary,
                fontSize: 11.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              color: dim
                  ? grid.AppPalette.textFaint
                  : grid.AppPalette.textPrimary,
              fontSize: 11.5,
              fontWeight: grid.AppFont.medium,
            ),
          ),
        ],
      ),
    );
  }
}

/// The grid's hardware: what it has, how much is in use, how much it will run
/// at once, and how fast.
class PowerPanel extends StatelessWidget {
  const PowerPanel({super.key, required this.power, required this.gridName});

  final GridPower power;
  final String gridName;

  @override
  Widget build(BuildContext context) {
    final vram = power.vramGb;
    final used = power.vramUsedGb;
    final util = power.gpuUtilPct;
    final parallel = power.parallel;
    final throughput = power.throughputTokS;
    return StatusPanel(
      title: gridName,
      subtitle: '${power.onlineNodes} '
          '${power.onlineNodes == 1 ? 'machine' : 'machines'} online, serving '
          '${power.models} ${power.models == 1 ? 'model' : 'models'}.',
      children: [
        // Every row is omitted rather than dashed when the relay did not say —
        // a dash in a figures panel reads as a measurement of nothing.
        if (vram != null)
          PanelRow(label: 'Graphics memory', value: formatMemoryGb(vram)),
        if (vram != null && used != null)
          PanelRow(
            label: 'In use',
            value: '${formatMemoryGb(used)} · '
                '${(used / vram * 100).round()}%',
          ),
        if (util != null)
          PanelRow(label: 'GPU load', value: '${util.round()}%'),
        if (parallel != null)
          PanelRow(
            label: 'Requests at once',
            value: '$parallel',
          ),
        if (throughput != null)
          PanelRow(
            label: 'Throughput',
            value: '${throughput.round()} tok/s',
          ),
        if (!power.ringIsMemory && util != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              // Said out loud, because the ring changes meaning here and a
              // reader who assumed memory would be reading the wrong number.
              'The ring shows GPU load — this grid reports no memory in use.',
              style: TextStyle(
                color: grid.AppPalette.textFaint,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
      ],
    );
  }
}

/// The machines behind the grid, busiest first.
class NodesPanel extends StatelessWidget {
  const NodesPanel({super.key, required this.nodes});

  final List<OverviewNode> nodes;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final online = [
      for (final node in nodes)
        if (node.online) node,
    ]..sort((a, b) => (b.answered?.freshInput ?? 0).compareTo(
        a.answered?.freshInput ?? 0,
      ));
    return StatusPanel(
      width: 330,
      title: 'Machines',
      subtitle: online.isEmpty
          ? 'Nothing is online on this grid right now.'
          : '${online.length} online, most work first.',
      children: [
        for (final node in online) _NodeRow(node: node),
      ],
    );
  }
}

class _NodeRow extends StatelessWidget {
  const _NodeRow({required this.node});

  final OverviewNode node;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final answered = node.answered;
    final vram = node.poolVramGb;
    final used = node.vramUsedMb;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  node.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: grid.AppPalette.textPrimary,
                    fontSize: 12,
                    fontWeight: grid.AppFont.medium,
                  ),
                ),
              ),
              if (answered != null && answered.freshInput > 0)
                Text(
                  formatTokens(answered.freshInput),
                  style: TextStyle(
                    color: grid.AppPalette.textSecondary,
                    fontSize: 11.5,
                    fontWeight: grid.AppFont.medium,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 1),
          Text(
            [
              // A seat brings a plan, not hardware — saying "0 GB" of a machine
              // relaying to a hosted model would be a fact about the wrong
              // thing.
              if (node.isSubscription)
                '${node.planType} plan'
              else if (vram != null && used != null)
                '${formatMemoryGb(used / 1024)} of ${formatMemoryGb(vram)}'
              else if (vram != null)
                formatMemoryGb(vram),
              if (node.hardware.isNotEmpty) node.hardware,
              if (node.models.isNotEmpty) node.models.first,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: grid.AppPalette.textFaint,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// What the grid can answer with.
class ModelsPanel extends StatelessWidget {
  const ModelsPanel({super.key, required this.models});

  final List<OverviewModel> models;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return StatusPanel(
      width: 320,
      title: 'Models',
      subtitle: models.isEmpty
          ? 'This grid advertises none right now.'
          : '${models.length} available to anyone on this grid.',
      children: [
        for (final model in models)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    model.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: grid.AppPalette.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (model.contextLength != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    '${(model.contextLength! / 1024).round()}k',
                    style: TextStyle(
                      color: grid.AppPalette.textFaint,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// What the grid has answered in the relay's window.
class WorkPanel extends StatelessWidget {
  const WorkPanel({super.key, required this.answered});

  final Answered answered;

  @override
  Widget build(BuildContext context) {
    final window = formatWindow(answered.windowSeconds);
    final suffix = window.isEmpty ? '' : ' in the last $window';
    return StatusPanel(
      title: 'Work answered',
      subtitle: '${formatTokens(answered.requests)} '
          '${answered.requests == 1 ? 'request' : 'requests'}$suffix.',
      children: [
        // Split three ways because the three cost wildly different things, and
        // one total would be dominated by the nearly-free half.
        PanelRow(
          label: 'Read, fresh',
          value: formatTokens(answered.freshInput),
        ),
        PanelRow(
          label: 'Read, from cache',
          value: formatTokens(answered.tokensCached),
          dim: true,
        ),
        PanelRow(label: 'Generated', value: formatTokens(answered.tokensOut)),
      ],
    );
  }
}

/// Who is on the grid. Only a count is known — the roster itself is the Grid
/// app's to show, and this app has no screen that needs it.
class MembersPanel extends StatelessWidget {
  const MembersPanel({super.key, required this.members});

  final int members;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return StatusPanel(
      width: 260,
      title: 'People',
      subtitle: '$members ${members == 1 ? 'person is' : 'people are'} on this '
          'grid.',
      children: [
        Row(
          children: [
            Icon(
              LucideIcons.info300,
              size: 13,
              color: grid.AppPalette.textFaint,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'Anyone here can send work to it, and anyone sharing answers '
                'it.',
                style: TextStyle(
                  color: grid.AppPalette.textFaint,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
