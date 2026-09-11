import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../shared/theme/app_theme.dart';
import '../widgets/engine_identity.dart';
import 'agent_hero.dart';
import 'agent_index.dart';
import 'phone_card.dart';
import 'status_pill.dart';

/// One agent in the Agents tab.
///
/// Differs from [AgentTile] — the row a single machine's page draws — in the one way the tab needs:
/// it names the MACHINE, because this list mixes them and a name alone is ambiguous the moment two
/// machines both have a `main` or a `docs` agent.
class AgentRow extends StatelessWidget {
  const AgentRow({super.key, required this.entry, required this.onTap});

  final AgentEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final agent = entry.agent;
    return AgentHeroCard(
      // An agent with no terminal does not open, so there is no page for the row to become — a tag
      // here would be one end of a flight that never happens.
      tag: agent.terminalAvailable
          ? agentHeroTag(
              machineId: entry.machineId,
              agentId: agent.id,
              source: AgentHeroSource.agents,
            )
          : null,
      child: PhoneCard(
        onTap: agent.terminalAvailable ? onTap : null,
        // A rim in the attention colour, so a waiting agent is findable in a long list without
        // reading a word of it — the list's whole job on a phone.
        border: entry.isWaiting
            ? Border.all(color: AppPalette.warn.withValues(alpha: 0.42))
            : null,
        child: Row(
          children: [
            PhoneCardGlyph(
              child: EngineMark(
                engine: agent.engine,
                displayName: agent.engineDisplayName,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    agent.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppPalette.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  _StatusAndMachine(entry: entry),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (agent.terminalAvailable)
              Icon(
                LucideIcons.chevronRight300,
                size: 22,
                color: AppPalette.textFaint,
              ),
          ],
        ),
      ),
    );
  }
}

/// The status line, with the machine's name after it.
///
/// One line rather than two: a phone row is 70pt and a third line of type would either shrink the
/// name above it or push the card taller than a thumb's reach for the list.
class _StatusAndMachine extends StatelessWidget {
  const _StatusAndMachine({required this.entry});

  final AgentEntry entry;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Row(
      children: [
        Flexible(child: StatusPill(summary: entry.summary)),
        const SizedBox(width: 6),
        // The machine is context, not status, so it is drawn a step quieter than the pill it
        // follows — and it yields its width first when both cannot fit.
        Flexible(
          child: Text(
            '· ${entry.machineName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppPalette.textFaint, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
