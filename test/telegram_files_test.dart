import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qvatube_apk/features/telegram/telegram_files.dart';

/// Mensajes con la forma exacta que devuelve TDLib 1.8 (getChatHistory).
Map<String, dynamic> archivo({
  int id = 77,
  int size = 1300000000,
  int downloaded = 0,
  bool active = false,
  bool done = false,
  String path = '',
}) => {
  '@type': 'file',
  'id': id,
  'size': size,
  'expected_size': size,
  'local': {
    '@type': 'localFile',
    'path': path,
    'can_be_downloaded': true,
    'is_downloading_active': active,
    'is_downloading_completed': done,
    'downloaded_size': downloaded,
  },
};

void main() {
  test('un video del bot se convierte en archivo con nombre y miniatura', () {
    final mini = base64Encode([0xFF, 0xD8, 0xFF]);
    final file = TelegramFiles.parseMessage({
      '@type': 'message',
      'id': 8812,
      'date': 1763480400,
      'is_outgoing': false,
      'content': {
        '@type': 'messageVideo',
        'caption': {'@type': 'formattedText', 'text': 'Cars 3 (2017)'},
        'video': {
          '@type': 'video',
          'duration': 6120,
          'file_name': 'Cars 3.mp4',
          'mime_type': 'video/mp4',
          'minithumbnail': {'width': 40, 'height': 22, 'data': mini},
          'video': archivo(downloaded: 650000000, active: true),
        },
      },
    })!;
    expect(file.name, 'Cars 3.mp4');
    expect(file.kind, TgFileKind.video);
    expect(file.fileId, 77);
    expect(file.messageId, 8812);
    expect(file.durationSeconds, 6120);
    expect(file.thumbnail, isNotNull);
    expect(file.downloading, isTrue);
    expect(file.progress, closeTo(0.5, 0.001));
    expect(file.playable, isTrue);
  });

  test('un documento .mkv se puede ver; un .zip no', () {
    TgFile? doc(String name) => TelegramFiles.parseMessage({
      'id': 1,
      'date': 0,
      'content': {
        '@type': 'messageDocument',
        'caption': {'text': ''},
        'document': {'file_name': name, 'document': archivo()},
      },
    });
    expect(doc('Narcos T1 E01.mkv')!.playable, isTrue);
    expect(doc('Subtitulos.zip')!.playable, isFalse);
  });

  test('sin nombre de archivo usa la primera línea del texto', () {
    final file = TelegramFiles.parseMessage({
      'id': 5,
      'date': 0,
      'content': {
        '@type': 'messageVideo',
        'caption': {'text': 'Breaking Bad T1 E01\nCalidad 1080p'},
        'video': {'video': archivo()},
      },
    })!;
    expect(file.name, 'Breaking Bad T1 E01');
  });

  test('los mensajes sin archivo se ignoran', () {
    expect(
      TelegramFiles.parseMessage({
        'id': 2,
        'date': 0,
        'content': {
          '@type': 'messageText',
          'text': {'text': '¡Hola!'},
        },
      }),
      isNull,
    );
  });

  test('applyFile refleja descarga completada y su ruta local', () {
    final file = TelegramFiles.parseMessage({
      'id': 3,
      'date': 0,
      'content': {
        '@type': 'messageVideo',
        'caption': {'text': ''},
        'video': {'file_name': 'a.mp4', 'video': archivo()},
      },
    })!;
    file.applyFile(
      archivo(downloaded: 1300000000, done: true, path: '/data/tdlib/a.mp4'),
    );
    expect(file.completed, isTrue);
    expect(file.downloading, isFalse);
    expect(file.localPath, '/data/tdlib/a.mp4');
    expect(file.progress, 1);
  });

  test('título del catálogo con temporada y episodio', () {
    final file = TgFile(
      messageId: 1,
      fileId: 2,
      name: 'The Midnight Gospel 1x07.mp4',
      kind: TgFileKind.video,
      date: DateTime(2026),
    );
    expect(file.title, 'The Midnight Gospel 1x07.mp4');
    file.catalog = TgCatalogInfo.fromJson({
      'title': 'The Midnight Gospel',
      'season': 1,
      'episode': 7,
      'poster': '/poster/x.jpg',
    });
    expect(file.title, 'The Midnight Gospel · T1 · E07');
    file.catalog = TgCatalogInfo.fromJson({
      'title': 'Piratas del Caribe',
      'season': null,
      'episode': null,
    });
    expect(file.title, 'Piratas del Caribe');
  });
}
