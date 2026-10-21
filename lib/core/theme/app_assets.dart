import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Manifiesto de assets por temporada (`assets/theme.json`).
///
/// Permite cambiar el logo, el favicon y los iconos de la app **sin tocar
/// código**: basta con editar el campo `active` del JSON (o cambiarlo desde
/// *Configuración → Tema* dentro de la app) y reconstruir.
///
/// Estructura del JSON:
/// ```json
/// {
///   "version": 1,
///   "active": "halloween",
///   "androidLauncher": { "mipmap-mdpi": "icon-72.png", ... },
///   "themes": {
///     "default": {
///       "label": "QvaTube (estándar)",
///       "path": "assets",
///       "assets": { "logo": "logo.png", "icons": { "192": "icon-192.png" } }
///     }
///   }
/// }
/// ```
class AppAssets {
  const AppAssets._();

  /// Ruta del manifiesto dentro de los assets.
  static const String manifestPath = 'assets/theme.json';

  /// Tema por defecto si el manifiesto no existe o está incompleto.
  static const String fallbackThemeId = 'default';

  static final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  /// Se incrementa cuando cambia el tema, para redibujar la UI.
  static ValueListenable<int> get revision => _revision;

  static AppAssetTheme _current = AppAssetTheme.fallback();
  static Map<String, AppAssetTheme> _themes = const {};

  /// Tema activo.
  static AppAssetTheme get current => _current;

  /// Todos los temas disponibles en el manifiesto.
  static List<AppAssetTheme> get themes => _themes.values.toList();

  /// Ruta del logo principal (el que se ve en la app).
  static String get logo => _current.logo;

  /// Ruta del logo en WebP (más liviano para la web).
  static String get logoWebp => _current.logoWebp;

  /// Ruta del favicon.
  static String get favicon => _current.favicon;

  /// Ruta del favicon `.ico`.
  static String get faviconIco => _current.faviconIco;

  /// Ruta de un icono por tamaño (`72`, `96`, `192`, `512`…).
  static String icon(String size) => _current.icon(size);

  /// Todos los iconos del tema activo (`tamaño → ruta`).
  static Map<String, String> get icons => _current.icons;

  /// Lee el manifiesto y aplica el tema indicado (o el `active`).
  ///
  /// Si el JSON no está disponible se usan las rutas por defecto, para que la
  /// app nunca se rompa.
  static Future<void> init({String? themeId}) async {
    try {
      final raw = await rootBundle.loadString(manifestPath);
      final json = jsonDecode(raw) as Map<String, dynamic>;

      final rawThemes = json['themes'];
      if (rawThemes is! Map) return;

      final parsed = <String, AppAssetTheme>{};
      rawThemes.forEach((key, value) {
        if (value is Map) {
          parsed[key.toString()] = AppAssetTheme.fromJson(
            id: key.toString(),
            json: Map<String, dynamic>.from(value),
          );
        }
      });
      if (parsed.isEmpty) return;

      _themes = parsed;

      final wanted = themeId ?? json['active']?.toString();
      _current = parsed[wanted] ??
          parsed[fallbackThemeId] ??
          parsed.values.first;
      _revision.value++;
    } catch (error) {
      debugPrint('[AppAssets] No se pudo leer $manifestPath: $error');
    }
  }

  /// Cambia el tema activo en caliente.
  static Future<bool> setTheme(String themeId) async {
    if (!_themes.containsKey(themeId)) return false;
    _current = _themes[themeId]!;
    _revision.value++;
    return true;
  }
}

/// Un tema del manifiesto: una carpeta con los assets de la temporada.
class AppAssetTheme {
  const AppAssetTheme({
    required this.id,
    required this.label,
    required this.path,
    required this.assets,
    this.description,
  });

  /// Tema de reserva (rutas por defecto de la marca).
  factory AppAssetTheme.fallback() {
    return const AppAssetTheme(
      id: AppAssets.fallbackThemeId,
      label: 'QvaTube (estándar)',
      path: 'assets',
      description: 'Tema por defecto de la marca.',
      assets: <String, String>{
        'logo': 'logo.png',
        'logoWebp': 'logo.webp',
        'favicon': 'favicon.png',
        'faviconIco': 'favicon.ico',
      },
    );
  }

  factory AppAssetTheme.fromJson({
    required String id,
    required Map<String, dynamic> json,
  }) {
    final path = json['path']?.toString() ?? 'assets';
    final rawAssets = json['assets'];
    final assets = <String, String>{};
    if (rawAssets is Map) {
      rawAssets.forEach((key, value) {
        if (key.toString() == 'icons') {
          if (value is Map) {
            value.forEach((size, file) {
              assets['icon:$size'] = '$path/${file.toString()}';
            });
          }
          return;
        }
        assets[key.toString()] = '$path/${value.toString()}';
      });
    }

    return AppAssetTheme(
      id: id,
      label: json['label']?.toString() ?? id,
      path: path,
      description: json['description']?.toString(),
      assets: assets,
    );
  }

  final String id;
  final String label;
  final String path;
  final String? description;

  /// Slot → ruta completa (`assets/themes/halloween/logo.png`).
  final Map<String, String> assets;

  String get logo => assets['logo'] ?? 'assets/logo.png';

  String get logoWebp => assets['logoWebp'] ?? 'assets/logo.webp';

  String get favicon => assets['favicon'] ?? 'assets/favicon.png';

  String get faviconIco => assets['faviconIco'] ?? 'assets/favicon.ico';

  /// Iconos del tema (`tamaño → ruta`).
  Map<String, String> get icons {
    final result = <String, String>{};
    assets.forEach((key, value) {
      if (key.startsWith('icon:')) {
        result[key.substring('icon:'.length)] = value;
      }
    });
    return result;
  }

  String icon(String size) => icons[size] ?? logo;
}
