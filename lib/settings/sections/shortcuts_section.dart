import 'package:flutter/material.dart';

import '../../shared/widgets/section_scaffold.dart';
import '../../shortcuts/shortcuts_list.dart';

/// Settings ▸ Keyboard shortcuts — the same list the ⌘/ sheet shows, in the
/// place someone looks when they don't yet know the sheet exists.
class ShortcutsSection extends StatelessWidget {
  const ShortcutsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'Keyboard shortcuts',
      subtitle: 'Every key this app takes. Press ⌘/ to see them anywhere.',
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: const ShortcutsList(),
        ),
      ),
    );
  }
}
