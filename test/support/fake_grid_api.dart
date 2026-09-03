// Shared by every test that renders the Grid pane, so the payload it parses is
// written down once. This is the shape `GET /v1/grid/me` really returned on
// 2026-09-03, trimmed to one owned grid and one consumed one.
import 'package:harness/grid/grid_api_client.dart';
import 'package:harness/grid/grid_credentials.dart';
import 'package:harness/grid/grid_network.dart';

const kGridMePayload = {
  'user': {
    'sub': '107217236829486611895',
    'email': 'huy@example.com',
    'name': 'Huy Pham',
    'email_domain': 'example.com',
    'can_restrict_to_domain': false,
  },
  'networks': [
    {
      'network_id': 'grid-aaf6a46ced4f42f9',
      'name': 'hp-1-1',
      'owner_email': 'huy@example.com',
      'lan_signaling_url': 'https://grid.autonomous.ai/grid-aaf6a46ced4f42f9',
      'description': '',
      'network_type': 'permissioned-public',
      'status': 'active',
      'created_at': 1787281262,
      'billing_mode': 'local_free',
      'router_enabled': true,
      'router_advisors': [
        {'provider': 'openai', 'model': 'gpt-5-mini'},
      ],
      'access_domain': null,
      'member': {
        'email': 'huy@example.com',
        'roles': ['admin', 'both'],
        'status': 'active',
        'source': 'allowlist',
        'created_by_email': '',
      },
    },
    {
      'network_id': 'grid-e3b210eacc5b4cdf',
      'name': 'Water Grid',
      'owner_email': 'someone@else.com',
      'lan_signaling_url': 'https://grid.autonomous.ai/grid-e3b210eacc5b4cdf',
      'network_type': 'permissioned-providers',
      'status': 'active',
      'router_enabled': false,
      'router_advisors': [],
      'member': {
        'roles': ['consumer'],
        'status': 'active',
        'source': 'allowlist',
      },
    },
  ],
};

/// Answers with [kGridMePayload] — or throws, for the failure path — without
/// going near the network, the way `_FakeCliLogin` stands in for the real CLI.
class FakeGridApi extends GridApiClient {
  FakeGridApi({this.error, this.credentialError, this.modelIds});

  /// Fails `me()`.
  final String? error;

  /// Fails `credentials()` — the path an agent launch takes.
  final String? credentialError;

  /// What `models()` answers with. Null gives the two the office grid serves.
  final List<String>? modelIds;

  int calls = 0;
  int credentialCalls = 0;
  final List<String> modelBaseUrls = [];

  @override
  Future<GridMe> me() async {
    calls++;
    if (error != null) throw Exception(error);
    return GridMe.fromJson(Map<String, dynamic>.from(kGridMePayload));
  }

  @override
  Future<GridCredentials> credentials(String networkId) async {
    credentialCalls++;
    if (credentialError != null) throw Exception(credentialError);
    return GridCredentials(
      networkId: networkId,
      baseUrl: 'https://grid.example/$networkId/relay/v1',
      apiKey: 'relay-key-for-$networkId',
    );
  }

  @override
  Future<List<String>> models({
    required String baseUrl,
    required String apiKey,
  }) async {
    modelBaseUrls.add(baseUrl);
    return modelIds ?? const ['Auto', 'GLM-4.7-Flash'];
  }
}
