import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'machines_page.dart';
import 'phone_navigation.dart';

/// The signed-in phone app: machines → a machine's agents → one agent's terminal, each a page
/// pushed over the last.
///
/// Its own [Navigator], nested under the app's, on purpose: `RootShell` swaps this whole shell
/// out on sign-out, and the pages have to go with it rather than stay stacked over the login
/// screen, as they would on the root navigator.
class PhoneShell extends StatefulWidget {
  const PhoneShell({super.key, required this.notifier});

  final AppNotifier notifier;

  @override
  State<PhoneShell> createState() => _PhoneShellState();
}

class _PhoneShellState extends State<PhoneShell> {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) => NavigatorPopHandler<Object?>(
    // Android's back button reaches the root navigator first; walk this one back instead.
    onPopWithResult: (_) => _navigator.currentState?.maybePop(),
    child: Navigator(
      key: _navigator,
      onGenerateRoute: (_) =>
          phoneRoute((_) => MachinesPage(notifier: widget.notifier)),
    ),
  );
}
