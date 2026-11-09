import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qvatube_apk/core/config/app_config.dart';
import 'package:qvatube_apk/core/network/api_client.dart';
import 'package:qvatube_apk/core/network/api_providers.dart';
import 'package:qvatube_apk/core/storage/app_preferences.dart';
import 'package:qvatube_apk/features/auth/presentation/providers/auth_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `GET /api/auth/me` simulado: responde con [onMe].
ProviderContainer _container(
  SharedPreferences prefs,
  void Function(RequestOptions, RequestInterceptorHandler) onMe,
) {
  final store = SessionStore(prefs);
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test/'))
    ..interceptors.add(InterceptorsWrapper(onRequest: onMe));
  final client = ApiClient(dio: dio, onSessionCookie: store.save)
    ..sessionCookie = store.cookie;
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      apiClientProvider.overrideWithValue(client),
    ],
  );
}

void main() {
  const savedUser =
      '{"id":"7","email":"a@b.c","display_name":"Ana","telegram_linked":true}';

  setUp(() {
    SharedPreferences.setMockInitialValues({
      AppConfig.sessionCookieKey: 'qva_session=abc',
      AppConfig.sessionUserKey: savedUser,
    });
  });

  test('con la conexión agotada se conserva la sesión guardada', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = _container(prefs, (options, handler) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        ),
      );
    });
    addTearDown(container.dispose);

    await container.read(authControllerProvider.notifier).restoreSession();
    final state = container.read(authControllerProvider);

    expect(state.status, AuthStatus.authenticated);
    expect(state.user?.name, 'Ana');
    expect(state.user?.telegramLinked, isTrue);
    expect(state.error, isNull);
    expect(prefs.getString(AppConfig.sessionCookieKey), 'qva_session=abc');
  });

  test('un 401 cierra la sesión y borra lo guardado', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = _container(prefs, (options, handler) {
      handler.reject(
        DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 401),
          type: DioExceptionType.badResponse,
        ),
      );
    });
    addTearDown(container.dispose);

    await container.read(authControllerProvider.notifier).restoreSession();
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(authControllerProvider).status,
      AuthStatus.unauthenticated,
    );
    expect(prefs.getString(AppConfig.sessionCookieKey), isNull);
    expect(prefs.getString(AppConfig.sessionUserKey), isNull);
  });

  test('con red, guarda el usuario que devuelve el servidor', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = _container(prefs, (options, handler) {
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'user': {'id': 7, 'display_name': 'Ana 2', 'telegram_linked': true},
          },
        ),
      );
    });
    addTearDown(container.dispose);

    await container.read(authControllerProvider.notifier).restoreSession();
    await Future<void>.delayed(Duration.zero);

    expect(container.read(authControllerProvider).user?.name, 'Ana 2');
    expect(prefs.getString(AppConfig.sessionUserKey), contains('Ana 2'));
  });
}
