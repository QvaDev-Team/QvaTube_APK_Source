import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/platform/device_channel.dart';
import '../../core/storage/download_storage.dart';
import 'legacy_downloads.dart';
import 'tdlib/td_client.dart';
import 'tdlib/td_library.dart';

/// Etapas de la conexión con Telegram dentro de QvaTube.
enum TgStage {
  /// Arquitectura no soportada o APK compilada sin las claves de Telegram.
  unavailable,

  /// Nunca conectado: hay que descargar el componente e iniciar sesión.
  disconnected,

  /// Descargando el componente de Telegram (TDLib).
  installing,

  /// Arrancando TDLib.
  starting,
  waitPhone,
  waitCode,
  waitPassword,
  ready,
  error,
}

/// Usuario de Telegram conectado.
@immutable
class TgUser {
  const TgUser({required this.id, required this.name, required this.phone});

  final int id;
  final String name;
  final String phone;
}

/// Sesión de Telegram del usuario dentro de QvaTube (TDLib).
///
/// Solo se usa para leer el chat del bot de QvaTube y descargar los
/// archivos que el bot envía. La sesión aparece en Telegram → Ajustes →
/// Dispositivos y se puede cerrar desde ahí o desde la app.
class TelegramService extends ChangeNotifier {
  TelegramService._();

  static final TelegramService instance = TelegramService._();

  // Claves de la aplicación de Telegram: se inyectan al compilar
  // (--dart-define desde los secretos del CI), nunca van en el código.
  static const int _apiId = int.fromEnvironment('TELEGRAM_API_ID');
  static const String _apiHash = String.fromEnvironment('TELEGRAM_API_HASH');

  static const String _connectedKey = 'qvatube.telegram_connected';
  static const String _dbKey = 'qvatube.telegram_db_key';

  /// `true` si esta APK puede usar Telegram (claves y arquitectura).
  static bool get isAvailable =>
      _apiId != 0 && _apiHash.isNotEmpty && TdLibrary.isSupported;

  TdClient? _client;
  StreamSubscription<Map<String, dynamic>>? _sub;
  SharedPreferences? _prefs;

  TgStage _stage = TgStage.disconnected;
  double _progress = 0;
  String? _error;
  String? _passwordHint;
  String? _codeHint;
  TgUser? _user;

  TgStage get stage => isAvailable ? _stage : TgStage.unavailable;
  double get progress => _progress;
  String? get error => _error;
  String? get passwordHint => _passwordHint;

  /// Dónde llegó el código (app de Telegram, SMS…).
  String? get codeHint => _codeHint;
  TgUser? get user => _user;
  bool get isReady => stage == TgStage.ready;

  /// `true` cuando TDLib está conectado a los servidores de Telegram
  /// (`connectionStateReady`). Al abrir la app puede tardar en conectar
  /// (en algunas redes, minutos): mientras tanto solo sirve lo guardado en
  /// el teléfono.
  final ValueNotifier<bool> online = ValueNotifier(false);

  /// Cliente de TDLib (solo con sesión iniciada).
  TdClient? get client => isReady ? _client : null;

  /// Al abrir la app: si el usuario ya había conectado Telegram, retoma la
  /// sesión sin pedirle nada.
  Future<void> restore(SharedPreferences prefs) async {
    _prefs = prefs;
    if (!isAvailable || prefs.getBool(_connectedKey) != true) return;
    if (!await TdLibrary.isInstalled()) return;
    await _start();
  }

  /// "Conectar Telegram": descarga el componente si hace falta y arranca.
  Future<void> connect(SharedPreferences prefs) async {
    _prefs = prefs;
    if (!isAvailable || _client != null) return;
    _error = null;
    try {
      if (!await TdLibrary.isInstalled()) {
        _set(TgStage.installing);
        await TdLibrary.install(
          onProgress: (p) {
            _progress = p;
            notifyListeners();
          },
        );
      }
      await _start();
    } catch (e) {
      _fail(_describe(e));
    }
  }

  Future<void> _start() async {
    _set(TgStage.starting);
    final path = await TdLibrary.install();
    final client = await TdClient.start(path);
    _client = client;
    _sub = client.updates.listen(_onUpdate);
  }

  Future<void> sendPhone(String phone) => _authStep({
    '@type': 'setAuthenticationPhoneNumber',
    'phone_number': phone.trim(),
  });

  Future<void> sendCode(String code) =>
      _authStep({'@type': 'checkAuthenticationCode', 'code': code.trim()});

  Future<void> sendPassword(String password) =>
      _authStep({'@type': 'checkAuthenticationPassword', 'password': password});

  Future<void> _authStep(Map<String, dynamic> request) async {
    final client = _client;
    if (client == null) return;
    _error = null;
    notifyListeners();
    try {
      await client.send(request);
    } catch (e) {
      _error = _describe(e);
      notifyListeners();
    }
  }

  /// Cierra la sesión de Telegram en QvaTube (y en la lista de dispositivos).
  Future<void> disconnect() async {
    await _prefs?.setBool(_connectedKey, false);
    final client = _client;
    if (client != null) {
      try {
        await client.send({'@type': 'logOut'});
      } catch (_) {}
    }
    _user = null;
    _set(TgStage.disconnected);
  }

  Future<void> _onUpdate(Map<String, dynamic> update) async {
    if (update['@type'] == 'updateConnectionState') {
      online.value =
          (update['state'] as Map?)?['@type'] == 'connectionStateReady';
      return;
    }
    if (update['@type'] != 'updateAuthorizationState') return;
    final state = update['authorization_state'] as Map<String, dynamic>;
    switch (state['@type']) {
      case 'authorizationStateWaitTdlibParameters':
        await _sendParameters();
      case 'authorizationStateWaitPhoneNumber':
        _set(TgStage.waitPhone);
      case 'authorizationStateWaitCode':
        _codeHint = _codeType((state['code_info'] as Map?)?['type'] as Map?);
        _set(TgStage.waitCode);
      case 'authorizationStateWaitPassword':
        _passwordHint = state['password_hint']?.toString();
        _set(TgStage.waitPassword);
      case 'authorizationStateReady':
        await _prefs?.setBool(_connectedKey, true);
        await _loadMe();
        _set(TgStage.ready);
      case 'authorizationStateWaitEmailAddress':
      case 'authorizationStateWaitEmailCode':
      case 'authorizationStateWaitRegistration':
      case 'authorizationStateWaitOtherDeviceConfirmation':
        _fail(
          'Esta cuenta necesita un paso que solo se puede hacer en la app de '
          'Telegram. Inicia sesión allí primero y vuelve a intentarlo.',
        );
      case 'authorizationStateClosed':
        online.value = false;
        await _sub?.cancel();
        _sub = null;
        _client = null;
        if (_stage != TgStage.error) _set(TgStage.disconnected);
    }
  }

  Future<void> _sendParameters() async {
    final client = _client;
    if (client == null) return;
    final base = '${await DeviceChannel.cacheDirectory()}/tdlib';
    // Los archivos van donde el usuario eligió (interna o SD); la base de
    // datos siempre en la memoria interna.
    final filesRoot = await DownloadStorage.root();
    DownloadStorage.telegramRoot = filesRoot;
    // Lo descargado en la otra ubicación se queda donde está y se sigue
    // viendo (TDLib solo conoce la carpeta actual).
    await DownloadStorage.addKnownRoot(filesRoot);
    await LegacyDownloads.init(
      currentRoot: filesRoot,
      otherRoots: await DownloadStorage.knownRoots(),
    );
    final info = await PackageInfo.fromPlatform();
    try {
      await client.send({
        '@type': 'setTdlibParameters',
        'use_test_dc': false,
        'database_directory': '$base/db',
        'files_directory': DownloadStorage.telegramFilesDir(filesRoot),
        'database_encryption_key': _databaseKey(),
        'use_file_database': true,
        'use_chat_info_database': true,
        'use_message_database': true,
        'use_secret_chats': false,
        'api_id': _apiId,
        'api_hash': _apiHash,
        'system_language_code': 'es',
        'device_model': 'QvaTube',
        'system_version': Platform.operatingSystemVersion,
        'application_version': info.version,
      });
    } catch (e) {
      _fail(_describe(e));
    }
  }

  /// Clave aleatoria (base64) que cifra la base de datos local de TDLib.
  String _databaseKey() {
    final prefs = _prefs;
    final saved = prefs?.getString(_dbKey);
    if (saved != null && saved.isNotEmpty) return saved;
    final rnd = Random.secure();
    final key = base64Encode(List<int>.generate(32, (_) => rnd.nextInt(256)));
    prefs?.setString(_dbKey, key);
    return key;
  }

  Future<void> _loadMe() async {
    try {
      final me = await _client!.send({'@type': 'getMe'});
      final name = [
        me['first_name'],
        me['last_name'],
      ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
      _user = TgUser(
        id: (me['id'] as num).toInt(),
        name: name,
        phone: me['phone_number']?.toString() ?? '',
      );
    } catch (_) {}
  }

  static String _codeType(Map? type) => switch (type?['@type']) {
    'authenticationCodeTypeTelegramMessage' =>
      'Te enviamos el código por Telegram (en tu otra sesión abierta).',
    'authenticationCodeTypeSms' => 'Te enviamos el código por SMS.',
    'authenticationCodeTypeCall' ||
    'authenticationCodeTypeFlashCall' ||
    'authenticationCodeTypeMissedCall' => 'Recibirás el código en una llamada.',
    _ => 'Escribe el código que te envió Telegram.',
  };

  /// Mensajes de error de Telegram en lenguaje claro.
  static String _describe(Object e) {
    if (e is TdError) {
      final m = e.message.toUpperCase();
      if (m.contains('PHONE_NUMBER_INVALID')) {
        return 'Ese número no es válido. Escríbelo con el código del país (+53…).';
      }
      if (m.contains('PHONE_CODE_INVALID')) return 'El código no es correcto.';
      if (m.contains('PHONE_CODE_EXPIRED')) {
        return 'El código caducó. Vuelve a pedir uno nuevo.';
      }
      if (m.contains('PASSWORD_HASH_INVALID')) {
        return 'La contraseña no es correcta.';
      }
      if (m.contains('FLOOD_WAIT') || e.code == 429) {
        return 'Demasiados intentos. Espera unos minutos y vuelve a probar.';
      }
      return 'Telegram: ${e.message}';
    }
    if (e is UnsupportedError) {
      return e.message ?? 'No disponible en este dispositivo.';
    }
    if (e is StateError) return e.message;
    return 'No se pudo conectar con Telegram. Revisa tu conexión.';
  }

  void _set(TgStage stage) {
    _stage = stage;
    notifyListeners();
  }

  void _fail(String message) {
    _error = message;
    _set(TgStage.error);
  }
}
