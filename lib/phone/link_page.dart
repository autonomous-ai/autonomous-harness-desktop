import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart';
import '../state/app_state.dart';
import '../widgets/link_machine_screen.dart';
import 'agents_page.dart';
import 'phone_header.dart';
import 'phone_navigation.dart';

/// A machine's password form, as a phone page — the same [LinkMachineScreen] the desktop pops
/// up, since the exchange behind it is the same.
///
/// It leaves by itself both ways: forward onto the machine's agents once the link lands, and
/// back when the form's own Close is pressed.
class LinkPage extends StatefulWidget {
  const LinkPage({super.key, required this.notifier, required this.machineId});

  final AppNotifier notifier;
  final String machineId;

  @override
  State<LinkPage> createState() => _LinkPageState();
}

class _LinkPageState extends State<LinkPage> {
  /// The form's Close marks the prompt dismissed. One already dismissed before this page opened
  /// must not shut the page on its first frame.
  late final bool _dismissedBefore = widget.notifier.isLinkPromptDismissed(
    widget.machineId,
  );
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_follow);
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_follow);
    super.dispose();
  }

  void _follow() {
    if (_leaving || !mounted) return;
    final machine = widget.notifier.stateOf(widget.machineId);
    final navigator = Navigator.of(context);
    if (machine != null && !machine.needsLink) {
      _leaving = true;
      navigator.pushReplacement(
        phoneRoute(
          (_) => AgentsPage(
            notifier: widget.notifier,
            machineId: widget.machineId,
          ),
        ),
      );
      return;
    }
    final closed =
        !_dismissedBefore &&
        widget.notifier.isLinkPromptDismissed(widget.machineId);
    if (machine == null || closed) {
      _leaving = true;
      navigator.maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final machine = widget.notifier.stateOf(widget.machineId);
    return Scaffold(
      backgroundColor: AppPalette.windowBg,
      body: SafeArea(
        child: Column(
          children: [
            PhoneHeader(
              title: machine?.machine.displayName ?? 'Machine',
              subtitle: Text(
                'Enter the password set on this machine',
                style: TextStyle(color: AppPalette.textSecondary, fontSize: 13),
              ),
            ),
            if (machine != null)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: LinkMachineScreen(
                    notifier: widget.notifier,
                    machineState: machine,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
