/// The Grid control plane's own model, as `GET /v1/grid/me` returns it.
///
/// Parsed by hand, like `core/models.dart` — the endpoint's OpenAPI entry
/// declares an empty response schema, so these fields are what the live API
/// actually sends (read off it on 2026-09-03), not what a generator inferred.
library;

/// The signed-in Grid account.
class GridUser {
  const GridUser({
    required this.sub,
    required this.email,
    required this.name,
    this.emailDomain,
  });

  final String sub;
  final String email;
  final String name;
  final String? emailDomain;

  static GridUser fromJson(Map<String, dynamic> json) => GridUser(
    sub: json['sub'] as String? ?? '',
    email: json['email'] as String? ?? '',
    name: json['name'] as String? ?? '',
    emailDomain: json['email_domain'] as String?,
  );
}

/// This account's place in one network — the roles it was granted, and how.
class GridMembership {
  const GridMembership({
    required this.roles,
    required this.status,
    this.source,
    this.createdByEmail,
  });

  /// `consumer`, `provider`, `both`, `admin` — a member can hold several.
  final List<String> roles;
  final String status;

  /// `allowlist`, `domain`, … — why this account is a member at all.
  final String? source;
  final String? createdByEmail;

  bool get isAdmin => roles.contains('admin');

  static GridMembership fromJson(Map<String, dynamic> json) => GridMembership(
    roles: [
      for (final role in json['roles'] as List<dynamic>? ?? const [])
        if (role is String) role,
    ],
    status: json['status'] as String? ?? 'unknown',
    source: json['source'] as String?,
    createdByEmail: json['created_by_email'] as String?,
  );
}

/// One grid this account can talk to.
class GridNetwork {
  const GridNetwork({
    required this.networkId,
    required this.name,
    required this.ownerEmail,
    required this.networkType,
    required this.status,
    required this.routerEnabled,
    required this.routerAdvisors,
    this.description,
    this.lanSignalingUrl,
    this.billingMode,
    this.accessDomain,
    this.createdAt,
    this.member,
  });

  final String networkId;
  final String name;
  final String ownerEmail;

  /// `permissioned-providers`, `permissioned-public`, `private-domain`, …
  final String networkType;
  final String status;
  final bool routerEnabled;

  /// `provider/model` pairs the router may consult. Empty when the router is
  /// off, and printed rather than counted — one advisor is a name, not a total.
  final List<String> routerAdvisors;
  final String? description;
  final String? lanSignalingUrl;
  final String? billingMode;

  /// Set only on a `private-domain` grid: the email domain that may join.
  final String? accessDomain;
  final DateTime? createdAt;

  /// Null when the API returns a grid without this account's membership on it —
  /// a public grid it can see but has not joined.
  final GridMembership? member;

  /// The name to show. A grid can be created without one, and its id is the
  /// only thing that always identifies it.
  String get displayName => name.trim().isEmpty ? networkId : name.trim();

  bool isOwnedBy(String email) =>
      email.isNotEmpty && ownerEmail.toLowerCase() == email.toLowerCase();

  static GridNetwork fromJson(Map<String, dynamic> json) {
    final member = json['member'];
    final createdAt = json['created_at'];
    return GridNetwork(
      networkId: json['network_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      ownerEmail: json['owner_email'] as String? ?? '',
      networkType: json['network_type'] as String? ?? 'unknown',
      status: json['status'] as String? ?? 'unknown',
      routerEnabled: json['router_enabled'] == true,
      routerAdvisors: [
        for (final advisor
            in json['router_advisors'] as List<dynamic>? ?? const [])
          if (advisor is Map)
            [
              advisor['provider'],
              advisor['model'],
            ].whereType<String>().join('/'),
      ],
      description: json['description'] as String?,
      lanSignalingUrl: json['lan_signaling_url'] as String?,
      billingMode: json['billing_mode'] as String?,
      accessDomain: json['access_domain'] as String?,
      // Seconds since the epoch, not milliseconds — the API's own unit.
      createdAt: createdAt is num
          ? DateTime.fromMillisecondsSinceEpoch(createdAt.round() * 1000)
          : null,
      member: member is Map
          ? GridMembership.fromJson(Map<String, dynamic>.from(member))
          : null,
    );
  }
}

/// The whole `GET /v1/grid/me` answer: who you are, and every grid you are on.
class GridMe {
  const GridMe({required this.user, required this.networks});

  final GridUser user;
  final List<GridNetwork> networks;

  static GridMe fromJson(Map<String, dynamic> json) => GridMe(
    user: GridUser.fromJson(
      Map<String, dynamic>.from(json['user'] as Map? ?? const {}),
    ),
    networks: [
      for (final network in json['networks'] as List<dynamic>? ?? const [])
        if (network is Map)
          GridNetwork.fromJson(Map<String, dynamic>.from(network)),
    ],
  );
}
