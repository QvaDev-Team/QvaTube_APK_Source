import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/endpoints/endpoints.dart';

/// Cliente de los endpoints de autenticación.
///
/// Rutas y cuerpos verificados contra `doc/openapi.json`
/// (tag "Autenticación", securityScheme `userCookie` = cookie `qva_session`).
class AuthApi {
  const AuthApi(this._client);

  final ApiClient _client;

  /// POST /api/auth/login
  /// body: { email (email, required), password (required) }
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _client.post(
      Endpoints.auth.login,
      body: <String, dynamic>{'email': email, 'password': password},
      operation: 'el inicio de sesión',
    );
    return _asMap(response.data);
  }

  /// POST /api/auth/register
  /// body: { email (required), password (required), display_name, invite_code }
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String? displayName,
    String? inviteCode,
  }) async {
    final body = <String, dynamic>{'email': email, 'password': password};
    if (displayName != null && displayName.isNotEmpty) {
      body['display_name'] = displayName;
    }
    if (inviteCode != null && inviteCode.isNotEmpty) {
      body['invite_code'] = inviteCode;
    }
    final response = await _client.post(
      Endpoints.auth.register,
      body: body,
      operation: 'el registro de la cuenta',
    );
    return _asMap(response.data);
  }

  /// POST /api/auth/logout
  Future<void> logout() async {
    await _client.post(Endpoints.auth.logout, operation: 'el cierre de sesión');
  }

  /// GET /api/auth/me
  Future<Map<String, dynamic>> me() async {
    final response = await _client.get(
      Endpoints.auth.me,
      operation: 'la carga del perfil',
    );
    return _asMap(response.data);
  }

  /// POST /api/auth/update-name
  /// body: { display_name (required) }
  Future<Map<String, dynamic>> updateName(String displayName) async {
    final response = await _client.post(
      Endpoints.auth.updateName,
      body: <String, dynamic>{'display_name': displayName},
      operation: 'la actualización del nombre',
    );
    return _asMap(response.data);
  }

  /// POST /api/auth/avatar (multipart/form-data)
  /// body: `{ photo: <binary> }` (required). El servidor lee el campo
  /// `photo` (web/routes/avatar.py, igual que la web): con otro nombre
  /// respondía "Falta la imagen".
  Future<Map<String, dynamic>> uploadAvatar({
    required String filePath,
    required String fileName,
  }) async {
    final formData = FormData.fromMap(<String, dynamic>{
      'photo': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final response = await _client.postForm(
      Endpoints.auth.avatar,
      formData: formData,
      operation: 'la subida del avatar',
    );
    return _asMap(response.data);
  }

  /// DELETE /api/auth/avatar
  Future<void> deleteAvatar() async {
    await _client.delete(
      Endpoints.auth.avatar,
      operation: 'el borrado del avatar',
    );
  }

  /// POST /api/auth/forgot-password
  /// body: { email (required) }
  Future<Map<String, dynamic>> forgotPassword({required String email}) async {
    final response = await _client.post(
      Endpoints.auth.forgotPassword,
      body: <String, dynamic>{'email': email},
      operation: 'la recuperación de contraseña',
    );
    return _asMap(response.data);
  }

  /// POST /api/auth/reset-password
  /// body: { token (required), code (required), new_password (required, min 8) }
  Future<Map<String, dynamic>> resetPassword({
    required String token,
    required String code,
    required String newPassword,
  }) async {
    final response = await _client.post(
      Endpoints.auth.resetPassword,
      body: <String, dynamic>{
        'token': token,
        'code': code,
        'new_password': newPassword,
      },
      operation: 'el restablecimiento de contraseña',
    );
    return _asMap(response.data);
  }

  /// POST /api/auth/link-code
  /// Genera el código corto para vincular la cuenta con Telegram.
  Future<Map<String, dynamic>> createLinkCode() async {
    final response = await _client.post(
      Endpoints.auth.linkCode,
      operation: 'el código de vinculación',
    );
    return _asMap(response.data);
  }

  /// POST /api/auth/verify/start
  /// Inicia la verificación por Telegram (devuelve token y deep link).
  Future<Map<String, dynamic>> startTelegramVerification() async {
    final response = await _client.post(
      Endpoints.auth.verifyStart,
      operation: 'la verificación por Telegram',
    );
    return _asMap(response.data);
  }

  /// POST /api/auth/verify/confirm
  /// body: { token (required), code (required) }
  Future<Map<String, dynamic>> confirmTelegramVerification({
    required String token,
    required String code,
  }) async {
    final response = await _client.post(
      Endpoints.auth.verifyConfirm,
      body: <String, dynamic>{'token': token, 'code': code},
      operation: 'la confirmación del código',
    );
    return _asMap(response.data);
  }

  /// GET /api/auth/verify/status
  /// Consulta el estado de la verificación en curso.
  Future<Map<String, dynamic>> telegramVerificationStatus({String? token}) async {
    final response = await _client.get(
      Endpoints.auth.verifyStatus,
      query: token == null ? null : <String, dynamic>{'token': token},
      operation: 'el estado de la verificación',
    );
    return _asMap(response.data);
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{};
  }
}
