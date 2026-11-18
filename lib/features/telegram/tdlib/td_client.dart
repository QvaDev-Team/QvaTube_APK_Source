import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

/// Error devuelto por TDLib (`{"@type":"error","code":…,"message":…}`).
class TdError implements Exception {
  const TdError(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => 'TdError($code): $message';
}

// Interfaz JSON de TDLib (td_json_client.h, TDLib 1.8):
//   int         td_create_client_id();
//   void        td_send(int client_id, const char *request);
//   const char *td_receive(double timeout);
//   const char *td_execute(const char *request);
typedef _CreateC = Int32 Function();
typedef _CreateD = int Function();
typedef _SendC = Void Function(Int32, Pointer<Utf8>);
typedef _SendD = void Function(int, Pointer<Utf8>);
typedef _ReceiveC = Pointer<Utf8> Function(Double);
typedef _ReceiveD = Pointer<Utf8> Function(double);
typedef _ExecuteC = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _ExecuteD = Pointer<Utf8> Function(Pointer<Utf8>);

class _TdFunctions {
  _TdFunctions(DynamicLibrary lib)
    : create = lib.lookupFunction<_CreateC, _CreateD>('td_create_client_id'),
      send = lib.lookupFunction<_SendC, _SendD>('td_send'),
      receive = lib.lookupFunction<_ReceiveC, _ReceiveD>('td_receive'),
      execute = lib.lookupFunction<_ExecuteC, _ExecuteD>('td_execute');

  final _CreateD create;
  final _SendD send;
  final _ReceiveD receive;
  final _ExecuteD execute;
}

/// Cliente de TDLib. `td_receive` bloquea, así que se llama en un isolate
/// aparte que reenvía cada respuesta; `td_send` es seguro desde aquí.
class TdClient {
  TdClient._(this._fns, this._clientId, this._isolate, this._port) {
    _port.listen(_onMessage);
  }

  final _TdFunctions _fns;
  final int _clientId;
  final Isolate _isolate;
  final ReceivePort _port;

  final _updates = StreamController<Map<String, dynamic>>.broadcast();
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  int _nextExtra = 0;
  bool _closed = false;

  /// Actualizaciones de TDLib (`updateAuthorizationState`, `updateFile`…).
  Stream<Map<String, dynamic>> get updates => _updates.stream;

  /// Carga la librería en [libraryPath] y crea un cliente.
  static Future<TdClient> start(String libraryPath) async {
    final fns = _TdFunctions(DynamicLibrary.open(libraryPath));
    _executeSync(fns, {
      '@type': 'setLogVerbosityLevel',
      'new_verbosity_level': 1,
    });
    final clientId = fns.create();
    final port = ReceivePort();
    final isolate = await Isolate.spawn(_receiveLoop, [
      libraryPath,
      port.sendPort,
    ], debugName: 'tdlib-receive');
    final client = TdClient._(fns, clientId, isolate, port);
    // TDLib no hace nada hasta recibir la primera petición.
    client.sendRaw({'@type': 'getOption', 'name': 'version'});
    return client;
  }

  static Map<String, dynamic>? _executeSync(
    _TdFunctions fns,
    Map<String, dynamic> request,
  ) {
    final req = jsonEncode(request).toNativeUtf8();
    try {
      final res = fns.execute(req);
      if (res == nullptr) return null;
      return jsonDecode(res.toDartString()) as Map<String, dynamic>;
    } finally {
      malloc.free(req);
    }
  }

  /// Envía [request] sin esperar respuesta.
  void sendRaw(Map<String, dynamic> request) {
    if (_closed) return;
    final req = jsonEncode(request).toNativeUtf8();
    try {
      _fns.send(_clientId, req);
    } finally {
      malloc.free(req);
    }
  }

  /// Envía [request] y espera su respuesta. Lanza [TdError] si TDLib
  /// responde con un error.
  Future<Map<String, dynamic>> send(
    Map<String, dynamic> request, {
    Duration timeout = const Duration(seconds: 60),
  }) {
    final extra = 'q${_nextExtra++}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[extra] = completer;
    sendRaw({...request, '@extra': extra});
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(extra);
        throw TimeoutException('Telegram no respondió a ${request['@type']}');
      },
    );
  }

  void _onMessage(dynamic message) {
    if (message is! String) return;
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (data['@client_id'] != null && data['@client_id'] != _clientId) return;
    final extra = data['@extra'];
    if (extra is String && _pending.containsKey(extra)) {
      final completer = _pending.remove(extra)!;
      if (data['@type'] == 'error') {
        completer.completeError(
          TdError(
            (data['code'] as num?)?.toInt() ?? 0,
            data['message']?.toString() ?? 'Error de Telegram',
          ),
        );
      } else {
        completer.complete(data);
      }
      return;
    }
    _updates.add(data);
    if (data['@type'] == 'updateAuthorizationState' &&
        (data['authorization_state'] as Map?)?['@type'] ==
            'authorizationStateClosed') {
      _dispose();
    }
  }

  /// Cierra el cliente (TDLib guarda su base de datos antes de terminar).
  void close() => sendRaw({'@type': 'close'});

  void _dispose() {
    if (_closed) return;
    _closed = true;
    for (final c in _pending.values) {
      c.completeError(const TdError(500, 'Telegram se cerró'));
    }
    _pending.clear();
    _isolate.kill(priority: Isolate.immediate);
    _port.close();
    _updates.close();
  }
}

/// Bucle del isolate: lee respuestas de TDLib y las manda al principal.
void _receiveLoop(List<Object> args) {
  final fns = _TdFunctions(DynamicLibrary.open(args[0] as String));
  final out = args[1] as SendPort;
  while (true) {
    final res = fns.receive(1.0);
    if (res != nullptr) out.send(res.toDartString());
  }
}
