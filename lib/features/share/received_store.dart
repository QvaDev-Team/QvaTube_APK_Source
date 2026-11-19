import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/platform/device_channel.dart';
import '../telegram/telegram_files.dart';
import 'wifi_share_protocol.dart';

/// Archivo recibido de otro teléfono por Wi-Fi.
@immutable
class ReceivedFile {
  const ReceivedFile({
    required this.path,
    required this.item,
    required this.receivedAt,
  });

  factory ReceivedFile.fromJson(Map<String, dynamic> json) => ReceivedFile(
    path: json['path'] as String,
    item: ShareItem.fromJson(Map<String, dynamic>.from(json['item'] as Map)),
    receivedAt:
        DateTime.tryParse(json['received_at']?.toString() ?? '') ??
        DateTime.now(),
  );

  final String path;
  final ShareItem item;
  final DateTime receivedAt;

  Map<String, dynamic> toJson() => {
    'path': path,
    'item': item.toJson(),
    'received_at': receivedAt.toIso8601String(),
  };
}

/// Archivos recibidos por Wi-Fi (`files/qvashare/`). Aparecen en el gestor
/// de descargas como descargados, junto a los del bot, y se pueden volver
/// a compartir.
class ReceivedStore extends ChangeNotifier {
  ReceivedStore._();

  static final ReceivedStore instance = ReceivedStore._();

  final List<ReceivedFile> _files = [];
  List<TgFile> _asTgFiles = const [];
  bool _loaded = false;

  List<ReceivedFile> get files => List.unmodifiable(_files);

  /// Los recibidos como [TgFile] (ids negativos para no chocar con TDLib).
  List<TgFile> get asTgFiles => _asTgFiles;

  static Future<Directory> dir() async {
    final d = Directory('${await DeviceChannel.cacheDirectory()}/qvashare');
    await d.create(recursive: true);
    return d;
  }

  static Future<File> _index() async =>
      File('${(await dir()).path}/index.json');

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _index();
      if (await f.exists()) {
        final list = jsonDecode(await f.readAsString()) as List;
        for (final e in list) {
          final r = ReceivedFile.fromJson(Map<String, dynamic>.from(e as Map));
          if (await File(r.path).exists()) _files.add(r);
        }
      }
    } catch (_) {}
    _rebuild();
  }

  Future<void> _save() async {
    try {
      final f = await _index();
      await f.writeAsString(jsonEncode([for (final r in _files) r.toJson()]));
    } catch (_) {}
  }

  /// `true` si ya se recibió (mismo nombre y tamaño).
  bool has(ShareItem item) =>
      _files.any((r) => r.item.name == item.name && r.item.size == item.size);

  Future<void> add(ReceivedFile file) async {
    _files.removeWhere((r) => r.path == file.path);
    _files.insert(0, file);
    _rebuild();
    await _save();
  }

  /// Borra del teléfono un archivo recibido.
  Future<void> delete(TgFile file) async {
    final r = _files.where((r) => r.path == file.localPath).firstOrNull;
    if (r == null) return;
    _files.remove(r);
    try {
      await File(r.path).delete();
    } catch (_) {}
    _rebuild();
    await _save();
  }

  void _rebuild() {
    _asTgFiles = [for (final r in _files) _toTgFile(r)];
    notifyListeners();
  }

  static TgFile _toTgFile(ReceivedFile r) {
    final id = -1 - (r.path.hashCode & 0x3fffffff);
    final item = r.item;
    final f =
        TgFile(
            messageId: id,
            fileId: id,
            name: item.name,
            kind: item.kind,
            date: r.receivedAt,
          )
          ..size = item.size
          ..downloaded = item.size
          ..completed = true
          ..localPath = r.path;
    if (item.title != null && item.title!.isNotEmpty) {
      f.catalog = TgCatalogInfo(
        title: item.title!,
        poster: item.poster,
        season: item.season,
        episode: item.episode,
        categoryKey: item.categoryKey,
      );
    }
    return f;
  }
}
