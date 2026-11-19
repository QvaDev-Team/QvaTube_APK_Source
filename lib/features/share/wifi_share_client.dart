import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/platform/device_channel.dart';
import 'received_store.dart';
import 'wifi_share_protocol.dart';

/// Teléfono que está compartiendo, encontrado en la red.
@immutable
class SharePeer {
  const SharePeer({
    required this.host,
    required this.announce,
    required this.seen,
  });

  final String host;
  final ShareAnnounce announce;
  final DateTime seen;

  String get key => '$host:${announce.port}';
}

class ShareAuthException implements Exception {
  const ShareAuthException();
}

/// Lado que recibe: encuentra teléfonos que comparten, pide la lista y
/// descarga los archivos a `files/qvashare/`.
class WifiShareClient extends ChangeNotifier {
  RawDatagramSocket? _udp;
  Timer? _prune;
  final Map<String, SharePeer> _peers = {};
  HttpClient? _http;

  /// Progreso por id de archivo (0–1) y el que se está recibiendo.
  final Map<String, double> progress = {};
  final Set<String> done = {};
  final Set<String> failed = {};
  String? current;
  bool receiving = false;
  bool _cancel = false;

  List<SharePeer> get peers =>
      _peers.values.toList()
        ..sort((a, b) => a.announce.name.compareTo(b.announce.name));

  Future<void> startDiscovery() async {
    await DeviceChannel.wifiMulticastLock(true);
    try {
      final udp = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        WifiShareProtocol.discoveryPort,
        reuseAddress: true,
      );
      udp.broadcastEnabled = true;
      _udp = udp;
      udp.listen((event) {
        if (event != RawSocketEvent.read) return;
        final d = udp.receive();
        if (d == null) return;
        try {
          final json = jsonDecode(utf8.decode(d.data));
          if (json is! Map) return;
          final a = ShareAnnounce.tryParse(Map<String, dynamic>.from(json));
          if (a == null) return;
          final peer = SharePeer(
            host: d.address.address,
            announce: a,
            seen: DateTime.now(),
          );
          final isNew = !_peers.containsKey(peer.key);
          _peers[peer.key] = peer;
          if (isNew) notifyListeners();
        } catch (_) {}
      });
    } catch (_) {}
    _prune = Timer.periodic(const Duration(seconds: 2), (_) {
      final before = _peers.length;
      _peers.removeWhere(
        (_, p) =>
            DateTime.now().difference(p.seen) > const Duration(seconds: 15),
      );
      if (_peers.length != before) notifyListeners();
    });
  }

  Future<void> stopDiscovery() async {
    _prune?.cancel();
    _udp?.close();
    _udp = null;
    await DeviceChannel.wifiMulticastLock(false);
  }

  @override
  void dispose() {
    unawaited(stopDiscovery());
    _cancel = true;
    _http?.close(force: true);
    super.dispose();
  }

  HttpClient get _client =>
      _http ??= HttpClient()..connectionTimeout = const Duration(seconds: 8);

  /// Lista de lo que comparte [host]. Lanza [ShareAuthException] si el PIN
  /// no es correcto.
  Future<({String name, List<ShareItem> items})> manifest(
    String host,
    int port,
    String pin,
  ) async {
    final req = await _client.get(host, port, '/manifest');
    req.headers.set(WifiShareProtocol.pinHeader, pin);
    final res = await req.close().timeout(const Duration(seconds: 10));
    if (res.statusCode == HttpStatus.unauthorized) {
      await res.drain<void>();
      throw const ShareAuthException();
    }
    final body = await res.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    return (
      name: json['name']?.toString() ?? 'QvaTube',
      items: [
        for (final i in (json['items'] as List? ?? const []))
          ShareItem.fromJson(Map<String, dynamic>.from(i as Map)),
      ],
    );
  }

  /// Descarga [items] uno tras otro. Si se corta, reanuda desde lo que ya
  /// había (`.part`).
  Future<void> receive(
    String host,
    int port,
    String pin,
    List<ShareItem> items,
  ) async {
    receiving = true;
    _cancel = false;
    progress.clear();
    done.clear();
    failed.clear();
    await DeviceChannel.setKeepScreenOn(true);
    notifyListeners();
    final dir = await ReceivedStore.dir();
    for (final item in items) {
      if (_cancel) break;
      current = item.id;
      notifyListeners();
      try {
        await _receiveOne(host, port, pin, item, dir);
        done.add(item.id);
      } catch (_) {
        failed.add(item.id);
      }
      notifyListeners();
    }
    current = null;
    receiving = false;
    await DeviceChannel.setKeepScreenOn(false);
    notifyListeners();
  }

  void cancel() {
    _cancel = true;
    _http?.close(force: true);
    _http = null;
  }

  Future<void> _receiveOne(
    String host,
    int port,
    String pin,
    ShareItem item,
    Directory dir,
  ) async {
    final safe = item.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    var target = File('${dir.path}/$safe');
    if (await target.exists()) {
      target = File(
        '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_$safe',
      );
    }
    final part = File('${target.path}.part');
    var have = await part.exists() ? await part.length() : 0;

    final req = await _client.get(host, port, '/file/${item.id}');
    req.headers.set(WifiShareProtocol.pinHeader, pin);
    if (have > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
    final res = await req.close();
    if (res.statusCode == HttpStatus.ok) {
      have = 0;
    } else if (res.statusCode != HttpStatus.partialContent) {
      await res.drain<void>();
      throw HttpException('HTTP ${res.statusCode}');
    }
    final sink = part.openWrite(
      mode: have > 0 ? FileMode.append : FileMode.write,
    );
    var got = have;
    var last = DateTime.now();
    try {
      await for (final chunk in res) {
        if (_cancel) throw const HttpException('cancelado');
        sink.add(chunk);
        got += chunk.length;
        final now = DateTime.now();
        if (now.difference(last) > const Duration(milliseconds: 250)) {
          last = now;
          progress[item.id] = item.size > 0 ? got / item.size : 0;
          notifyListeners();
        }
      }
    } finally {
      await sink.close();
    }
    if (item.size > 0 && got < item.size) {
      throw const HttpException('incompleto');
    }
    await part.rename(target.path);
    progress[item.id] = 1;
    await ReceivedStore.instance.add(
      ReceivedFile(path: target.path, item: item, receivedAt: DateTime.now()),
    );
  }
}
