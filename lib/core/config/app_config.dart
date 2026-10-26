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

  /// Manifiesto JSON con la última versión publicada.
  ///
  /// Lo publica el workflow de GitHub Actions (archivo `latest.json` de la
  /// release). Formato:
  /// `{"version_code": 2002, "version_name": "1.0.2", "url": "https://.../qvatube.apk"}`
  ///
  /// Se puede cambiar en build con
  /// `--dart-define=UPDATE_MANIFEST_URL=https://tu-servidor/latest.json`.
  static const String updateManifestUrl = String.fromEnvironment(
    'UPDATE_MANIFEST_URL',
    defaultValue: 'https://github.com/R0ger0l1va/qvatube_apk/releases/download/latest/latest.json',
  );

  /// URL directa del APK de la última versión.
  ///
  /// Se usa como plan B: si no hay manifiesto, la app descarga este APK y lee
  /// su `versionCode` para saber si hay algo nuevo.
  static const String updateApkUrl = String.fromEnvironment(
    'UPDATE_APK_URL',
    defaultValue: 'https://github.com/R0ger0l1va/qvatube_apk/releases/download/latest/qvatube.apk',
  );

  /// Clave de la preferencia con el tema (temporada) activo.
  static const String themeIdKey = 'qvatube.theme_id';

  /// Claves de preferencias locales de la app.
  static const String showNewBadgesKey = 'qvatube.show_new_badges';
  static const String showContinueWatchingKey =
      'qvatube.show_continue_watching';

  /// Última versión instalada registrada en el dispositivo.
  static const String lastVersionCodeKey = 'qvatube.last_version_code';
}
