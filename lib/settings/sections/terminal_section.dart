import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/widgets/section_scaffold.dart';
import '../../terminal/terminal_font_store.dart';
import 'appearance_section.dart' show SettingLabel;

/// Settings ▸ Terminal: the face the agent's output is drawn in.
class TerminalSection extends StatelessWidget {
  const TerminalSection({super.key});

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return SectionScaffold(
      title: 'Terminal',
      subtitle:
          'The font every terminal pane is drawn in. ⌘+ and ⌘- change the size '
          'without leaving this screen.',
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ValueListenableBuilder<TerminalStyle>(
            valueListenable: terminalFontStore,
            builder: (context, style, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingLabel('Font'),
                const SizedBox(height: 8),
                _FamilyDropdown(family: terminalFontStore.family),
                const SizedBox(height: 18),
                const SettingLabel('Size'),
                const SizedBox(height: 8),
                _SizeStepper(size: style.fontSize),
                const SizedBox(height: 18),
                const SettingLabel('Preview'),
                const SizedBox(height: 8),
                _Preview(style: style),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('terminal-settings-reset-button'),
                    onPressed: () => unawaited(terminalFontStore.reset()),
                    child: const Text(
                      'Reset to default',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FamilyDropdown extends StatelessWidget {
  const _FamilyDropdown({required this.family});

  final TerminalFontChoice family;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<TerminalFontChoice>(
      key: const Key('terminal-font-family-dropdown'),
      isExpanded: true,
      value: family,
      items: [
        for (final choice in TerminalFontChoice.values)
          DropdownMenuItem(
            value: choice,
            child: Text(choice.label, style: const TextStyle(fontSize: 13.5)),
          ),
      ],
      onChanged: (choice) {
        if (choice != null) unawaited(terminalFontStore.setFamily(choice));
      },
    );
  }
}

class _SizeStepper extends StatelessWidget {
  const _SizeStepper({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          key: const Key('terminal-font-size-decrease'),
          icon: const Icon(Icons.remove, size: 18),
          onPressed: () => unawaited(terminalFontStore.decreaseSize()),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${size.round()}pt',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5),
          ),
        ),
        IconButton(
          key: const Key('terminal-font-size-increase'),
          icon: const Icon(Icons.add, size: 18),
          onPressed: () => unawaited(terminalFontStore.increaseSize()),
        ),
      ],
    );
  }
}

/// A live sample rendered with the exact style about to go into the terminal —
/// if a pick were ever going to misalign, it shows right here before it reaches
/// any remote TUI.
class _Preview extends StatelessWidget {
  const _Preview({required this.style});

  final TerminalStyle style;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: grid.AppPalette.windowBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: grid.AppGlass.hair),
      ),
      child: Text(
        '┌─ mmmmmmmmmm ─┐\nagent@harness ❯ _',
        style: style.toTextStyle(color: grid.AppPalette.textPrimary),
      ),
    );
  }
}
