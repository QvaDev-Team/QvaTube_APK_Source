import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_update_service.dart';

/// Servicio de comprobación y descarga de actualizaciones.
final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  return AppUpdateService();
});
