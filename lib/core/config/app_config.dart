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

  /// El contenido definitivo de cada pantalla todavía no está definido, por lo
  /// que las llamadas al servidor permanecen desactivadas. La capa de red está
  /// implementada y verificada contra `doc/openapi.json`, pero no se ejecuta
  /// hasta que se habilite este flag.
  static const bool remoteCallsEnabled = false;

  /// Clave de almacenamiento para saber si ya se mostró la pantalla de
  /// introducción (intro) en este dispositivo.
  static const String introSeenKey = 'qvatube.intro_seen';

  /// Clave de almacenamiento de la sesión (cookie `qva_session`).
  static const String sessionCookieKey = 'qvatube.session_cookie';
}
