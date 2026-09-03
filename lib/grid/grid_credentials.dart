/// A short-lived key for one grid's relay, as
/// `GET /v1/grid/networks/{id}/credentials` returns it.
///
/// Fetched fresh every time it is needed rather than stored: [expiresAt] is
/// real (about a year out today, but the API is free to shorten it), and a key
/// cached to disk would eventually be handed to an engine that then fails to
/// answer with no way for the user to tell why.
class GridCredentials {
  const GridCredentials({
    required this.networkId,
    required this.baseUrl,
    required this.apiKey,
    this.expiresAt,
  });

  final String networkId;

  /// The OpenAI-compatible relay root, e.g.
  /// `https://grid.autonomous.ai/<network id>/relay/v1`. Already includes the
  /// version segment, so `$baseUrl/models` is the models endpoint.
  final String baseUrl;
  final String apiKey;
  final DateTime? expiresAt;

  static GridCredentials fromJson(Map<String, dynamic> json) {
    final expires = json['expires_at'];
    return GridCredentials(
      networkId: json['network_id'] as String? ?? '',
      baseUrl: json['base_url'] as String? ?? '',
      apiKey: json['api_key'] as String? ?? '',
      // Seconds since the epoch, like every other timestamp this API sends.
      expiresAt: expires is num
          ? DateTime.fromMillisecondsSinceEpoch(expires.round() * 1000)
          : null,
    );
  }
}
