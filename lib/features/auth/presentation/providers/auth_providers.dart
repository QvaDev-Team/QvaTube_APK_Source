import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../data/auth_api.dart';
import '../../data/auth_repository.dart';

export '../../../../core/network/api_providers.dart' show apiClientProvider;

/// API de autenticación (rutas de `doc/openapi.json`).
final authApiProvider = Provider<AuthApi>((ref) {
  return AuthApi(ref.watch(apiClientProvider));
});

/// Repositorio de autenticación.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(authApiProvider),
    ref.watch(apiClientProvider),
  );
});
