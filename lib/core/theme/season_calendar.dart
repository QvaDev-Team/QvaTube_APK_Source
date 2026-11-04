/// Temporadas por fecha, sin depender del servidor (mismas ventanas que
/// `services/seasons.py`, en hora de Cuba y con los días inclusive).
///
/// Lo usa la pantalla de carga, que tiene que mostrar el arte correcto desde
/// el primer fotograma: no puede esperar a `GET /api/season` ni a descargar
/// nada. El resto de logos sigue lo que diga el servidor (SeasonBranding).
abstract final class SeasonCalendar {
  /// (id, mes inicio, día inicio, mes fin, día fin). Si se solaparan, gana la
  /// primera, como en el servidor.
  static const _windows = <(String, int, int, int, int)>[
    ('halloween', 10, 1, 11, 2),
    ('navidad', 12, 1, 1, 6),
    ('sanvalentin', 2, 7, 2, 14),
  ];

  /// Imagen de la pantalla de carga de cada temporada (incluida en el APK).
  static const splashAssets = <String, String>{
    'halloween': 'assets/themes/halloween/icons/icon-512.png',
    'navidad': 'assets/splash/navidad.png',
    'sanvalentin': 'assets/splash/sanvalentin.png',
  };

  static const defaultSplash = 'assets/icons/icon-512.png';

  /// Temporada de [now] (hora del teléfono pasada a la de Cuba) o `null`.
  static String? current([DateTime? now]) {
    // Cuba: UTC-5 en invierno y UTC-4 en verano; para ventanas de días
    // completos basta con UTC-5 (como mucho, una hora de diferencia).
    final cuba = (now ?? DateTime.now()).toUtc().subtract(const Duration(hours: 5));
    final today = cuba.month * 100 + cuba.day;
    for (final (id, m1, d1, m2, d2) in _windows) {
      final start = m1 * 100 + d1;
      final end = m2 * 100 + d2;
      final inside = start <= end
          ? today >= start && today <= end
          : today >= start || today <= end; // cruza el fin de año
      if (inside) return id;
    }
    return null;
  }

  static String splashFor([DateTime? now]) =>
      splashAssets[current(now)] ?? defaultSplash;
}
