import '../../../core/network/api_client.dart';
import '../domain/auth_models.dart';
import 'auth_api.dart';

/// Repositorio de autenticación.
///
/// Envuelve los endpoints de `doc/openapi.json` (tag "Autenticación") y
/// normaliza los errores que devuelve la API (`{"error": "..."}`).
class AuthRepository {
  const AuthRepository(this._api, this._client);

  final AuthApi _api;
  final ApiClient _client;

  /// Cookie de sesión actual (`qva_session`).
  String? get sessionCookie => _client.sessionCookie;

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

  Future<void> logout() async {
    await _api.logout();
    _client.sessionCookie = null;
  }

  Future<AuthUser> updateName(String displayName) async {
    final data = await _api.updateName(displayName);
    return AuthUser.fromJson(data);
  }

  Future<AuthUser> uploadAvatar({
    required String filePath,
    required String fileName,
  }) async {
    final data = await _api.uploadAvatar(filePath: filePath, fileName: fileName);
    return AuthUser.fromJson(data);
  }

  Future<void> deleteAvatar() async {
    await _api.deleteAvatar();
  }

  Future<void> requestPasswordReset(String email) =>
      _api.forgotPassword(email: email);

  /// Devuelve el token de recuperación (`{"token": "..."}`).
  Future<String> requestPasswordResetToken(String email) async {
    final data = await _api.forgotPassword(email: email);
    return (data['token'] ?? '') as String;
  }

  Future<void> resetPassword({
    required String token,
    required String code,
    required String newPassword,
  }) => _api.resetPassword(token: token, code: code, newPassword: newPassword);

  Future<TelegramLinkCode> createLinkCode() async {
    final data = await _api.createLinkCode();
    return TelegramLinkCode.fromJson(data);
  }

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
    return 'Las llamadas al servidor están deshabilitadas para '
        '${error.operation}.';
  }
  if (error is ApiException) {
    return error.message;
  }
  return 'Ocurrió un error inesperado. Inténtalo de nuevo.';
}
