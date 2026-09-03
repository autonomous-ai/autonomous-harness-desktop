import 'package:flutter/widgets.dart';

import '../../share/widgets/share_pane.dart';

/// Settings ▸ Share Intelligence: what this computer gives a grid, rather than
/// what it takes from one.
///
/// A thin wrapper on purpose. Everything here lives in `lib/share/`, because it
/// is a feature with a CLI, a state machine and a design of its own that
/// happens to be reached from Settings — not a setting.
class ShareIntelligenceSection extends StatelessWidget {
  const ShareIntelligenceSection({super.key});

  @override
  Widget build(BuildContext context) => const SharePane();
}
