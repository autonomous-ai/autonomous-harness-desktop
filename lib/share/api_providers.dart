import 'grid_cli.dart';

/// A hosted provider this computer can lend its own key to.
///
/// The `grid` CLI carries the model whitelist but not a friendly name, a key
/// hint or where to get one, so those live here. [kind] must match the CLI's
/// own service kind, since it is what `grid join --api <kind>` is given.
class ApiProvider {
  const ApiProvider({
    required this.kind,
    required this.label,
    required this.envVar,
    this.keyHint = '',
    this.keyHelpUrl,
  });

  final String kind;
  final String label;

  /// The variable the CLI reads this kind's key from. The key travels in the
  /// child's environment and never in argv — `ps` is world-readable.
  final String envVar;
  final String keyHint;
  final String? keyHelpUrl;
}

/// The key providers this app can present.
///
/// Add one here once its kind is in the CLI whitelist; [discoverKeyProviders]
/// verifies each at runtime, so an entry the installed CLI does not know is
/// hidden rather than offered and then rejected by the join.
///
/// **The CLI's two seat kinds — `claude` and `codex-cli` — are deliberately not
/// here.** A seat serves a coding CLI already signed in on this computer, and
/// on a machine whose whole purpose is running coding agents that is a
/// different proposition from lending a key: it would put this Mac's Claude
/// subscription on a grid, quota and all, from a page about sharing spare
/// compute. It belongs on this page eventually, said in its own words, not
/// folded into a row headed "your API key".
const List<ApiProvider> kApiProviders = [
  ApiProvider(
    kind: 'openai',
    label: 'OpenAI',
    envVar: 'OPENAI_API_KEY',
    keyHint: 'sk-…',
    keyHelpUrl: 'https://platform.openai.com/api-keys',
  ),
];

/// One model a provider is whitelisted to serve.
class ApiModel {
  const ApiModel({required this.advertised, required this.vendorName});

  /// The grid-facing name (`openai:gpt-5.5`) — what a join advertises.
  final String advertised;

  /// The plain vendor id, which is what the user recognises.
  final String vendorName;
}

/// A provider the installed CLI actually whitelists, with its models.
class KeyProviderOffer {
  const KeyProviderOffer({required this.provider, required this.models});

  final ApiProvider provider;
  final List<ApiModel> models;
}

/// The key providers this CLI can serve right now.
///
/// `grid catalog --api <kind>` is curated static data — no key, no vendor call
/// — so the list can be shown before the user commits anything. A kind the CLI
/// does not know simply fails, and failing is how it gets left out.
Future<List<KeyProviderOffer>> discoverKeyProviders(GridCli cli) async {
  final offers = <KeyProviderOffer>[];
  for (final provider in kApiProviders) {
    final catalog = await cli.runJson<Map<String, dynamic>>([
      'catalog',
      '--api',
      provider.kind,
    ]);
    final rows = catalog?['models'];
    if (rows is! List || rows.isEmpty) continue;
    offers.add(
      KeyProviderOffer(
        provider: provider,
        models: [
          for (final row in rows)
            if (row is Map && row['advertised'] is String)
              ApiModel(
                advertised: row['advertised'] as String,
                vendorName: '${row['vendor_name'] ?? row['advertised']}',
              ),
        ],
      ),
    );
  }
  return offers;
}
