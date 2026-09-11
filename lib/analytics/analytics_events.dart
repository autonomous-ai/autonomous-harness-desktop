import 'analytics.dart';

/// The events this app sends, one method each.
///
/// An extension rather than a set of loose helpers, so every [Analytics]
/// implementation gets them for free — and so the name and the params of an
/// event are written down **once**. Two call sites that name the same action
/// differently is the failure mode this exists to prevent.
///
/// Adding an event: add a method here, keep the name `snake_case`, and keep the
/// params to product facts — a short code, an option, a count. **Never** a
/// prompt, terminal output, an agent's name, a repository path or a machine
/// hostname. This stream describes what someone did, not what they wrote or
/// what their machines are called; ids are fine, the names people give things
/// are not.
extension AnalyticsEvents on Analytics {
  // --- The launch ---------------------------------------------------------

  /// The app came up. [signedIn] separates a returning user from someone who
  /// is about to meet the login screen.
  void appOpened({required bool signedIn}) =>
      track('app_opened', params: {'signed_in': signedIn});

  /// The app is quitting, after [open]. Sent on the way out, so it is the last
  /// thing the queue drains.
  void appClosed({required Duration open}) =>
      track('app_closed', params: {'open_seconds': open.inSeconds});

  /// A screen was opened. [screen] is the section's stable name, never its
  /// label — labels are rewritten weekly and a renamed label would read as a
  /// new screen.
  ///
  /// [source] is the DOOR that was used, and it is `required` for the reason
  /// `new_agent_opened`'s is: a screen with several ways in tells you almost
  /// nothing as a bare count.
  ///
  /// Values: `account_menu` and `shortcut` (a door that OPENED Settings on this
  /// pane); `rail` (moved here from another pane, using the settings rail).
  void screenView(String screen, {required String source}) =>
      track('screen_view', params: {'screen': screen, 'source': source});

  // --- Sign-in ------------------------------------------------------------

  /// Sign-in completed.
  void signedIn() => track('signed_in');

  /// Sign-in didn't complete. [reason] is a short code — `cancelled`,
  /// `failed` — never the error text, which can carry a path or a host name.
  void signInFailed(String reason) =>
      track('sign_in_failed', params: {'reason': reason});

  /// The user signed out.
  void signedOut() => track('signed_out');

  /// First-run provisioning finished. [ready] is false when a required step
  /// could not be completed — which says how much of a fresh Mac this app can
  /// actually set up on its own, otherwise only visible in a support thread.
  void environmentPrepared({required bool ready}) =>
      track('environment_prepared', params: {'ready': ready});

  // --- Agents -------------------------------------------------------------
  //
  // How many people open the New agent dialog, how many of those finish it,
  // and how many of THOSE ever send the agent a message. Each step is a
  // separate event carrying the same device and user id, so the funnel is
  // built by counting distinct people per step.

  /// The New agent dialog was opened. [source] is which door was used —
  /// `machine_row` (the `+` on a machine's row), `rail_empty` (the button the
  /// empty rail shows), `pane_empty` (the button in the empty centre pane) or
  /// `shortcut` (⌘N and the app menu).
  ///
  /// Sent by `showNewAgentDialog` itself rather than by its callers, so a door
  /// added later cannot forget to report itself.
  void newAgentOpened({required String source}) =>
      track('new_agent_opened', params: {'source': source});

  /// An agent was created from the New agent dialog. [engine] is the engine id
  /// and [bypassPermission] whether its own guardrails were switched off, both
  /// product facts.
  ///
  /// The working folder is deliberately absent: it is an absolute path, which
  /// this stream never carries.
  void agentCreated({required String engine, required bool bypassPermission}) =>
      track(
        'agent_created',
        params: {'engine': engine, 'bypass_permission': bypassPermission},
      );

  /// The first message of a signed-in session — how long it took this person to
  /// get from being logged in to actually talking to an agent, whichever agent
  /// that turned out to be.
  ///
  /// **Once per sign-in, not per agent.** Which agent it was is
  /// [agentCreated]'s question; this one is about the gap at the top of the
  /// funnel, where somebody signs in and then does nothing.
  ///
  /// [from] says what started the clock, because the two populations behave
  /// nothing alike: `sign_in` is a fresh log-in, `launch` is opening the app
  /// with a session already on the machine. Averaging them together would hide
  /// both.
  ///
  /// Driven by the CLI's `turn_started`, not by the composer, so a message
  /// typed straight into the terminal counts the same as one sent from the box
  /// underneath it — which is how most people drive these engines.
  ///
  /// ⚠️ **No message text, ever**, and no agent, machine or folder either. Who
  /// it was and when are already on every event (`user_email`,
  /// `event_timestamp`); what this adds is the wait.
  void appFirstMessage({
    required String from,
    required int secondsSinceLogin,
  }) => track(
    'app_first_message',
    params: {'from': from, 'seconds_since_login': secondsSinceLogin},
  );

  // --- The shape of the desk --------------------------------------------------

  /// What this person's workspace looks like right now.
  ///
  /// ONE EVENT FOR THREE QUESTIONS — how many agents, how many machines, what is
  /// actually open — and it is a SNAPSHOT rather than a stream. The alternative
  /// was an event per pane opened and closed, which answers the same questions
  /// only by replaying a whole session in order, and costs an event every time
  /// somebody rearranges their grid.
  ///
  /// Sent once per visit and again when the shape changes, debounced. Counts and
  /// a list of engine ids; no agent names, no machine names, no folder.
  void workspaceSnapshot({
    required int machinesLinked,
    required int machinesOnline,
    required int agentsTotal,
    required int panesOpen,
    required bool railFolded,
    required List<String> engines,
    String? layoutPreset,
  }) => track(
    'workspace_snapshot',
    params: {
      'machines_linked': machinesLinked,
      'machines_online': machinesOnline,
      'agents_total': agentsTotal,
      'panes_open': panesOpen,
      'rail_folded': railFolded,
      // Sorted so the same desk reads as the same value twice, rather than as
      // two different strings because a map iterated in a different order.
      'engines': (engines.toSet().toList()..sort()).join(','),
      'layout_preset': layoutPreset,
    },
  );

  // --- What people actually use ------------------------------------------------

  /// One feature, used, by one door.
  ///
  /// A SINGLE EVENT WITH A CONTROLLED VOCABULARY, not forty event names. The
  /// vocabulary is `ShortcutAction`'s own — already written down, already stable,
  /// already the thing the shortcut sheet prints — so a feature added later
  /// reports itself the day it is bound, and nobody has to remember to add an
  /// event for it.
  ///
  /// [source] is WHICH DOOR, and it carries most of the value. `shortcut` and
  /// `menu` for the same feature are two different populations, and after the
  /// keyboard-first work there is a third question the bare count cannot answer:
  /// `hjkl` against `arrow` is whether that work was worth doing. A feature is
  /// not "used 400 times"; it is used 400 times by 12 people through one door
  /// and 4 through another.
  void featureUsed({required String feature, required String source}) =>
      track('feature_used', params: {'feature': feature, 'source': source});

  // --- Time, honestly ----------------------------------------------------------

  /// How long the app was OPEN against how long it was in front of somebody.
  ///
  /// Both numbers, because only the pair is honest. A window left open behind a
  /// browser for eight hours reports eight hours of "use" if you ask [appClosed]
  /// alone — and this app is one people leave open, so that is not an edge case,
  /// it is the common one. The difference is the answer.
  void appFocusTime({required Duration open, required Duration focused}) =>
      track(
        'app_focus_time',
        params: {
          'open_seconds': open.inSeconds,
          'focused_seconds': focused.inSeconds,
        },
      );

  /// A tile opened, and which door opened it.
  void paneOpened({required String engine, required String source}) =>
      track('pane_opened', params: {'engine': engine, 'source': source});

  /// A tile closed, with how long it was on screen and how much happened in it.
  ///
  /// [secondsOpen] is the real "how long do people work with one agent" — the
  /// question [appFocusTime] answers for the window and nothing answered for an
  /// agent. [turns] beside it separates a tile somebody worked in from one they
  /// opened, looked at and closed, which are the same duration and not the same
  /// event.
  void paneClosed({
    required String engine,
    required int secondsOpen,
    required int turns,
  }) => track(
    'pane_closed',
    params: {'engine': engine, 'seconds_open': secondsOpen, 'turns': turns},
  );

  /// A turn was sent to an agent, and by which route.
  ///
  /// THE CENTRAL EVENT OF THIS STREAM. [appFirstMessage] fires once per sign-in
  /// and answers "did they ever start"; this fires every turn and answers how
  /// people actually drive these engines — which is the thing the product is
  /// shaped around and the thing nothing measured.
  ///
  /// [source] is `composer`, `palette` (⌘B), or `terminal`. Terminal is the
  /// DEFAULT rather than a detection: typing straight into the pty is invisible
  /// to this app by design, so a turn nothing claimed is one somebody typed.
  ///
  /// ⚠️ A turn the DIAL sent without going through the window's palette lands
  /// here as `terminal` too — the window cannot tell those apart. The dial's own
  /// `dial_turn_sent` is the cross-check, and the two are meant to be read
  /// together rather than either being trusted alone.
  ///
  /// No message text, ever. Not a word of it, not its length.
  void turnSent({required String engine, required String source}) =>
      track('turn_sent', params: {'engine': engine, 'source': source});

  // --- Was the router right? ---------------------------------------------------

  /// One ⌘B routing, and what the person did with the answer.
  ///
  /// [chosenRank] IS THE POINT. The router prints a ranked list and dispatches
  /// on its own top score; whether the agent a person actually wants is the one
  /// it put first is the single question that says if the routing is any good,
  /// and nothing measured it. 0 means the router was right, 3 means they scrolled
  /// past three of its suggestions, and -1 means they closed it and went
  /// elsewhere.
  ///
  /// [confidence] is the winner's own score, so the threshold that decides
  /// silent-send against ask-first can be checked against outcomes rather than
  /// argued about.
  ///
  /// The task text is NEVER here. Not a word, not its length.
  void taskRouted({
    required String outcome,
    required int candidates,
    required int chosenRank,
    required double confidence,
    required String via,
  }) => track(
    'task_routed',
    params: {
      'outcome': outcome,
      'candidates': candidates,
      'chosen_rank': chosenRank,
      // Two decimals: the threshold lives at 0.85 and the interesting question
      // is which side of it a route fell on, not its fourth digit.
      'confidence': double.parse(confidence.toStringAsFixed(2)),
      'via': via,
    },
  );

  // --- Machines ----------------------------------------------------------------

  /// A machine joined this account's list, or left it.
  ///
  /// The count is already in [workspaceSnapshot]; this is the EVENT, which the
  /// snapshot cannot be: two machines linked and one unlinked in a week reads as
  /// "one more machine" in snapshots alone.
  void machineLinked({required String mode}) =>
      track('machine_linked', params: {'mode': mode});

  void machineUnlinked() => track('machine_unlinked');

  /// One step of pairing a computer, and how it went.
  ///
  /// A funnel, not a result: pairing is where people are lost, and knowing that
  /// 40 started and 12 finished is worth nothing without knowing which step ate
  /// the other 28.
  void machineSetup({required String step, required String outcome}) =>
      track('machine_setup', params: {'step': step, 'outcome': outcome});

  // --- Updates -----------------------------------------------------------------

  /// A new version was offered, taken, or waved away.
  ///
  /// For an app that updates itself, "how many people are running last month's
  /// build" is a question with no other source — and it is the first thing worth
  /// knowing when a fix does not seem to have reached anybody.
  void updateOffered({required String from, required String to}) =>
      track('update_offered', params: {'from': from, 'to': to});

  void updateInstalled({required String from, required String to}) =>
      track('update_installed', params: {'from': from, 'to': to});

  void updateSkipped({required String from, required String to}) =>
      track('update_skipped', params: {'from': from, 'to': to});
}
