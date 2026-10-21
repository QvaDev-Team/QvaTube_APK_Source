import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

import '../data/auth_repository.dart';
import '../domain/auth_models.dart';
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
///
/// La lógica de red está implementada y verificada contra `doc/openapi.json`,
/// pero las llamadas permanecen desactivadas
/// (`AppConfig.remoteCallsEnabled == false`) hasta que se defina el contenido
/// de cada pantalla.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    return const AuthState();
  }

  AuthRepository get _repository => ref.read(authRepositoryProvider);

  /// Comprueba la sesión actual con `GET /api/auth/me`.
  Future<void> restoreSession() async {
    try {
      final user = await _repository.me();
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } on RemoteCallsDisabledException {
      state = const AuthState(status: AuthStatus.unauthenticated);
    } catch (error) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: authErrorMessage(error),
      );
    }
  }

  /// `POST /api/auth/login`
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isWorking: true, clearError: true, clearInfo: true);
    try {
      final user = await _repository.login(email: email, password: password);
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

  /// `POST /api/auth/logout`
  Future<void> logout() async {
    try {
      await _repository.logout();
    } catch (_) {
      // El cierre de sesión local siempre se aplica.
    }
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Entra en modo invitado (spec §6.9: "Explorar como invitado").
  void continueAsGuest() {
    state = const AuthState(status: AuthStatus.guest);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  void setInfo(String message) {
    state = state.copyWith(info: message, clearError: true);
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

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
