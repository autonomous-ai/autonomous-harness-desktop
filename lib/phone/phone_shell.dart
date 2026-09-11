import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'agent_index.dart';
import 'agents_tab.dart';
import 'machines_tab.dart';
import 'phone_tab_bar.dart';
import 'settings_page.dart';

/// The signed-in phone app: three tabs, each with its own page stack.
///
/// Its own [Navigator] per tab, nested under the app's, on purpose. Two reasons, and both are
/// things a single shared navigator gets wrong:
///
///  - `RootShell` swaps this whole shell out on sign-out, and the pages have to go with it rather
///    than stay stacked over the login screen, as they would on the root navigator.
///  - A tab remembers where it was. Walking into a machine's agents, switching to Settings and
///    coming back returns to that machine, not to the root of the tab — which is what every phone
///    OS does and what a single stack cannot express.
class PhoneShell extends StatefulWidget {
  const PhoneShell({super.key, required this.notifier});

  final AppNotifier notifier;

  @override
  State<PhoneShell> createState() => _PhoneShellState();
}

class _PhoneShellState extends State<PhoneShell> {
  PhoneTab _tab = PhoneTab.agents;

  final _navigators = {
    for (final tab in PhoneTab.values) tab: GlobalKey<NavigatorState>(),
  };

  /// One per tab — see the note at the `HeroControllerScope` below for why they cannot be shared.
  final _heroControllers = {
    for (final tab in PhoneTab.values) tab: HeroController(),
  };

  @override
  void dispose() {
    for (final controller in _heroControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  NavigatorState? get _currentNavigator => _navigators[_tab]?.currentState;

  void _select(PhoneTab tab) {
    if (tab == _tab) {
      // A second tap on the tab you are already on pops that tab back to its root — the phone
      // convention, and the only way back out of a deep stack without walking every page.
      _currentNavigator?.popUntil((route) => route.isFirst);
      _syncCanPop();
      return;
    }
    // The new tab has a depth of its own, so the back gesture's answer changes with it.
    setState(() {
      _tab = tab;
      _tabCanPop = _navigators[tab]?.currentState?.canPop() ?? false;
    });
  }

  Widget _rootFor(PhoneTab tab) => switch (tab) {
    PhoneTab.agents => AgentsTab(notifier: widget.notifier),
    PhoneTab.machines => MachinesTab(notifier: widget.notifier),
    PhoneTab.settings => SettingsPage(notifier: widget.notifier),
  };

  /// Whether the tab on screen has a page to go back to — what [PopScope] is given.
  ///
  /// Kept as state rather than read inline in `build`, because a push or pop inside a nested
  /// [Navigator] does not rebuild this widget: the flag has to be pushed here by the notification
  /// below, or `canPop` would answer with whatever was true when the shell last happened to build.
  bool _tabCanPop = false;

  /// Android's back button, handled per tab.
  ///
  /// ⚠️ Deliberately NOT `NavigatorPopHandler`, which is what a single-stack phone shell would
  /// use. It tracks one `canPop` flag fed by `NavigationNotification`s bubbling out of its
  /// subtree — and an [IndexedStack] keeps all three navigators MOUNTED and notifying, so the flag
  /// ends up reflecting whichever tab spoke last rather than the one on screen. A back press on a
  /// root Agents tab would then be swallowed because Settings happened to be two pages deep.
  ///
  /// So the notification is used only as a SIGNAL that some stack moved, and the answer is then
  /// read from the current tab's navigator — the one stack the person is actually looking at.
  bool _onNavigation(NavigationNotification notification) {
    _syncCanPop();
    // Let it keep bubbling: the root navigator above this shell tracks its own state from it.
    return false;
  }

  void _syncCanPop() {
    final next = _currentNavigator?.canPop() ?? false;
    if (next == _tabCanPop) return;
    // The notification arrives mid-build of the subtree that sent it, so defer rather than calling
    // setState inside another widget's build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = _currentNavigator?.canPop() ?? false;
      if (current == _tabCanPop) return;
      setState(() => _tabCanPop = current);
    });
  }

  void _handleBack(bool didPop, Object? result) {
    if (didPop) return;
    _currentNavigator?.maybePop().then((_) {
      if (mounted) _syncCanPop();
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.notifier,
    builder: (context, _) => PopScope<Object?>(
      // False while this tab has somewhere to go back to, so the gesture reaches [_handleBack]
      // instead of leaving the app. True at a tab's root: the press then belongs to the system.
      canPop: !_tabCanPop,
      onPopInvokedWithResult: _handleBack,
      child: NotificationListener<NavigationNotification>(
        onNotification: _onNavigation,
        child: Scaffold(
          body: IndexedStack(
            index: PhoneTab.values.indexOf(_tab),
            sizing: StackFit.expand,
            children: [
              for (final tab in PhoneTab.values)
                // ⚠️ Each tab's navigator needs its OWN HeroController, and without this the
                // engine-mark flights simply never happen — silently, with no error.
                //
                // `MaterialApp` installs one controller for the ROOT navigator only; a nested
                // `Navigator` inherits nothing, so its routes have no observer to drive a flight.
                // One shared controller is not the fix either — `navigator.dart` on
                // `HeroControllerScope`: "The hero controller ... can only subscribe to one
                // navigator", and these three are all mounted at once inside the IndexedStack.
                HeroControllerScope(
                  controller: _heroControllers[tab]!,
                  child: Navigator(
                    key: _navigators[tab],
                    // ⚠️ The controller goes in the SCOPE ONLY, never also in `observers`.
                    // `NavigatorState._updateEffectiveObservers` appends the scope's controller to
                    // `widget.observers` itself, so listing it here registers it twice and trips
                    // "A HeroController can not be shared by multiple Navigators" — which reads
                    // like a sharing bug and is really a double-subscription by one navigator.
                    onGenerateRoute: (_) =>
                        MaterialPageRoute<void>(builder: (_) => _rootFor(tab)),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: PhoneTabBar(
            current: _tab,
            onSelect: _select,
            waitingCount: waitingAgents(agentIndex(widget.notifier)).length,
          ),
        ),
      ),
    ),
  );
}
