import 'package:dio/dio.dart';

import '../config/app_config.dart';

/// Error de negocio devuelto por la API.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.details});

  final String message;
  final int? statusCode;
  final Map<String, dynamic>? details;

  @override
  String toString() => message;
}

/// Las llamadas remotas están desactivadas mientras no se define el
/// contenido de cada pantalla.
class RemoteCallsDisabledException extends ApiException {
  const RemoteCallsDisabledException([
    this.operation = 'la operación',
  ]) : super('Las llamadas al servidor están deshabilitadas para $operation.');

  final String operation;
}

/// Cliente HTTP de QvaTube.
///
/// - Base URL desde `AppConfig.apiBaseUrl`.
/// - Envía la cookie de sesión `qva_session` y la captura del `Set-Cookie`
///   (la API de autenticación usa cookie HttpOnly, ver `securitySchemes` en
///   doc/openapi.json).
class ApiClient {
  ApiClient({
    Dio? dio,
    String baseUrl = AppConfig.apiBaseUrl,
    this.remoteCallsEnabled = AppConfig.remoteCallsEnabled,
    void Function(String? cookie)? onSessionCookie,
  }) {
    _dio = dio ??
        Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 30),
            contentType: Headers.jsonContentType,
            responseType: ResponseType.json,
            // La API no usa CORS en el móvil, pero accept cookies igualmente.
            headers: const {'Accept': 'application/json'},
          ),
        );
    _cookieInterceptor = SessionCookieInterceptor(
      onCookie: (cookie) => onSessionCookie?.call(cookie),
    );
    _dio.interceptors.add(_cookieInterceptor);
  }

  late final Dio _dio;
  /// Si es `false` ninguna petición sale del dispositivo.
  final bool remoteCallsEnabled;
  late final SessionCookieInterceptor _cookieInterceptor;

  Dio get dio => _dio;

  /// Cookie de sesión actual (`qva_session`).
  String? get sessionCookie => _cookieInterceptor.cookie;

  set sessionCookie(String? value) {
    _cookieInterceptor.cookie = value;
    _cookieInterceptor.onCookie?.call(value);
  }

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
    String operation = 'la consulta',
  }) {
    return _send(
      () => _dio.get<dynamic>(path, queryParameters: query, cancelToken: cancelToken),
      operation: operation,
    );
  }

  Future<Response<dynamic>> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
    String operation = 'la operación',
  }) {
    return _send(
      () => _dio.post<dynamic>(path, data: body, queryParameters: query, cancelToken: cancelToken),
      operation: operation,
    );
  }

  Future<Response<dynamic>> delete(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
    String operation = 'la operación',
  }) {
    return _send(
      () => _dio.delete<dynamic>(path, data: body, queryParameters: query, cancelToken: cancelToken),
      operation: operation,
    );
  }

  Future<Response<dynamic>> postForm(
    String path, {
    required FormData formData,
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
    String operation = 'la operación',
  }) {
    return _send(
      () => _dio.post<dynamic>(path, data: formData, queryParameters: query, cancelToken: cancelToken),
      operation: operation,
    );
  }

  Future<Response<dynamic>> _send(
    Future<Response<dynamic>> Function() request, {
    String operation = 'la operación',
  }) async {
    if (!remoteCallsEnabled) {
      throw RemoteCallsDisabledException(operation);
    }
    try {
      return await request();
    } on DioException catch (error) {
      throw ApiException(
        _describe(error),
        statusCode: error.response?.statusCode,
        details: error.response?.data is Map
            ? Map<String, dynamic>.from(error.response!.data as Map)
            : null,
      );
    }
  }

  String _describe(DioException error) {
    final status = error.response?.statusCode;
    final data = error.response?.data;
    if (data is Map && data['error'] is String) {
      return data['error'] as String;
    }
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'La conexión tardó demasiado. Inténtalo de nuevo.',
      DioExceptionType.connectionError =>
        'Sin conexión con el servidor de QvaTube.',
      DioExceptionType.badCertificate =>
        'Certificado del servidor no válido.',
      _ => status == null
          ? 'No se pudo completar la operación.'
          : 'Error $status: ${error.message ?? 'operación fallida'}',
    };
  }
}

/// Captura la cookie de sesión `qva_session` y la reenvía en cada petición.
class SessionCookieInterceptor extends Interceptor {
  SessionCookieInterceptor({this.onCookie});

  /// Se invoca cada vez que el servidor renueva la cookie de sesión.
  final void Function(String? cookie)? onCookie;

  String? cookie;

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final setCookie = response.headers['set-cookie'];
    if (setCookie != null && setCookie.isNotEmpty) {
      for (final raw in setCookie) {
        final parts = raw.split(';').first.split('=');
        if (parts.length == 2 && parts.first.trim() == 'qva_session') {
          final value = parts.last.trim();
          if (value.isNotEmpty) {
            cookie = value;
            onCookie?.call(value);
          }
        }
      }
    }
    handler.next(response);
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final current = cookie;
    if (current != null && current.isNotEmpty) {
      options.headers['cookie'] = 'qva_session=$current';
    }
    handler.next(options);
  }
}
