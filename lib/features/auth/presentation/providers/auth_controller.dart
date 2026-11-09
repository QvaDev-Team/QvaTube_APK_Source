import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/push/push_service.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/storage/app_preferences.dart';
import '../../data/auth_repository.dart';
import '../../domain/auth_models.dart';
import 'auth_providers.dart';

enum AuthStatus {
  /// Estado inicial: todavía no se ha comprobado la sesión.
  unknown,

  /// El usuario exploró como invitado.
  guest,

  /// Autenticado con email y contraseña.
  authenticated,

  /// Sin sesión activa.
  unauthenticated,
}

/// Estado global de autenticación.
@immutable
class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.isWorking = false,
    this.error,
    this.info,
  });

  final AuthStatus status;
  final AuthUser? user;
  final bool isWorking;
  final String? error;
  final String? info;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  /// Sesión iniciada pero sin vincular Telegram: la verificación es
  /// obligatoria antes de usar la app (igual que el gate de la web).
  bool get needsTelegramVerification =>
      isAuthenticated && user != null && !user!.telegramLinked;

  bool get isGuest => status == AuthStatus.guest;

  /// Permite entrar a la app como invitado o con sesión activa.
  bool get canBrowse => isAuthenticated || isGuest;

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    bool? isWorking,
    String? error,
    String? info,
    bool clearError = false,
    bool clearInfo = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      isWorking: isWorking ?? this.isWorking,
      error: clearError ? null : (error ?? this.error),
      info: clearInfo ? null : (info ?? this.info),
    );
  }
}

/// Controlador del flujo de autenticación.
class AuthController extends Notifier<AuthState> {
  Timer? _retryTimer;
  int _retryAttempt = 0;

  @override
  AuthState build() {
    ref.onDispose(() => _retryTimer?.cancel());
    // El último usuario conocido se guarda en el teléfono para poder entrar
    // con mala conexión; se borra al quedar sin sesión.
    listenSelf((previous, next) {
      if (previous?.user == next.user && previous?.status == next.status) {
        return;
      }
      final store = ref.read(sessionStoreProvider);
      if (next.isAuthenticated && next.user != null) {
        store.saveUser(next.user!.toJson());
      } else if (next.status == AuthStatus.unauthenticated) {
        store.saveUser(null);
      }
    });
    return const AuthState();
  }

  AuthRepository get _repository => ref.read(authRepositoryProvider);

  /// Comprueba la sesión actual con `GET /api/auth/me`.
  ///
  /// La sesión solo se cierra si el servidor responde 401 (cookie vencida o
  /// revocada). Con mala conexión (tiempo agotado, sin red, error del
  /// servidor) se entra con la sesión guardada y se vuelve a comprobar en
  /// segundo plano: no hay que iniciar sesión otra vez.
  Future<void> restoreSession() async {
    _retryTimer?.cancel();
    final cookie = ref.read(apiClientProvider).sessionCookie;
    if (cookie == null || cookie.isEmpty) {
      if (state.status == AuthStatus.unknown) {
        state = const AuthState(status: AuthStatus.unauthenticated);
      }
      return;
    }
    try {
      final user = await _repository.me();
      _retryAttempt = 0;
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        _retryAttempt = 0;
        ref.read(apiClientProvider).sessionCookie = null;
        state = const AuthState(status: AuthStatus.unauthenticated);
        return;
      }
      _keepOfflineSession();
    } catch (_) {
      _keepOfflineSession();
    }
  }

  /// Sin respuesta válida del servidor pero con cookie guardada: se sigue
  /// con la sesión (el usuario guardado o el que ya estaba en memoria) y se
  /// reintenta con espera creciente (15 s, 30 s, 60 s... hasta 2 min).
  void _keepOfflineSession() {
    if (!state.isAuthenticated) {
      final cached = ref.read(sessionStoreProvider).user;
      state = AuthState(
        status: AuthStatus.authenticated,
        user: state.user ?? (cached == null ? null : AuthUser.fromJson(cached)),
      );
    }
    final seconds = (15 * (1 << _retryAttempt)).clamp(15, 120);
    if (_retryAttempt < 3) _retryAttempt++;
    _retryTimer = Timer(Duration(seconds: seconds), () {
      if (state.isAuthenticated) restoreSession();
    });
  }

  /// `POST /api/auth/login`
  Future<bool> login({required String email, required String password}) async {
    state = state.copyWith(isWorking: true, clearError: true, clearInfo: true);
    try {
      final user = await _repository.login(email: email, password: password);
      await _persistSession();
      state = AuthState(status: AuthStatus.authenticated, user: user);
      return true;
    } catch (error) {
      state = state.copyWith(
        isWorking: false,
        status: AuthStatus.unauthenticated,
        error: authErrorMessage(error),
      );
      return false;
    }
  }

  /// `POST /api/auth/register`
  Future<bool> register({
    required String email,
    required String password,
    String? displayName,
    String? inviteCode,
  }) async {
    state = state.copyWith(isWorking: true, clearError: true, clearInfo: true);
    try {
      final user = await _repository.register(
        email: email,
        password: password,
        displayName: displayName,
        inviteCode: inviteCode,
      );
      await _persistSession();
      state = AuthState(status: AuthStatus.authenticated, user: user);
      return true;
    } catch (error) {
      state = state.copyWith(
        isWorking: false,
        status: AuthStatus.unauthenticated,
        error: authErrorMessage(error),
      );
      return false;
    }
  }

  /// La cuenta quedó vinculada con Telegram (`POST /api/auth/verify/confirm`).
  /// Usa el usuario que devolvió el servidor o, si no vino, marca el actual.
  void completeTelegramVerification(AuthUser? user) {
    final next = (user ?? state.user)?.copyWith(telegramLinked: true);
    state = AuthState(status: AuthStatus.authenticated, user: next);
  }

  /// `POST /api/auth/logout`
  Future<void> logout() async {
    _retryTimer?.cancel();
    // Antes de perder la cookie: que no lleguen avisos de esta cuenta.
    await PushService.unregisterFromBackend();
    try {
      await _repository.logout();
    } catch (_) {
      // El cierre de sesión local siempre se aplica.
    }
    ref.read(apiClientProvider).sessionCookie = null;
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Entra en modo invitado (spec §6.9: "Explorar como invitado").
  void continueAsGuest() {
    state = const AuthState(status: AuthStatus.guest);
  }

  /// `POST /api/auth/update-name`
  Future<bool> updateDisplayName(String displayName) async {
    state = state.copyWith(isWorking: true, clearError: true);
    try {
      final user = await _repository.updateName(displayName);
      state = state.copyWith(isWorking: false, user: user);
      return true;
    } catch (error) {
      state = state.copyWith(isWorking: false, error: authErrorMessage(error));
      return false;
    }
  }

  /// `POST /api/auth/avatar` (multipart)
  Future<bool> uploadAvatar({
    required String filePath,
    required String fileName,
  }) async {
    state = state.copyWith(isWorking: true, clearError: true);
    try {
      final user = await _repository.uploadAvatar(
        filePath: filePath,
        fileName: fileName,
      );
      state = state.copyWith(isWorking: false, user: user);
      return true;
    } catch (error) {
      state = state.copyWith(isWorking: false, error: authErrorMessage(error));
      return false;
    }
  }

  /// `DELETE /api/auth/avatar`
  Future<bool> deleteAvatar() async {
    state = state.copyWith(isWorking: true, clearError: true);
    try {
      await _repository.deleteAvatar();
      final user = state.user?.copyWith(avatarUrl: '');
      state = state.copyWith(isWorking: false, user: user);
      return true;
    } catch (error) {
      state = state.copyWith(isWorking: false, error: authErrorMessage(error));
      return false;
    }
  }

  /// `POST /api/auth/link-code`
  Future<TelegramLinkCode?> createTelegramLinkCode() async {
    state = state.copyWith(isWorking: true, clearError: true);
    try {
      final code = await _repository.createLinkCode();
      state = state.copyWith(isWorking: false);
      return code;
    } catch (error) {
      state = state.copyWith(isWorking: false, error: authErrorMessage(error));
      return null;
    }
  }

  /// `POST /api/auth/forgot-password`
  Future<String?> requestPasswordReset(String email) async {
    state = state.copyWith(isWorking: true, clearError: true);
    try {
      final token = await _repository.requestPasswordResetToken(email);
      state = state.copyWith(isWorking: false);
      return token;
    } catch (error) {
      state = state.copyWith(isWorking: false, error: authErrorMessage(error));
      return null;
    }
  }

  /// `POST /api/auth/reset-password`
  Future<bool> resetPassword({
    required String token,
    required String code,
    required String newPassword,
  }) async {
    state = state.copyWith(isWorking: true, clearError: true);
    try {
      await _repository.resetPassword(
        token: token,
        code: code,
        newPassword: newPassword,
      );
      state = state.copyWith(isWorking: false);
      return true;
    } catch (error) {
      state = state.copyWith(isWorking: false, error: authErrorMessage(error));
      return false;
    }
  }

  /// Guarda la cookie de sesión en disco antes de cambiar el estado, para que
  /// un cierre inmediato de la app no la pierda.
  Future<void> _persistSession() async {
    final cookie = ref.read(apiClientProvider).sessionCookie;
    if (cookie == null || cookie.isEmpty) return;
    await ref.read(sessionStoreProvider).save(cookie);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  void setInfo(String message) {
    state = state.copyWith(info: message, clearError: true);
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// Notificador para que `go_router` reaccione a los cambios de sesión.
final authSessionNotifierProvider = Provider<ChangeNotifier>((ref) {
  final notifier = ValueNotifier<int>(0);
  ref.listen<AuthState>(
    authControllerProvider,
    (_, _) => notifier.value = notifier.value + 1,
  );
  ref.onDispose(notifier.dispose);
  return notifier;
});
