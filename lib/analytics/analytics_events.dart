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
  /// the funnel sees which one people take. [networkId] is null for "each
  /// engine's own login", which is a choice like any other and the one a
  /// funnel most needs to be able to count.
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
}
