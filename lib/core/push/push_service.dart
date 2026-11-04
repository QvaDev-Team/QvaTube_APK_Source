import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../network/api_client.dart';

/// Estado de las notificaciones push en este teléfono.
class PushStatus {
  const PushStatus({required this.state, this.token, this.detail});

  /// `loading`, `ready` (hay token), `unavailable` (sin Google Play
  /// Services / Firebase no arranca) o `error` (no se obtuvo token: casi
  /// siempre sin conexión con Google).
  final String state;
  final String? token;
  final String? detail;
}

/// Notificaciones push con Firebase Cloud Messaging.
///
/// Fase de prueba: registra el teléfono, muestra su token en Configuración
/// para enviarle un mensaje de prueba desde la consola de Firebase y se lo
/// manda al backend (`POST /api/push/register`, si ya existe; si no, se
/// ignora). Las notificaciones con `notification` se muestran solas con la
/// app en segundo plano o cerrada; al tocarlas se abre la app.
class PushService {
  PushService._();

  static final ValueNotifier<PushStatus> status =
      ValueNotifier(const PushStatus(state: 'loading'));

  static bool _started = false;
  static ApiClient? _client;
  static void Function(RemoteMessage message)? _onOpen;
  static void Function(RemoteMessage message)? _onForeground;

  /// Arranca Firebase y pide el token. Nunca lanza: si el teléfono no tiene
  /// Google Play Services, la app sigue igual sin push.
  static Future<void> start({
    required ApiClient client,
    required void Function(RemoteMessage message) onOpen,
    required void Function(RemoteMessage message) onForeground,
  }) async {
    _client = client;
    _onOpen = onOpen;
    _onForeground = onForeground;
    if (_started) return;
    _started = true;

    try {
      await Firebase.initializeApp();
    } catch (e) {
      status.value = PushStatus(state: 'unavailable', detail: '$e');
      return;
    }

    final messaging = FirebaseMessaging.instance;
    FirebaseMessaging.onMessage.listen((m) => _onForeground?.call(m));
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _onOpen?.call(m));
    // Token FCM clásico: es el que acepta "Enviar mensaje de prueba" de la
    // consola y el campo `token` de la API HTTP v1. (register()/FID es el
    // modelo nuevo de envío directo; se puede migrar cuando el backend lo use.)
    // ignore: deprecated_member_use
    messaging.onTokenRefresh.listen(_setToken);

    try {
      final initial = await messaging.getInitialMessage();
      if (initial != null) _onOpen?.call(initial);
    } catch (_) {}

    await refreshToken();
  }

  /// Vuelve a pedir el token (también desde el botón de Configuración).
  static Future<void> refreshToken() async {
    if (!_started) return;
    status.value = PushStatus(state: 'loading', token: status.value.token);
    try {
      final token = await FirebaseMessaging.instance
          // ignore: deprecated_member_use
          .getToken()
          .timeout(const Duration(seconds: 30));
      if (token == null || token.isEmpty) {
        status.value = const PushStatus(
          state: 'error',
          detail: 'Google no devolvió ningún token.',
        );
        return;
      }
      await _setToken(token);
    } catch (e) {
      status.value = PushStatus(state: 'error', detail: _describe(e));
    }
  }

  static Future<void> _setToken(String token) async {
    status.value = PushStatus(state: 'ready', token: token);
    await registerWithBackend();
  }

  /// Tema al que el CI manda el aviso de "nueva versión" de cada release.
  static const updatesTopic = 'app-updates';

  /// `true` si hay token y el teléfono quedó suscrito a [updatesTopic].
  static Future<bool> subscribeToUpdates() async {
    if (status.value.state != 'ready') return false;
    try {
      await FirebaseMessaging.instance
          .subscribeToTopic(updatesTopic)
          .timeout(const Duration(seconds: 30));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Envía el token al backend para que pueda mandar los avisos de
  /// `/api/notifications` como push. Requiere sesión; los errores (sin
  /// sesión o endpoint aún no creado) se ignoran.
  static Future<void> registerWithBackend() async {
    final token = status.value.token;
    final client = _client;
    if (token == null || client == null || client.sessionCookie == null) {
      return;
    }
    try {
      await client.post(
        '/api/push/register',
        body: <String, dynamic>{'token': token, 'platform': 'android'},
        operation: 'el registro de notificaciones',
      );
    } catch (_) {}
  }

  /// Al cerrar sesión: que el backend deje de enviar a este teléfono.
  static Future<void> unregisterFromBackend() async {
    final token = status.value.token;
    final client = _client;
    if (token == null || client == null) return;
    try {
      await client.post(
        '/api/push/unregister',
        body: <String, dynamic>{'token': token},
        operation: 'la baja de notificaciones',
      );
    } catch (_) {}
  }

  static String _describe(Object e) {
    final text = e.toString();
    if (e is TimeoutException) {
      return 'Google no respondió a tiempo (¿sin conexión con Google?).';
    }
    if (text.contains('SERVICE_NOT_AVAILABLE')) {
      return 'Google Play Services no está disponible o no conecta '
          '(SERVICE_NOT_AVAILABLE).';
    }
    if (text.contains('MISSING_INSTANCEID_SERVICE')) {
      return 'Este teléfono no tiene Google Play Services.';
    }
    return text;
  }
}
