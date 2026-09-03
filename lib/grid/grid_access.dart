/// Who may reach a grid at all — the rule under the people, in words.
///
/// **Read-only here, deliberately.** Grid's own share sheet lets an owner change
/// this rule; this app does not, and the reason is not effort. Changing it
/// restarts the grid under everyone using it and cuts off whoever the new rule
/// excludes — and until Harness has a Grid sign-in of its own, every build runs
/// on one shared developer token (see `kGridSessionToken`), so the flip would
/// land on somebody else's grid, in somebody else's name. A statement of the
/// rule is honest at that price; a control is not.
///
/// The wire values are the control plane's own (`grid_networks/store.py`,
/// `VALID_NETWORK_TYPES`), read there rather than copied from Grid's client
/// enum — which carries three that only half overlap with what
/// `GET /v1/grid/me` actually sends.
library;

import 'grid_network.dart';

/// What a grid's access rule is called, and what it permits — or null when the
/// control plane named a rule this app has no words for.
///
/// Null rather than a guess: a sentence under the heading "Who can join" is
/// read as a promise about who is already in, and inventing one for an
/// unrecognised type is the one mistake here that nobody could catch.
typedef GridAccessRule = ({String label, String description});

/// Auto-provisioned, one per email domain. **The grid's `name` IS the domain**
/// (the control plane refuses a `private-domain` grid named anything else), and
/// every account on it is an open `both` member — synthetic, with no allowlist
/// row, which is why those rows cannot be removed.
const String kNetworkTypePrivateDomain = 'private-domain';

/// Allowlisted providers, open consumers: any signed-in account may *use* the
/// grid, only the people on the list may put a machine on it.
const String kNetworkTypePermissionedProviders = 'permissioned-providers';

/// The two rules that gate everyone by the allowlist. `permissioned-public`
/// differs from `permissioned` only in having a public URL, which is not a fact
/// about who may join.
const String kNetworkTypePermissioned = 'permissioned';
const String kNetworkTypePermissionedPublic = 'permissioned-public';

/// Open to anyone at all.
const String kNetworkTypePermissionless = 'permissionless';

/// The rule [network] is under, in the words the share sheet prints.
///
/// The domain is taken from the grid's own name rather than from the viewer's
/// email: `access_domain` comes back null on every network `GET /v1/grid/me`
/// returns, the viewer may be on the grid from some other domain entirely, and
/// the name is the field the control plane actually constrains.
GridAccessRule? gridAccessRule(GridNetwork network) {
  switch (network.networkType) {
    case kNetworkTypePrivateDomain:
      final domain = (network.accessDomain ?? network.name).trim();
      if (domain.isEmpty) return null;
      return (
        label: '@$domain emails',
        // Two clauses, both load-bearing. "or start an AI node" is not padding
        // — a domain account is admitted as a **`both`** member, not as a
        // consumer. And "as well as the people you invite" is what stops the
        // rule reading as an exclusion: the allowlist keeps working beside it,
        // which is why this grid's roster holds both kinds of row.
        description:
            'Anyone with an @$domain email can use this grid, or start an AI '
            'node to power it, as well as the people you invite.',
      );
    case kNetworkTypePermissioned:
    case kNetworkTypePermissionedPublic:
      return (
        label: 'Invite only',
        description:
            'Only the people listed above can use this grid, or start an AI '
            'node to power it.',
      );
    case kNetworkTypePermissionedProviders:
      return (
        label: 'Anyone signed in',
        // The second clause is never dropped: opening up who may *use* the grid
        // is not opening up who may plug a machine into it, and the first half
        // alone reads as the larger promise.
        description:
            'Anyone signed in to Grid can use it. Only the people above can '
            'start an AI node to power it.',
      );
    case kNetworkTypePermissionless:
      return (
        label: 'Public',
        description:
            'Anyone can use this grid, or start an AI node to power it.',
      );
    default:
      return null;
  }
}

/// Whether this account owns [network] — the one thing that decides whether the
/// sheet offers to change or remove anybody.
///
/// Read off the grid rather than off the roster's `admin` row: the roster is
/// about the people IN it, and a viewer who is not the owner may still be
/// looking at a list whose first row holds `admin`.
bool gridIsOwnedBy(GridNetwork network, String? email) =>
    email != null && network.isOwnedBy(email);
