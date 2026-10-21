import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/app_preferences.dart';
import 'api_client.dart';

/// Cliente HTTP único de la app.
///
/// Restaura la cookie de sesión guardada en el dispositivo y la persiste
/// cada vez que el servidor la renueva.
final apiClientProvider = Provider<ApiClient>((ref) {
  final store = ref.watch(sessionStoreProvider);
  final client = ApiClient(
    onSessionCookie: (cookie) => store.save(cookie),
  );
  client.sessionCookie = store.cookie;
  ref.onDispose(client.dio.close);
  return client;
});
