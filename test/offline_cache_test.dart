import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qvatube_apk/core/network/api_client.dart';
import 'package:qvatube_apk/core/network/response_cache.dart';

/// Servidor falso: responde con [respuesta] o, si [sinRed], falla como un
/// teléfono sin conexión.
class _ServidorFalso implements HttpClientAdapter {
  bool sinRed = false;
  int llamadas = 0;
  Map<String, dynamic> respuesta = {'items': <Object>[], 'page': 1};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    llamadas++;
    if (sinRed) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'Failed host lookup',
        error: const SocketException('Failed host lookup'),
      );
    }
    return ResponseBody.fromString(
      jsonEncode(respuesta),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory dir;
  late _ServidorFalso servidor;
  late ApiClient client;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('qva_cache_test');
    servidor = _ServidorFalso();
    final dio = Dio(BaseOptions(baseUrl: 'https://qvatube.test'))
      ..httpClientAdapter = servidor;
    client = ApiClient(dio: dio, responseCache: ResponseCache(() async => dir));
    OfflineStatus.markOnline();
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  /// Espera a que se escriba la copia en disco (se guarda sin bloquear).
  Future<void> esperarGuardado() async {
    for (var i = 0; i < 50; i++) {
      if (dir.listSync().any((f) => f.path.endsWith('.json'))) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  const query = {'cat': 'movie', 'page': 1, 'limit': 30, 'sort': 'date'};

  test('sin conexión devuelve el catálogo guardado de la sección', () async {
    servidor.respuesta = {
      'items': [
        {'title': 'Cars 3'},
      ],
      'page': 1,
    };
    final online = await client.get('/api/movies', query: query);
    expect(online.extra['fromCache'], isNull);
    await esperarGuardado();

    servidor.sinRed = true;
    final offline = await client.get('/api/movies', query: query);
    expect(offline.extra['fromCache'], isTrue);
    expect((offline.data as Map)['items'][0]['title'], 'Cars 3');
    expect(OfflineStatus.offline.value, isTrue);
  });

  test('al volver la conexión se quita el aviso y se usa la red', () async {
    await client.get('/api/movies', query: query);
    await esperarGuardado();
    servidor.sinRed = true;
    await client.get('/api/movies', query: query);
    expect(OfflineStatus.offline.value, isTrue);

    servidor.sinRed = false;
    servidor.respuesta = {'items': <Object>[], 'page': 1, 'nuevo': true};
    final r = await client.get('/api/movies', query: query);
    expect(r.extra['fromCache'], isNull);
    expect((r.data as Map)['nuevo'], isTrue);
    expect(OfflineStatus.offline.value, isFalse);
  });

  test('sin copia guardada, el error sin red se sigue lanzando', () async {
    servidor.sinRed = true;
    await expectLater(
      client.get('/api/movies', query: query),
      throwsA(isA<ApiException>().having((e) => e.network, 'network', isTrue)),
    );
  });

  test('otra página u otro filtro no reutiliza la copia de la primera', () async {
    await client.get('/api/movies', query: query);
    await esperarGuardado();
    servidor.sinRed = true;
    await expectLater(
      client.get('/api/movies', query: {...query, 'page': 2}),
      throwsA(isA<ApiException>()),
    );
  });

  test('los datos de una cuenta no se muestran a otra', () async {
    client.sessionCookie = 'cuenta-a';
    await client.get('/api/favorites');
    await esperarGuardado();

    client.sessionCookie = 'cuenta-b';
    servidor.sinRed = true;
    await expectLater(
      client.get('/api/favorites'),
      throwsA(isA<ApiException>()),
    );
  });

  test('no se guardan las rutas de sesión ni las de reproducción', () {
    expect(ResponseCache.isCacheable('/api/movies'), isTrue);
    expect(ResponseCache.isCacheable('/api/tv/channels'), isTrue);
    expect(ResponseCache.isCacheable('/api/auth/me'), isFalse);
    expect(ResponseCache.isCacheable('/api/tv/viewers'), isFalse);
    expect(ResponseCache.isCacheable('/watch/1/2'), isFalse);
  });
}
