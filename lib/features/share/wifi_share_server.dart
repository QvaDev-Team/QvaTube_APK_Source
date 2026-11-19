import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/platform/device_channel.dart';
import '../telegram/telegram_files.dart';
import 'wifi_share_protocol.dart';

/// Lado que envía: servidor HTTP local + anuncio por UDP.
class WifiShareServer extends ChangeNotifier {
  WifiShareServer({required this.deviceName});

  final String deviceName;

  HttpServer? _server;
  RawDatagramSocket? _udp;
  Timer? _announceTimer;
  final Map<String, ({ShareItem item, String path})> _items = {};

  /// Bytes enviados por archivo (suma de todas las descargas).
  final Map<String, int> sent = {};

  /// Teléfonos que se conectaron (IP).
  final Set<String> peers = {};

  String pin = '';

  /// Red del punto de acceso local creado al compartir (o null).
  String? hotspotSsid;
  String? hotspotPassword;

  /// Por qué no se pudo crear (`permission`, `location_off`…).
  String? hotspotError;
  List<String> addresses = const [];

  bool get running => _server != null;
  int get port => _server?.port ?? 0;
  List<ShareItem> get items => [for (final e in _items.values) e.item];
  int get totalSize => _items.values.fold(0, (s, e) => s + e.item.size);

  Future<void> start(List<TgFile> files) async {
    await stop();
    _items.clear();
    sent.clear();
    peers.clear();
    for (final (i, f) in files.indexed) {
      if (f.localPath.isEmpty) continue;
      final id = '$i';
      _items[id] = (item: ShareItem.fromTgFile(id, f), path: f.localPath);
    }
    pin = (Random.secure().nextInt(9000) + 1000).toString();
    // Punto de acceso local: el otro teléfono se conecta a él al escanear
    // el QR, sin necesitar un router ni ir a los ajustes de Wi-Fi.
    hotspotSsid = null;
    hotspotPassword = null;
    hotspotError = null;
    if (Platform.isAndroid) {
      if (await DeviceChannel.shareHotspotPermission()) {
        final hs = await DeviceChannel.startShareHotspot();
        hotspotError = hs.error;
        if (hs.error == null && (hs.ssid ?? '').isNotEmpty) {
          hotspotSsid = hs.ssid;
          hotspotPassword = hs.password;
          // La interfaz del punto de acceso tarda un momento en tener IP.
          for (var i = 0; i < 10; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            if ((await localAddresses()).isNotEmpty) break;
          }
        }
      } else {
        hotspotError = 'permission';
      }
    }
    addresses = await localAddresses();

    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    server.listen(_handle, onError: (_) {});

    final udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    udp.broadcastEnabled = true;
    _udp = udp;
    _announce();
    _announceTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _announce(),
    );
    await DeviceChannel.setKeepScreenOn(true);
    await _updateNotification();
    notifyListeners();
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _announceTimer = null;
    _udp?.close();
    _udp = null;
    final s = _server;
    _server = null;
    await s?.close(force: true);
    if (hotspotSsid != null) await DeviceChannel.stopShareHotspot();
    await DeviceChannel.shareNotification(on: false);
    hotspotSsid = null;
    hotspotPassword = null;
    await DeviceChannel.setKeepScreenOn(false);
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }

  void _announce() {
    final udp = _udp;
    final server = _server;
    if (udp == null || server == null) return;
    final data = utf8.encode(
      jsonEncode(
        ShareAnnounce(
          name: deviceName,
          port: server.port,
          count: _items.length,
          size: totalSize,
        ).toJson(),
      ),
    );
    final targets = <String>{
      '255.255.255.255',
      for (final a in addresses) a.replaceFirst(RegExp(r'\.\d+$'), '.255'),
    };
    for (final t in targets) {
      try {
        udp.send(data, InternetAddress(t), WifiShareProtocol.discoveryPort);
      } catch (_) {}
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      if (req.headers.value(WifiShareProtocol.pinHeader) != pin) {
        res.statusCode = HttpStatus.unauthorized;
        await res.close();
        return;
      }
      final peer = req.connectionInfo?.remoteAddress.address;
      if (peer != null && peers.add(peer)) {
        notifyListeners();
        unawaited(_updateNotification());
      }

      final segments = req.uri.pathSegments;
      if (segments.length == 1 && segments.first == 'manifest') {
        res.headers.contentType = ContentType.json;
        res.write(
          jsonEncode({
            'name': deviceName,
            'items': [for (final i in items) i.toJson()],
          }),
        );
        await res.close();
        return;
      }
      if (segments.length == 2 && segments.first == 'file') {
        await _sendFile(req, segments[1]);
        return;
      }
      res.statusCode = HttpStatus.notFound;
      await res.close();
    } catch (_) {
      try {
        await res.close();
      } catch (_) {}
    }
  }

  Future<void> _sendFile(HttpRequest req, String id) async {
    final res = req.response;
    final entry = _items[id];
    final file = entry == null ? null : File(entry.path);
    if (entry == null || file == null || !await file.exists()) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    final length = await file.length();
    var start = 0;
    final range = req.headers.value(HttpHeaders.rangeHeader);
    final m = range == null ? null : RegExp(r'bytes=(\d+)-').firstMatch(range);
    if (m != null) {
      start = int.parse(m.group(1)!).clamp(0, length);
      res.statusCode = HttpStatus.partialContent;
      res.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-${length - 1}/$length',
      );
    }
    res.headers
      ..contentType = ContentType.binary
      ..contentLength = length - start
      ..set(HttpHeaders.acceptRangesHeader, 'bytes');
    var last = DateTime.now();
    await res.addStream(
      file.openRead(start).map((chunk) {
        sent[id] = (sent[id] ?? 0) + chunk.length;
        final now = DateTime.now();
        if (now.difference(last) > const Duration(milliseconds: 300)) {
          last = now;
          notifyListeners();
        }
        return chunk;
      }),
    );
    await res.close();
    notifyListeners();
  }

  /// Notificación fija: red creada, PIN y si ya hay alguien conectado.
  Future<void> _updateNotification() async {
    final n = _items.length;
    final what = n == 1 ? '1 archivo' : '$n archivos';
    final who = peers.isEmpty
        ? 'PIN $pin · esperando al otro teléfono'
        : peers.length == 1
        ? 'Un teléfono conectado'
        : '${peers.length} teléfonos conectados';
    await DeviceChannel.shareNotification(
      on: true,
      network: hotspotSsid,
      text: '$what · $who',
    );
  }

  /// IPs locales (IPv4) de Wi-Fi o punto de acceso.
  static Future<List<String>> localAddresses() async {
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      final out = <String>[];
      for (final i in ifaces) {
        // rmnet/ccmni = datos móviles: no sirven para compartir.
        if (RegExp(r'^(rmnet|ccmni|dummy|lo)').hasMatch(i.name)) continue;
        for (final a in i.addresses) {
          if (!a.isLoopback) out.add(a.address);
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}
