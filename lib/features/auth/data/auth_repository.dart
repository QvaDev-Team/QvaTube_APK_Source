import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../domain/auth_models.dart';
import 'auth_api.dart';

/// Repositorio de autenticación.
///
/// Envuelve los endpoints de `doc/openapi.json`. Mientras
/// `AppConfig.remoteCallsEnabled` sea `false` ninguna petición sale del
/// dispositivo: se lanza [RemoteCallsDisabledException] y la UI informa de que
/// falta definir el contenido de cada pantalla.
class AuthRepository {
  const AuthRepository(this._api);

  final AuthApi _api;

  bool get isRemoteEnabled => AppConfig.remoteCallsEnabled;

  Future<AuthUser> login({
    required String email,
    required String password,
  }) async {
    final data = await _api.login(email: email, password: password);
    return AuthUser.fromJson(data);
  }

  Future<AuthUser> register({
    required String email,
    required String password,
    String? displayName,
    String? inviteCode,
  }) async {
    final data = await _api.register(
      email: email,
      password: password,
      displayName: displayName,
      inviteCode: inviteCode,
    );
    return AuthUser.fromJson(data);
  }

  Future<AuthUser> me() async {
    final data = await _api.me();
    return AuthUser.fromJson(data);
  }

  Future<void> logout() => _api.logout();

  Future<AuthUser> updateName(String displayName) async {
    final data = await _api.updateName(displayName);
    return AuthUser.fromJson(data);
  }

  Future<void> requestPasswordReset(String email) =>
      _api.forgotPassword(email: email);

  Future<void> resetPassword({
    required String token,
    required String code,
    required String newPassword,
  }) => _api.resetPassword(token: token, code: code, newPassword: newPassword);

  Future<TelegramVerification> startTelegramVerification() async {
    final data = await _api.startTelegramVerification();
    return TelegramVerification.fromJson(data);
  }

  Future<TelegramVerification> confirmTelegramVerification({
    required String token,
    required String code,
  }) async {
    final data = await _api.confirmTelegramVerification(token: token, code: code);
    return TelegramVerification.fromJson(data);
  }

  Future<TelegramVerification> telegramVerificationStatus({String? token}) async {
    final data = await _api.telegramVerificationStatus(token: token);
    return TelegramVerification.fromJson(data);
  }
}

/// Mensajes de error ya traducidos para la UI.
String authErrorMessage(Object error) {
  if (error is RemoteCallsDisabledException) {
    return 'Conexión con la API pendiente de definir para ${error.operation}.';
  }
  if (error is ApiException) {
    return error.message;
  }
  return 'Ocurrió un error inesperado. Inténtalo de nuevo.';
}
