import 'package:flutter/foundation.dart';

import '../telegram/telegram_files.dart';

/// Protocolo de "Compartir por Wi-Fi" entre dos teléfonos con QvaTube en la
/// misma red (Wi-Fi o punto de acceso de uno de ellos):
///
/// * El que envía abre un servidor HTTP en un puerto libre y anuncia cada
///   segundo por UDP (difusión al puerto [discoveryPort]) un [ShareAnnounce].
/// * El que recibe escucha esos anuncios, el usuario elige el teléfono y
///   escribe el PIN de 4 cifras que ve en el otro.
/// * `GET /manifest` → `{name, items: [ShareItem…]}`
///   `GET /file/{id}` → el archivo (admite `Range` para reanudar).
///   Ambos llevan la cabecera [pinHeader]; sin PIN correcto, 401.
abstract final class WifiShareProtocol {
  static const int discoveryPort = 47321;
  static const String app = 'qvatube-share';
  static const int version = 1;
  static const String pinHeader = 'x-qva-pin';
}

/// Anuncio por UDP de un teléfono que está compartiendo.
@immutable
class ShareAnnounce {
  const ShareAnnounce({
    required this.name,
    required this.port,
    required this.count,
    required this.size,
  });

  final String name;
  final int port;
  final int count;
  final int size;

  Map<String, dynamic> toJson() => {
    'app': WifiShareProtocol.app,
    'v': WifiShareProtocol.version,
    'name': name,
    'port': port,
    'count': count,
    'size': size,
  };

  static ShareAnnounce? tryParse(Map<String, dynamic> json) {
    if (json['app'] != WifiShareProtocol.app) return null;
    final port = (json['port'] as num?)?.toInt();
    if (port == null) return null;
    return ShareAnnounce(
      name: json['name']?.toString() ?? 'QvaTube',
      port: port,
      count: (json['count'] as num?)?.toInt() ?? 0,
      size: (json['size'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Un archivo que se comparte, con los datos del catálogo para que en el
/// otro teléfono aparezca con su título, carátula y sección.
@immutable
class ShareItem {
  const ShareItem({
    required this.id,
    required this.name,
    required this.size,
    required this.kind,
    this.title,
    this.poster,
    this.season,
    this.episode,
    this.categoryKey,
  });

  factory ShareItem.fromJson(Map<String, dynamic> json) => ShareItem(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? 'archivo',
    size: (json['size'] as num?)?.toInt() ?? 0,
    kind: TgFileKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => TgFileKind.document,
    ),
    title: json['title']?.toString(),
    poster: json['poster']?.toString(),
    season: (json['season'] as num?)?.toInt(),
    episode: (json['episode'] as num?)?.toInt(),
    categoryKey: json['category_key']?.toString(),
  );

  /// Desde un archivo del gestor (del bot o recibido antes).
  factory ShareItem.fromTgFile(String id, TgFile f) => ShareItem(
    id: id,
    name: f.name,
    size: f.size,
    kind: f.kind,
    title: f.catalog?.title,
    poster: f.catalog?.poster,
    season: f.catalog?.season,
    episode: f.catalog?.episode,
    categoryKey: f.catalog?.categoryKey,
  );

  final String id;
  final String name;
  final int size;
  final TgFileKind kind;
  final String? title;
  final String? poster;
  final int? season;
  final int? episode;
  final String? categoryKey;

  /// Título para mostrar.
  String get displayTitle {
    final t = title;
    if (t == null || t.isEmpty) return name;
    final s = season, e = episode;
    if (s == null || e == null) return t;
    return '$t · T$s · E${e.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'size': size,
    'kind': kind.name,
    'title': title,
    'poster': poster,
    'season': season,
    'episode': episode,
    'category_key': categoryKey,
  };
}
