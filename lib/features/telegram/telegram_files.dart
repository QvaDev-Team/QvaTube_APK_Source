import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/platform/device_channel.dart';
import 'tdlib/td_client.dart';
import 'telegram_service.dart';

/// Tipo de archivo que envió el bot.
enum TgFileKind { video, audio, document }

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

  int size = 0;
  int downloaded = 0;
  bool downloading = false;
  bool completed = false;
  String localPath = '';

  double get progress => size > 0 ? (downloaded / size).clamp(0, 1) : 0;

  /// Se puede ver en el reproductor de QvaTube.
  bool get playable => kind != TgFileKind.document || _looksLikeVideo(name);

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

  /// Lee el chat del bot [botUsername] y arma la lista de archivos.
  Future<void> load(String botUsername) async {
    final client = _client;
    if (client == null || _loading) return;
    _listen();
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final chat = await client.send({
        '@type': 'searchPublicChat',
        'username': botUsername.replaceFirst('@', ''),
      });
      final chatId = (chat['id'] as num).toInt();
      _botChatId = chatId;
      // Abrir el chat hace que TDLib traiga los mensajes del servidor.
      client.sendRaw({'@type': 'openChat', 'chat_id': chatId});

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
          'only_local': false,
        });
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
      _files
        ..clear()
        ..addAll(found);
      _byFileId
        ..clear()
        ..addEntries(found.map((f) => MapEntry(f.fileId, f)));
    } catch (e) {
      _error = e is TdError
          ? 'No se pudo leer el chat del bot (${e.message}).'
          : 'No se pudo leer el chat del bot. Revisa tu conexión.';
    } finally {
      _loading = false;
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
      DeviceChannel.telegramDownloadDone(tg.name);
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
      _error = 'No se pudo descargar ${file.name}.';
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
      text: active.length == 1 ? active.first.name : null,
    );
  }

  /// Al desconectar Telegram se vacía la lista.
  void clear() {
    _sub?.cancel();
    _sub = null;
    _listening = null;
    _files.clear();
    _byFileId.clear();
    DeviceChannel.telegramDownloadStop();
    notifyListeners();
  }
}
