import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// Instancia de `SharedPreferences` inyectada en `main()`.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider debe sobrescribirse');
});

/// ¿Ya se mostró la pantalla de introducción en este dispositivo?
final introSeenProvider = Provider<bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getBool(AppConfig.introSeenKey) ?? false;
});

/// Marca la intro como vista para que solo aparezca la primera vez.
Future<void> markIntroAsSeen(WidgetRef ref) async {
  final prefs = ref.read(sharedPreferencesProvider);
  await prefs.setBool(AppConfig.introSeenKey, true);
  ref.invalidate(introSeenProvider);
}

/// Guarda la cookie de sesión (`qva_session`) para que la sesión sobreviva
/// al cierre de la app.
class SessionStore {
  const SessionStore(this._prefs);

  final SharedPreferences _prefs;

  String? get cookie => _prefs.getString(AppConfig.sessionCookieKey);

  Future<void> save(String? cookie) async {
    if (cookie == null || cookie.isEmpty) {
      await _prefs.remove(AppConfig.sessionCookieKey);
      return;
    }
    await _prefs.setString(AppConfig.sessionCookieKey, cookie);
  }
}

final sessionStoreProvider = Provider<SessionStore>((ref) {
  return SessionStore(ref.watch(sharedPreferencesProvider));
});
