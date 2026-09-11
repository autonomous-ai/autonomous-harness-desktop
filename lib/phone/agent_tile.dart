import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/models.dart';
import '../shared/theme/app_theme.dart';
import '../state/app_state.dart';
import '../widgets/engine_identity.dart';
import 'agent_hero.dart';
import 'phone_card.dart';
import 'phone_status.dart';
import 'status_pill.dart';

/// One agent on a machine's page: its engine, its name, and what it is doing. An agent with no
/// terminal to attach is drawn dimmed and does not open.
class AgentTile extends StatelessWidget {
  const AgentTile({
    super.key,
    required this.machine,
    required this.agent,
    required this.onTap,
  });

  final MachineState machine;
  final Agent agent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return AgentHeroCard(
      // Null where the row does not open — see [AgentHeroCard].
      tag: agent.terminalAvailable
          ? agentHeroTag(
              machineId: machine.machine.machineId,
              agentId: agent.id,
              source: AgentHeroSource.machine,
            )
          : null,
      child: PhoneCard(
        onTap: agent.terminalAvailable ? onTap : null,
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
                  StatusPill(summary: phoneAgentSummary(machine, agent)),
                ],
              ),
            ),
            const SizedBox(width: 8),
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
