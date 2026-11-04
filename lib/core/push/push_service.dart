import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../network/api_client.dart';
import '../platform/device_channel.dart';

/// Notificaciones push con Firebase Cloud Messaging.
///
/// - Registra el teléfono y manda su token al backend
///   (`POST /api/push/register`; se ignora si falla).
/// - Se suscribe al tema [updatesTopic], por donde el CI avisa de cada
///   versión nueva.
/// - Si el teléfono no recibe push (sin Google Play Services o sin conexión
///   con Google), el aviso de versión nueva sale de la comprobación
///   periódica en segundo plano (UpdateCheckWorker).
/// - El usuario puede apagarlas en Configuración ([setEnabled]): se borra el
///   token y no llega nada.
class PushService {
  PushService._();

  /// Tema al que el CI manda el aviso de "nueva versión" de cada release.
  static const updatesTopic = 'app-updates';
  static const _enabledKey = 'qvatube.notifications_enabled';

  /// Notificaciones activadas por el usuario (por defecto, sí).
  static final ValueNotifier<bool> enabled = ValueNotifier(true);

  static SharedPreferences? _prefs;
  static bool _firebaseReady = false;
  static bool _started = false;
  static String? _token;
  static ApiClient? _client;
  static void Function(RemoteMessage message)? _onOpen;
  static void Function(RemoteMessage message)? _onForeground;

  /// Arranca Firebase y aplica la preferencia. Nunca lanza: si el teléfono
  /// no tiene Google Play Services, la app sigue igual sin push.
  static Future<void> start({
    required SharedPreferences prefs,
    required ApiClient client,
    required void Function(RemoteMessage message) onOpen,
    required void Function(RemoteMessage message) onForeground,
  }) async {
    _prefs = prefs;
    _client = client;
    _onOpen = onOpen;
    _onForeground = onForeground;
    enabled.value = prefs.getBool(_enabledKey) ?? true;
    if (_started) return;
    _started = true;

    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
      final messaging = FirebaseMessaging.instance;
      FirebaseMessaging.onMessage.listen((m) => _onForeground?.call(m));
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _onOpen?.call(m));
      // Token FCM clásico: el que aceptan "Enviar mensaje de prueba" de la
      // consola y el campo `token` de la API HTTP v1 (register()/FID es el
      // modelo nuevo; se puede migrar cuando el backend lo use).
      // ignore: deprecated_member_use
      messaging.onTokenRefresh.listen((token) {
        _token = token;
        registerWithBackend();
      });
      final initial = await messaging.getInitialMessage();
      if (initial != null) _onOpen?.call(initial);
    } catch (e) {
      debugPrint('[Push] Firebase no disponible: $e');
    }

    await _apply();
  }

  /// Interruptor de Configuración.
  static Future<void> setEnabled(bool value) async {
    enabled.value = value;
    await _prefs?.setBool(_enabledKey, value);
    await _apply();
  }

  /// Activadas: token + tema de versiones (o, sin push, la comprobación
  /// periódica). Desactivadas: nada de eso y el backend deja de enviar.
  static Future<void> _apply() async {
    if (!enabled.value) {
      DeviceChannel.cancelUpdateCheck();
      if (!_firebaseReady) return;
      await unregisterFromBackend();
      final messaging = FirebaseMessaging.instance;
      try {
        await messaging.setAutoInitEnabled(false);
        await messaging.unsubscribeFromTopic(updatesTopic);
        // ignore: deprecated_member_use
        await messaging.deleteToken();
      } catch (_) {}
      _token = null;
      return;
    }

    var pushWorks = false;
    if (_firebaseReady) {
      final messaging = FirebaseMessaging.instance;
      try {
        await messaging.setAutoInitEnabled(true);
        // ignore: deprecated_member_use
        _token = await messaging.getToken().timeout(const Duration(seconds: 30));
        if (_token != null) {
          await messaging
              .subscribeToTopic(updatesTopic)
              .timeout(const Duration(seconds: 30));
          pushWorks = true;
          await registerWithBackend();
        }
      } catch (e) {
        debugPrint('[Push] Sin token FCM: $e');
      }
    }
    // Nunca los dos avisos de versión a la vez.
    if (pushWorks) {
      DeviceChannel.cancelUpdateCheck();
    } else {
      DeviceChannel.scheduleUpdateCheck(AppConfig.updateManifestUrl);
    }
  }

  /// Envía el token al backend para que pueda mandar los avisos de
  /// `/api/notifications` como push. Requiere sesión; los errores (sin
  /// sesión o endpoint aún no creado) se ignoran.
  static Future<void> registerWithBackend() async {
    final token = _token;
    final client = _client;
    if (!enabled.value ||
        token == null ||
        client == null ||
        client.sessionCookie == null) {
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

  /// Al cerrar sesión o apagar las notificaciones: que el backend deje de
  /// enviar a este teléfono.
  static Future<void> unregisterFromBackend() async {
    final token = _token;
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
}
