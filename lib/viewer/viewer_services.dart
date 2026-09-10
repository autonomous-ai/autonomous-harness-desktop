import '../auth/auth_session.dart';
import '../core/config.dart';
import '../ws/relay_codec.dart';
import 'direct_auth.dart';
import 'direct_auth_api.dart';
import 'direct_link.dart';
import 'direct_login.dart';
import 'e2ee_relay_codec.dart';
import 'viewer_key_store.dart';

/// Everything a viewer build uses in place of the harness CLI, built once and handed to
/// `AppNotifier`: the SSO session, signing in, the machines this device has linked and the E2EE
/// sessions to them. A desktop build has none — and where it is null, nothing in the app behaves
/// any differently than it did before viewers existed.
class ViewerServices {
  const ViewerServices._({
    required this.keys,
    required this.auth,
    required this.login,
    required this.links,
    required this.relayCodecs,
  });

  factory ViewerServices({
    required AppConfig config,
    required AuthSession session,
    ViewerKeyStore? keys,
  }) {
    final store = keys ?? ViewerKeyStore();
    final auth = DirectAuth(session: session, api: DirectAuthApi(config: config));
    return ViewerServices._(
      keys: store,
      auth: auth,
      login: DirectLogin(auth: auth),
      links: DirectLink(keys: store, auth: auth, config: config),
      relayCodecs: viewerRelayCodecs(store),
    );
  }

  final ViewerKeyStore keys;
  final DirectAuth auth;
  final DirectLogin login;
  final DirectLink links;
  final RelayCodecFactory relayCodecs;
}
