import '../core/config.dart';
import '../core/harness_file_store.dart';
import '../core/local_key_value_store.dart';

/// Persists user-configurable connection settings in the Harness home file.
class ConfigStore {
  final LocalKeyValueStore _storage;
  static const _baseUrlKey = 'app_api_base_url';
  static const _environmentKey = 'app_autonomous_environment';
  static const _skippedDesktopUpdateVersionKey =
      'skipped_desktop_update_version';
  static const _environmentSetupVersionKey = 'environment_setup_version';
  static const String defaultBaseUrl = 'https://harness-api.autonomous.ai';

  ConfigStore({LocalKeyValueStore? storage})
    : _storage = storage ?? HarnessFileStore.shared;

  AppConfig get config => AppConfig(
    apiBaseUrl: _cachedBaseUrl ?? defaultBaseUrl,
    autonomousEnv: _cachedEnvironment ?? 'prod',
  );
  String? _cachedBaseUrl;
  String? _cachedEnvironment;
  String? _cachedSkippedDesktopUpdateVersion;
  int? _cachedEnvironmentSetupVersion;

  String? get skippedDesktopUpdateVersion => _cachedSkippedDesktopUpdateVersion;
  // The setup version this machine last passed provisioning at (see `kEnvironmentSetupVersion`).
  // CLI, tmux and Grid never uninstall themselves, so as long as this is still current there is
  // nothing to gain from re-probing them — and flashing EnvironmentSetupScreen — on every launch.
  int? get environmentSetupVersion => _cachedEnvironmentSetupVersion;

  Future<AppConfig> load() async {
    // Keep the tiny startup path sequential and predictable.
    final baseUrl = await _storage.read(_baseUrlKey);
    final environment = await _storage.read(_environmentKey);
    final skippedUpdate = await _storage.read(_skippedDesktopUpdateVersionKey);
    final environmentSetupVersion = await _storage.read(
      _environmentSetupVersionKey,
    );
    _cachedBaseUrl = baseUrl ?? defaultBaseUrl;
    _cachedEnvironment = environment == 'stag' ? 'stag' : 'prod';
    _cachedSkippedDesktopUpdateVersion = skippedUpdate?.trim().isEmpty ?? true
        ? null
        : skippedUpdate!.trim();
    _cachedEnvironmentSetupVersion = environmentSetupVersion == null
        ? null
        : int.tryParse(environmentSetupVersion);
    return config;
  }

  Future<void> save(String baseUrl) async {
    _cachedBaseUrl = baseUrl;
    await _storage.write(_baseUrlKey, baseUrl);
  }

  Future<void> saveEnvironment(String autonomousEnv) async {
    _cachedEnvironment = autonomousEnv == 'stag' ? 'stag' : 'prod';
    await _storage.write(_environmentKey, _cachedEnvironment!);
  }

  Future<void> saveSkippedDesktopUpdateVersion(String? version) async {
    final normalized = version?.trim();
    _cachedSkippedDesktopUpdateVersion =
        normalized == null || normalized.isEmpty ? null : normalized;
    if (_cachedSkippedDesktopUpdateVersion == null) {
      await _storage.delete(_skippedDesktopUpdateVersionKey);
    } else {
      await _storage.write(
        _skippedDesktopUpdateVersionKey,
        _cachedSkippedDesktopUpdateVersion!,
      );
    }
  }

  Future<void> saveEnvironmentSetupVersion(int version) async {
    _cachedEnvironmentSetupVersion = version;
    await _storage.write(_environmentSetupVersionKey, version.toString());
  }

  Future<void> reset() async {
    _cachedBaseUrl = null;
    _cachedEnvironment = null;
    _cachedSkippedDesktopUpdateVersion = null;
    _cachedEnvironmentSetupVersion = null;
    await Future.wait([
      _storage.delete(_baseUrlKey),
      _storage.delete(_environmentKey),
      _storage.delete(_skippedDesktopUpdateVersionKey),
      _storage.delete(_environmentSetupVersionKey),
    ]);
  }
}
