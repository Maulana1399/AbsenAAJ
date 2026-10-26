/// Aplikasi-level configuration.
///
/// The API base URL is injected at build time via `--dart-define`, so no
/// environment-specific URL is hardcoded in source.
///
/// Examples:
///   Android emulator (host machine loopback):
///     flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
///
///   Physical device on the same LAN as the backend:
///     flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
///   (use the LAN IP of the machine running Laravel, never 127.0.0.1)
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const Duration apiConnectTimeout = Duration(seconds: 10);
  static const Duration apiReceiveTimeout = Duration(seconds: 30);
}