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
