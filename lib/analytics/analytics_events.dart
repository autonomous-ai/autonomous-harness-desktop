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
/// prompt, terminal output, an agent's name, a repository path, a machine
/// hostname or a grid's name. This stream describes what someone did, not what
/// they wrote or what their machines are called; ids are fine, the names people
/// give things are not.
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
  void screenView(String screen) =>
      track('screen_view', params: {'screen': screen});

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
  /// could not be completed, [grid] whether the optional Grid CLI landed —
  /// together they say how much of a fresh Mac this app can actually set up on
  /// its own, which is otherwise only visible in a support thread.
  void environmentPrepared({required bool ready, required bool grid}) =>
      track('environment_prepared', params: {'ready': ready, 'grid': grid});

  // --- Grids --------------------------------------------------------------
  //
  // The grid funnel, mirroring Grid's own: which grid a person points this
  // computer at, whether they ever look at what is on it, whether they bring
  // anyone else onto it, and whether an agent actually runs against it. Every
  // event carries the same device and user id, so the funnel is built by
  // counting the distinct people who reach each step — no event needs to know
  // about the one before it. A grid is identified by [networkId] only; its
  // NAME is user-chosen text and never leaves the machine.

  /// The user chose which grid new agents run against. [source] = `pill` (the
  /// sidebar) or `settings` (Settings ▸ Grid) — the two doors, kept apart so
  /// the funnel sees which one people take. [networkId] is null for "No
  /// grid", which is a choice like any other and the one a funnel most needs
  /// to be able to count.
  void gridPicked({required String source, String? networkId}) => track(
    'grid_picked',
    params: {
      'source': source,
      'network_id': networkId,
      'has_grid': networkId != null && networkId.isNotEmpty,
    },
  );

  /// The grids on this account came back, once per launch. [count] is how many,
  /// which is what tells "nobody picks a grid" apart from "nobody HAS one".
  ///
  /// No `source`: both doors read the one shared controller, and which door was
  /// used is already [gridPicked]'s question. An event fired per surface would
  /// count the same account twice for opening two panels.
  void gridNetworksLoaded({required int count}) =>
      track('grid_networks_loaded', params: {'count': count});

  /// The node dashboard was opened from the status rail — the first moment a
  /// person looks at what their grid is actually made of.
  void gridDashboardOpened({String? networkId, int? nodes}) => track(
    'grid_dashboard_opened',
    params: {'network_id': networkId, 'nodes': nodes},
  );

  /// The share sheet was opened, meaning to put someone else on the grid.
  void gridShareOpened({String? networkId, int? members}) => track(
    'grid_share_opened',
    params: {'network_id': networkId, 'members': members},
  );

  /// Someone was invited. [role] is the grant they were given. The invitee's
  /// address is NOT sent — that is a third party's identity, and it is not ours
  /// to file under our own funnel.
  void gridMemberInvited({required String role, String? networkId}) => track(
    'grid_member_invited',
    params: {'role': role, 'network_id': networkId},
  );

  /// An existing member's grant was changed — one upsert, so one event.
  void gridMemberRoleChanged({required String role, String? networkId}) =>
      track(
        'grid_member_role_changed',
        params: {'role': role, 'network_id': networkId},
      );

  /// A member was removed from the grid.
  void gridMemberRemoved({String? networkId}) =>
      track('grid_member_removed', params: {'network_id': networkId});

  /// An agent was created to run against a grid — the north-star moment for
  /// this app, the equivalent of Grid's "a model went live". [engine] is the
  /// engine id, [model] the model chosen for it, both product facts.
  void gridAgentLaunched({
    required String engine,
    String? model,
    String? networkId,
  }) => track(
    'grid_agent_launched',
    params: {'engine': engine, 'model': model, 'network_id': networkId},
  );

  // --- Agents -------------------------------------------------------------
  //
  // The funnel [gridAgentLaunched] could not answer, because it fires only for
  // an agent that was pointed at a grid: how many people open the New agent
  // dialog, how many of those finish it, and how many of THOSE ever send the
  // agent a message. Each step is a separate event carrying the same device and
  // user id, so the funnel is built by counting distinct people per step.

  /// The New agent dialog was opened. [source] is which door was used —
  /// `machine_row` (the `+` on a machine's row), `rail_empty` (the button the
  /// empty rail shows), `pane_empty` (the button in the empty centre pane) or
  /// `shortcut` (⌘N and the app menu).
  ///
  /// Sent by `showNewAgentDialog` itself rather than by its callers, so a door
  /// added later cannot forget to report itself.
  void newAgentOpened({required String source}) =>
      track('new_agent_opened', params: {'source': source});

  /// An agent was created — **every** agent, unlike [gridAgentLaunched], which
  /// counts only the ones pointed at a grid.
  ///
  /// [model] is the model chosen for it, and is null in two different cases
  /// that [onGrid] tells apart: `onGrid: true` with no model is Auto (the grid
  /// picks), and `onGrid: false` is the engine's own login, where there is no
  /// model for us to name.
  ///
  /// The working folder is deliberately absent: it is an absolute path, which
  /// this stream never carries.
  void agentCreated({
    required String engine,
    required bool onGrid,
    required bool bypassPermission,
    String? model,
    String? networkId,
  }) => track(
    'agent_created',
    params: {
      'engine': engine,
      'model': model,
      'on_grid': onGrid,
      'network_id': networkId,
      'bypass_permission': bypassPermission,
    },
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

  /// A RUNNING agent was moved onto a grid, or onto a different model.
  /// [outcome] = `ok` or the CLI's own refusal code (`UNSUPPORTED`, …) — which
  /// is how "the feature does not work" and "this machine's CLI is too old"
  /// stop looking identical in the data.
  void gridAgentRetargeted({
    required String outcome,
    String? engine,
    String? model,
  }) => track(
    'grid_agent_retargeted',
    params: {'outcome': outcome, 'engine': engine, 'model': model},
  );

  // --- Running out of subscription ----------------------------------------
  //
  // Two events, and the pair is the point: the first counts the people who
  // were TOLD their subscription is nearly spent, the second the people who
  // did something about it. Either one alone answers nothing — a warning
  // nobody sees and a warning nobody acts on produce the same number of moves.

  /// The strip above the status rail offered a way past a nearly-spent limit.
  ///
  /// [window] is the vendor's own name for it (`Session`, `Weekly`, `5h`) and
  /// [percent] is rounded, because a limit is not a measurement anybody needs
  /// to two places. Sent once per window per cycle — the same rule the strip
  /// itself follows — so this counts occasions rather than polls.
  void usageLimitWarned({
    required String provider,
    required String window,
    required int percent,
    required String action,
  }) => track(
    'usage_limit_warned',
    params: {
      'provider': provider,
      'window': window,
      'percent': percent,
      'action': action,
    },
  );

  /// Somebody pressed it. [action] is the offer that was on the button —
  /// `moveAgents` or `chooseProvider` — and [agents] how many were about to
  /// move, which is what separates "one agent, idly" from "this was the whole
  /// session's work".
  void usageLimitOffer({
    required String provider,
    required String action,
    required int agents,
  }) => track(
    'usage_limit_offer',
    params: {'provider': provider, 'action': action, 'agents': agents},
  );

  /// The strip was closed without being taken. Without this, a warning somebody
  /// waved away and one that was never drawn are the same absence in the funnel.
  void usageLimitDismissed({
    required String provider,
    required String window,
  }) => track(
    'usage_limit_dismissed',
    params: {'provider': provider, 'window': window},
  );
}
