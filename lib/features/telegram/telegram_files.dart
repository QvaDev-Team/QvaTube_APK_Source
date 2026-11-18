import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/platform/device_channel.dart';
import 'tdlib/td_client.dart';
import 'telegram_service.dart';

/// Tipo de archivo que envió el bot.
enum TgFileKind { video, audio, document }

/// Datos del catálogo de un archivo que el bot envió con `delivery: "app"`
/// (`GET /api/telegram-files`).
@immutable
class TgCatalogInfo {
  const TgCatalogInfo({
    required this.title,
    this.poster,
    this.season,
    this.episode,
    this.categoryKey,
  });

  factory TgCatalogInfo.fromJson(Map<String, dynamic> json) => TgCatalogInfo(
    title: json['title']?.toString() ?? '',
    poster: json['poster']?.toString(),
    season: (json['season'] as num?)?.toInt(),
    episode: (json['episode'] as num?)?.toInt(),
    categoryKey: json['category_key']?.toString(),
  );

  final String title;

  /// Ruta del servidor (`/cover/…`) o URL de TMDb.
  final String? poster;
  final int? season;
  final int? episode;
  final String? categoryKey;

  /// "T1 · E07" para episodios; vacío si no aplica.
  String get episodeLabel {
    final s = season, e = episode;
    if (s == null || e == null) return '';
    return 'T$s · E${e.toString().padLeft(2, '0')}';
  }
}

/// Archivo que el bot de QvaTube envió al chat del usuario.
class TgFile {
  TgFile({
    required this.messageId,
    required this.fileId,
    required this.name,
    required this.kind,
    required this.date,
    this.caption = '',
    this.thumbnail,
    this.durationSeconds = 0,
  });

  final int messageId;
  final int fileId;
  final String name;
  final TgFileKind kind;
  final DateTime date;
  final String caption;

  /// Miniatura muy pequeña (JPEG) que viene dentro del propio mensaje.
  final Uint8List? thumbnail;
  final int durationSeconds;

  /// Título, carátula y episodio del catálogo, si el archivo llegó por el
  /// gestor de descargas (si no, solo se conoce el nombre del archivo).
  TgCatalogInfo? catalog;

  /// Nombre para mostrar: el del catálogo o, si no hay, el del archivo.
  String get title {
    final c = catalog;
    if (c == null || c.title.isEmpty) return name;
    final ep = c.episodeLabel;
    return ep.isEmpty ? c.title : '${c.title} · $ep';
  }

  int size = 0;
  int downloaded = 0;
  bool downloading = false;
  bool completed = false;
  String localPath = '';

  double get progress => size > 0 ? (downloaded / size).clamp(0, 1) : 0;

  /// Se puede ver en el reproductor de QvaTube.
  bool get playable => kind != TgFileKind.document || _looksLikeVideo(name);

  /// Libro que se puede abrir en el lector de QvaTube (EPUB o PDF).
  bool get readable =>
      RegExp(r'\.(epub|pdf)$', caseSensitive: false).hasMatch(name);

  static bool _looksLikeVideo(String name) => RegExp(
    r'\.(mp4|mkv|avi|mov|webm|m4v|ts|mp3|m4a|flac|ogg|opus|wav)$',
    caseSensitive: false,
  ).hasMatch(name);

  /// Aplica el estado de un objeto `file` de TDLib.
  void applyFile(Map<String, dynamic> file) {
    final local = (file['local'] as Map?) ?? const {};
    size = _int(file['size']) > 0
        ? _int(file['size'])
        : _int(file['expected_size']);
    downloaded = _int(local['downloaded_size']);
    downloading = local['is_downloading_active'] == true;
    completed = local['is_downloading_completed'] == true;
    localPath = local['path']?.toString() ?? '';
  }

  static int _int(Object? v) => v is num ? v.toInt() : 0;
}

/// Lista de archivos del bot y descargas desde Telegram (TDLib), con
/// progreso, pausa y reanudación. Las descargas siguen con la app cerrada
/// gracias al servicio en primer plano de Android.
class TelegramFiles extends ChangeNotifier {
  TelegramFiles._();

  static final TelegramFiles instance = TelegramFiles._();

  /// Mensajes del chat del bot que se revisan como máximo.
  static const int _maxMessages = 400;

  final List<TgFile> _files = [];
  final Map<int, TgFile> _byFileId = {};
  StreamSubscription<Map<String, dynamic>>? _sub;
  TdClient? _listening;
  bool _loading = false;
  String? _error;
  int? _botChatId;

  List<TgFile> get files => List.unmodifiable(_files);
  bool get loading => _loading;
  String? get error => _error;

  TdClient? get _client => TelegramService.instance.client;

  void _listen() {
    final client = _client;
    if (client == null || identical(client, _listening)) return;
    _sub?.cancel();
    _listening = client;
    _sub = client.updates.listen((update) {
      if (update['@type'] == 'updateFile') {
        _onFile(update['file'] as Map<String, dynamic>);
      }
    });
  }

  /// Id del chat del bot guardado en el teléfono: al abrir la app TDLib
  /// puede tardar minutos en conectar y `searchPublicChat` necesita red.
  static const String _botChatKey = 'qvatube.telegram_bot_chat';

  bool _syncing = false;

  /// Filas de `GET /api/telegram-files`: (tamaño, hora de envío, datos).
  final List<({int size, DateTime? sentAt, TgCatalogInfo info})> _catalog = [];

  /// Aplica la lista de `GET /api/telegram-files` (título, carátula y
  /// temporada/episodio de lo que el bot envió con el gestor de descargas).
  void applyCatalog(List<Map<String, dynamic>> rows) {
    _catalog
      ..clear()
      ..addAll([
        for (final row in rows)
          (
            size: (row['size'] as num?)?.toInt() ?? 0,
            sentAt: DateTime.tryParse('${row['sent_at'] ?? ''}Z'),
            info: TgCatalogInfo.fromJson(row),
          ),
      ]);
    _matchCatalog(_files);
    notifyListeners();
  }

  /// Une cada archivo del chat con su fila del servidor.
  ///
  /// No se puede usar el `telegram_message_id` del servidor: en los chats
  /// privados cada cuenta numera los mensajes por su lado (el bot ve un id
  /// y el usuario otro). Se cruza por el tamaño exacto del archivo y, si
  /// hay varios iguales, por la hora de envío más cercana.
  void _matchCatalog(List<TgFile> files) {
    for (final f in files) {
      f.catalog = null;
      if (f.size <= 0) continue;
      Duration? best;
      for (final row in _catalog) {
        if (row.size != f.size) continue;
        final sent = row.sentAt;
        final gap = sent == null
            ? const Duration(days: 1)
            : f.date.difference(sent).abs();
        if (gap > const Duration(days: 2)) continue;
        if (best == null || gap < best) {
          best = gap;
          f.catalog = row.info;
        }
      }
    }
  }

  String? _botUsername;
  VoidCallback? _onlineListener;

  /// Actualizando la lista desde los servidores de Telegram.
  bool get syncing => _syncing;

  /// Sin nada guardado en el teléfono y esperando a que Telegram conecte.
  bool get waitingForConnection =>
      _files.isEmpty &&
      !_loading &&
      _error == null &&
      !TelegramService.instance.online.value;

  /// Lee el chat del bot [botUsername] y arma la lista de archivos.
  ///
  /// Primero con lo que TDLib tiene guardado en el teléfono (inmediato y
  /// sin conexión) y después, en cuanto Telegram esté conectado, con lo
  /// del servidor.
  Future<void> load(String botUsername) async {
    final client = _client;
    if (client == null || _loading) return;
    _botUsername = botUsername.replaceFirst('@', '');
    _listen();
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final chatId = await _findBotChat(client, _botUsername!);
      if (chatId != null) {
        _botChatId = chatId;
        // Abrir el chat hace que TDLib traiga los mensajes del servidor.
        client.sendRaw({'@type': 'openChat', 'chat_id': chatId});
        final local = await _scan(client, chatId, onlyLocal: true);
        if (local.isNotEmpty || _files.isEmpty) _replace(local);
      }
    } catch (_) {
      // Sin copia local: se intenta otra vez con conexión.
    } finally {
      _loading = false;
      notifyListeners();
    }
    _syncWhenOnline();
  }

  /// Chat del bot: el guardado, el que TDLib ya conoce (sin red) o, como
  /// último recurso, la búsqueda en el servidor.
  Future<int?> _findBotChat(TdClient client, String username) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_botChatKey);
    if (saved != null) return saved;

    int? found;
    try {
      final local = await client.send({
        '@type': 'searchChats',
        'query': username,
        'limit': 5,
      }, timeout: const Duration(seconds: 10));
      for (final id in ((local['chat_ids'] as List?) ?? const []).cast<num>()) {
        if (await _isBotChat(client, id.toInt(), username)) {
          found = id.toInt();
          break;
        }
      }
    } catch (_) {}
    if (found == null && TelegramService.instance.online.value) {
      final chat = await client.send({
        '@type': 'searchPublicChat',
        'username': username,
      }, timeout: const Duration(seconds: 30));
      found = (chat['id'] as num).toInt();
    }
    if (found != null) await prefs.setInt(_botChatKey, found);
    return found;
  }

  Future<bool> _isBotChat(TdClient client, int chatId, String username) async {
    final chat = await client.send({
      '@type': 'getChat',
      'chat_id': chatId,
    }, timeout: const Duration(seconds: 10));
    final type = chat['type'] as Map?;
    if (type?['@type'] != 'chatTypePrivate') return false;
    final user = await client.send({
      '@type': 'getUser',
      'user_id': type!['user_id'],
    }, timeout: const Duration(seconds: 10));
    final names = ((user['usernames'] as Map?)?['active_usernames'] as List?)
        ?.map((n) => n.toString().toLowerCase());
    return names?.contains(username.toLowerCase()) ?? false;
  }

  /// Recorre el historial del chat del bot y devuelve sus archivos.
  Future<List<TgFile>> _scan(
    TdClient client,
    int chatId, {
    required bool onlyLocal,
  }) async {
    final found = <TgFile>[];
    final seenIds = <int>{};
    var fromId = 0;
    var emptyRounds = 0;
    while (seenIds.length < _maxMessages && emptyRounds < 2) {
      final page = await client.send({
        '@type': 'getChatHistory',
        'chat_id': chatId,
        'from_message_id': fromId,
        'offset': 0,
        'limit': 100,
        'only_local': onlyLocal,
      }, timeout: Duration(seconds: onlyLocal ? 10 : 30));
      final messages = (page['messages'] as List?) ?? const [];
      if (messages.isEmpty) {
        emptyRounds++;
        continue;
      }
      var nuevos = 0;
      for (final m in messages.cast<Map<String, dynamic>>()) {
        final id = (m['id'] as num).toInt();
        fromId = id;
        // El mensaje frontera entre páginas puede repetirse.
        if (!seenIds.add(id)) continue;
        nuevos++;
        if (m['is_outgoing'] == true) continue;
        final file = parseMessage(m);
        if (file != null) found.add(file);
      }
      emptyRounds = nuevos == 0 ? emptyRounds + 1 : 0;
    }
    return found;
  }

  void _replace(List<TgFile> found) {
    _matchCatalog(found);
    _files
      ..clear()
      ..addAll(found);
    _byFileId
      ..clear()
      ..addEntries(found.map((f) => MapEntry(f.fileId, f)));
  }

  /// Actualiza desde el servidor ya, o en cuanto Telegram conecte.
  void _syncWhenOnline() {
    final online = TelegramService.instance.online;
    if (online.value) {
      unawaited(_syncFromServer());
      return;
    }
    if (_onlineListener != null) return;
    void listener() {
      if (!online.value) return;
      online.removeListener(listener);
      _onlineListener = null;
      unawaited(_syncFromServer());
    }

    _onlineListener = listener;
    online.addListener(listener);
  }

  Future<void> _syncFromServer() async {
    final client = _client;
    if (client == null || _syncing || _loading) return;
    var chatId = _botChatId;
    _syncing = true;
    notifyListeners();
    try {
      if (chatId == null) {
        final username = _botUsername;
        if (username == null) return;
        chatId = await _findBotChat(client, username);
        if (chatId == null) return;
        _botChatId = chatId;
        client.sendRaw({'@type': 'openChat', 'chat_id': chatId});
      }
      _replace(await _scan(client, chatId, onlyLocal: false));
      _error = null;
    } catch (e) {
      if (_files.isEmpty) {
        _error = e is TdError
            ? 'No se pudo leer el chat del bot (${e.message}).'
            : 'No se pudo leer el chat del bot. Revisa tu conexión.';
      }
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Convierte un mensaje con archivo en [TgFile] (o `null` si no tiene).
  @visibleForTesting
  static TgFile? parseMessage(Map<String, dynamic> message) {
    final content = (message['content'] as Map?)?.cast<String, dynamic>();
    if (content == null) return null;
    final date = DateTime.fromMillisecondsSinceEpoch(
      ((message['date'] as num?)?.toInt() ?? 0) * 1000,
    );
    final caption = ((content['caption'] as Map?)?['text'] ?? '').toString();

    Map<String, dynamic>? media;
    Map<String, dynamic>? file;
    TgFileKind kind;
    switch (content['@type']) {
      case 'messageVideo':
        media = (content['video'] as Map).cast<String, dynamic>();
        file = (media['video'] as Map).cast<String, dynamic>();
        kind = TgFileKind.video;
      case 'messageAudio':
        media = (content['audio'] as Map).cast<String, dynamic>();
        file = (media['audio'] as Map).cast<String, dynamic>();
        kind = TgFileKind.audio;
      case 'messageDocument':
        media = (content['document'] as Map).cast<String, dynamic>();
        file = (media['document'] as Map).cast<String, dynamic>();
        kind = TgFileKind.document;
      default:
        return null;
    }

    final mini =
        (media['minithumbnail'] ?? media['album_cover_minithumbnail']) as Map?;
    Uint8List? thumb;
    final data = mini?['data'];
    if (data is String && data.isNotEmpty) {
      try {
        thumb = base64Decode(data);
      } catch (_) {}
    }
    var name = media['file_name']?.toString() ?? '';
    if (name.isEmpty) name = media['title']?.toString() ?? '';
    if (name.isEmpty && caption.isNotEmpty) name = caption.split('\n').first;
    if (name.isEmpty) name = 'Archivo ${message['id']}';

    final tg = TgFile(
      messageId: (message['id'] as num).toInt(),
      fileId: (file['id'] as num).toInt(),
      name: name,
      kind: kind,
      date: date,
      caption: caption,
      thumbnail: thumb,
      durationSeconds: (media['duration'] as num?)?.toInt() ?? 0,
    )..applyFile(file);
    return tg;
  }

  void _onFile(Map<String, dynamic> file) {
    final id = (file['id'] as num?)?.toInt();
    final tg = id == null ? null : _byFileId[id];
    if (tg == null) return;
    final wasCompleted = tg.completed;
    tg.applyFile(file);
    if (tg.completed && !wasCompleted) {
      DeviceChannel.telegramDownloadDone(tg.title);
    }
    _syncNotification();
    notifyListeners();
  }

  /// Empieza o reanuda la descarga (TDLib sigue desde donde iba).
  Future<void> download(TgFile file) async {
    final client = _client;
    if (client == null) return;
    _listen();
    file.downloading = true;
    notifyListeners();
    try {
      final res = await client.send({
        '@type': 'downloadFile',
        'file_id': file.fileId,
        'priority': 16,
        'offset': 0,
        'limit': 0,
        'synchronous': false,
      });
      _onFile(res);
    } catch (e) {
      file.downloading = false;
      _error = 'No se pudo descargar ${file.title}.';
      notifyListeners();
    }
  }

  /// Pausa la descarga (lo ya bajado se conserva).
  Future<void> pause(TgFile file) async {
    await _client?.send({
      '@type': 'cancelDownloadFile',
      'file_id': file.fileId,
      'only_if_pending': false,
    });
    file.downloading = false;
    _syncNotification();
    notifyListeners();
  }

  /// Borra el archivo del teléfono (sigue en el chat del bot).
  Future<void> remove(TgFile file) async {
    await _client?.send({'@type': 'deleteFile', 'file_id': file.fileId});
    file
      ..downloaded = 0
      ..downloading = false
      ..completed = false
      ..localPath = '';
    _syncNotification();
    notifyListeners();
  }

  /// Chat del bot (para abrirlo en la app de Telegram si hace falta).
  int? get botChatId => _botChatId;

  /// Notificación con el progreso total de las descargas activas.
  void _syncNotification() {
    final active = _files.where((f) => f.downloading && !f.completed).toList();
    if (active.isEmpty) {
      DeviceChannel.telegramDownloadStop();
      return;
    }
    final total = active.fold<int>(0, (s, f) => s + f.size);
    final done = active.fold<int>(0, (s, f) => s + f.downloaded);
    DeviceChannel.telegramDownloadProgress(
      percent: total > 0 ? (done * 100 ~/ total) : -1,
      title: active.length == 1
          ? 'Descargando de Telegram'
          : 'Descargando ${active.length} archivos de Telegram',
      text: active.length == 1 ? active.first.title : null,
    );
  }

  /// Al desconectar Telegram se vacía la lista.
  void clear() {
    final listener = _onlineListener;
    if (listener != null) {
      TelegramService.instance.online.removeListener(listener);
      _onlineListener = null;
    }
    _botChatId = null;
    _catalog.clear();
    SharedPreferences.getInstance().then((p) => p.remove(_botChatKey));
    _sub?.cancel();
    _sub = null;
    _listening = null;
    _files.clear();
    _byFileId.clear();
    DeviceChannel.telegramDownloadStop();
    notifyListeners();
  }
}
