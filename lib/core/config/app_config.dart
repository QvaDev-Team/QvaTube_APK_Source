/// Configuración global de la app.
abstract final class AppConfig {
  const AppConfig._();

  /// Base URL de la API de QvaTube (doc/openapi.json -> servers[0].url).
  ///
  /// Puede sobreescribirse en build con:
  /// `flutter run --dart-define=API_URL=https://host/`
  static const String apiBaseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://qvatube.hidenplay.net/',
  );

  /// Las pantallas ya están conectadas a la API de QvaTube. Si hay que dejar
  /// la app en modo "sin red" (por ejemplo, mientras se define el contenido
  /// de alguna pantalla), basta con poner este flag en `false`: el cliente
  /// lanza `RemoteCallsDisabledException` y la UI avisa al usuario.
  static const bool remoteCallsEnabled = true;

  /// Clave de almacenamiento para saber si ya se mostró la pantalla de
  /// introducción (intro) en este dispositivo.
  static const String introSeenKey = 'qvatube.intro_seen';

  /// Clave de almacenamiento de la sesión (cookie `qva_session`).
  static const String sessionCookieKey = 'qvatube.session_cookie';

  /// Clave de la preferencia con el tema (temporada) activo.
  static const String themeIdKey = 'qvatube.theme_id';

  /// Claves de preferencias locales de la app.
  static const String showNewBadgesKey = 'qvatube.show_new_badges';
  static const String showContinueWatchingKey = 'qvatube.show_continue_watching';
}
