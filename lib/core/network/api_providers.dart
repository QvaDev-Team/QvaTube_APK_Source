import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/app_preferences.dart';
import '../platform/device_channel.dart';
import 'api_client.dart';
import 'response_cache.dart';

/// Cliente HTTP único de la app.
///
/// Restaura la cookie de sesión guardada en el dispositivo y la persiste
/// cada vez que el servidor la renueva.
final apiClientProvider = Provider<ApiClient>((ref) {
  final store = ref.watch(sessionStoreProvider);
  final client = ApiClient(
    onSessionCookie: (cookie) => store.save(cookie),
    // Respuestas guardadas para ver el catálogo sin conexión.
    responseCache: ResponseCache(
      () async =>
          Directory('${await DeviceChannel.cacheDirectory()}/api_cache'),
    ),
  );
  client.sessionCookie = store.cookie;
  ref.onDispose(client.dio.close);
  return client;
});
