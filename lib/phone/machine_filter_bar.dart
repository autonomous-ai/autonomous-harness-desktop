import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart';
import '../state/app_state.dart';
import 'phone_status.dart';
import 'status_pill.dart';

/// The machine chips over the Agents tab.
///
/// The machine does not disappear in this direction — it stops being a page you walk through and
/// becomes a way to narrow the list you are already looking at. A chip for a machine that cannot
/// be opened is drawn disabled rather than hidden: seeing that a machine needs its password is
/// half of why somebody would look here at all.
class MachineFilterBar extends StatelessWidget {
  const MachineFilterBar({
    super.key,
    required this.machines,
    required this.selectedId,
    required this.countFor,
    required this.totalCount,
    required this.onSelect,
  });

  final List<MachineState> machines;

  /// The machine the list is narrowed to, or null for all of them.
  final String? selectedId;

  /// How many agents a machine contributes, for the figure on its chip.
  final int Function(String machineId) countFor;

  final int totalCount;

  /// Null selects every machine.
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _Chip(
            label: 'All',
            count: totalCount,
            selected: selectedId == null,
            onTap: () => onSelect(null),
          ),
          for (final machine in machines) _chipFor(machine),
        ],
      ),
    );
  }

  Widget _chipFor(MachineState machine) {
    final id = machine.machine.machineId;
    final status = phoneMachineStatusOf(machine);
    final ready = status == PhoneMachineStatus.ready;
    return _Chip(
      label: machine.machine.displayName,
      // A count only where there is one to give. A machine that has not answered would otherwise
      // read as "0 agents", which is a claim rather than a silence.
      count: ready ? countFor(id) : null,
      tone: phoneMachineSummary(machine).tone,
      selected: selectedId == id,
      // Narrowing to a machine with nothing to show is a dead end, so those chips do not select.
      // They still say what is wrong through their dot, and the Machines tab is where it is fixed.
      onTap: ready ? () => onSelect(id) : null,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.tone,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final int? count;

  /// Drawn as the leading dot. Null on the "All" chip, which is not a machine and has no state.
  final PhoneTone? tone;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(right: 7, top: 4, bottom: 4),
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Material(
          color: selected ? AppSurface.accentWash : AppGlass.rowFill,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected
                      ? AppPalette.accentOnSurface.withValues(alpha: 0.5)
                      : AppGlass.hair,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tone != null) ...[
                    _Dot(tone: tone!),
                    const SizedBox(width: 6),
                  ],
                  ConstrainedBox(
                    // A long machine name must not push the chips off the rail; it ellipsises and
                    // the ones after it stay reachable.
                    //
                    // 108 rather than a rounder 140: hostnames run long by default — a stock
                    // `caokhanh-Inspiron-3520` or `MacBooks-MacBook-Pro` is over twenty characters
                    // — and at 140 just two of them fill a 390pt screen, hiding every chip after
                    // them. Ellipsised earlier, four fit, and the leading characters are the part
                    // that tells two machines apart anyway.
                    constraints: const BoxConstraints(maxWidth: 108),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? AppPalette.textPrimary
                            : AppPalette.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '$count',
                      style: TextStyle(
                        color: AppPalette.textFaint,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        fontFeatures: AppFont.tabularFigures,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.tone});

  final PhoneTone tone;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return SizedBox.square(
      dimension: 7,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: phoneToneColor(tone),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
