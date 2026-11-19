import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../auth/presentation/providers/auth_controller.dart';
import '../telegram/telegram_files.dart';
import 'received_store.dart';
import 'wifi_share_client.dart';
import 'wifi_share_protocol.dart';
import 'wifi_share_server.dart';

String _size(int bytes) {
  if (bytes <= 0) return '—';
  const mb = 1024 * 1024;
  if (bytes >= 1024 * mb) {
    return '${(bytes / (1024 * mb)).toStringAsFixed(2)} GB';
  }
  return '${(bytes / mb).toStringAsFixed(bytes >= 100 * mb ? 0 : 1)} MB';
}

/// "Compartir por Wi-Fi": pasar contenido descargado de QvaTube a otro
/// teléfono con QvaTube en la misma red (o en el punto de acceso de uno de
/// los dos), sin internet.
class WifiShareScreen extends StatelessWidget {
  const WifiShareScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(LucideIcons.arrowLeft),
          ),
          title: const Text('Compartir por Wi-Fi'),
          bottom: const TabBar(
            indicatorColor: AppColors.accent,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textMuted,
            tabs: [
              Tab(icon: Icon(LucideIcons.send, size: 18), text: 'Enviar'),
              Tab(icon: Icon(LucideIcons.inbox, size: 18), text: 'Recibir'),
            ],
          ),
        ),
        body: const TabBarView(children: [_SendTab(), _ReceiveTab()]),
      ),
    );
  }
}

Widget _hint(IconData icon, String text) => Container(
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: AppColors.surfaceSecondary,
    borderRadius: BorderRadius.circular(AppRadii.md),
    border: Border.all(color: AppColors.border),
  ),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 20, color: AppColors.accent),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          text,
          style: AppTextStyles.body(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.45,
          ),
        ),
      ),
    ],
  ),
);

// ── Enviar ──────────────────────────────────────────────────────────────

class _SendTab extends ConsumerStatefulWidget {
  const _SendTab();

  @override
  ConsumerState<_SendTab> createState() => _SendTabState();
}

class _SendTabState extends ConsumerState<_SendTab>
    with AutomaticKeepAliveClientMixin {
  final Set<TgFile> _selected = {};
  WifiShareServer? _server;
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _server?.dispose();
    super.dispose();
  }

  List<TgFile> get _available =>
      TelegramFiles.instance.files
          .where((f) => f.completed && f.localPath.isNotEmpty)
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  Future<void> _start() async {
    final name = ref.read(authControllerProvider).user?.name ?? 'QvaTube';
    final server = WifiShareServer(deviceName: name);
    server.addListener(() {
      if (mounted) setState(() {});
    });
    try {
      await server.start(_selected.toList());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo empezar a compartir.')),
      );
      return;
    }
    setState(() => _server = server);
  }

  Future<void> _stop() async {
    final s = _server;
    setState(() => _server = null);
    await s?.stop();
    s?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final server = _server;
    if (server != null && server.running) return _sharing(server);

    final all = _available;
    final q = _query.trim().toLowerCase();
    final files = q.isEmpty
        ? all
        : all.where((f) => f.title.toLowerCase().contains(q)).toList();
    final total = _selected.fold<int>(0, (s, f) => s + f.size);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            children: [
              _hint(
                LucideIcons.wifi,
                'Elige lo que quieres pasar. El otro teléfono necesita '
                'QvaTube y estar en la misma red Wi-Fi o conectado a tu '
                'punto de acceso. No gasta datos.',
              ),
              const SizedBox(height: 14),
              if (all.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Todavía no tienes nada descargado en el teléfono.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              else ...[
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Buscar',
                    prefixIcon: const Icon(LucideIcons.search, size: 18),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.surfaceSecondary,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() {
                      if (_selected.length == all.length) {
                        _selected.clear();
                      } else {
                        _selected
                          ..clear()
                          ..addAll(all);
                      }
                    }),
                    child: Text(
                      _selected.length == all.length
                          ? 'Quitar todo'
                          : 'Seleccionar todo',
                    ),
                  ),
                ),
                for (final f in files)
                  CheckboxListTile(
                    value: _selected.contains(f),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(f);
                      } else {
                        _selected.remove(f);
                      }
                    }),
                    activeColor: AppColors.accent,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      f.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      _size(f.size),
                      style: AppTextStyles.body(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                minimumSize: const Size.fromHeight(50),
              ),
              onPressed: _selected.isEmpty ? null : _start,
              icon: const Icon(LucideIcons.share2, size: 18),
              label: Text(
                _selected.isEmpty
                    ? 'Elige qué compartir'
                    : 'Compartir ${_selected.length} · ${_size(total)}',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sharing(WifiShareServer server) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        Center(
          child: Text(
            'PIN para recibir',
            style: AppTextStyles.body(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            server.pin.split('').join(' '),
            style: AppTextStyles.mono(
              fontSize: 44,
              fontWeight: FontWeight.w800,
              color: AppColors.accent,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _hint(
          LucideIcons.smartphone,
          'En el otro teléfono: QvaTube → Gestor de descargas → '
          'Compartir por Wi-Fi → Recibir. Toca "${server.deviceName}" y '
          'escribe este PIN.',
        ),
        const SizedBox(height: 10),
        if (server.addresses.isEmpty)
          _hint(
            LucideIcons.triangleAlert,
            'No estás en una red Wi-Fi. Conéctate a una o activa tu punto '
            'de acceso y que el otro teléfono se conecte a él.',
          )
        else
          Text(
            'Dirección: ${server.addresses.first}:${server.port}',
            textAlign: TextAlign.center,
            style: AppTextStyles.body(fontSize: 12, color: AppColors.textMuted),
          ),
        const SizedBox(height: 18),
        Text(
          server.peers.isEmpty
              ? 'Esperando al otro teléfono…'
              : server.peers.length == 1
              ? 'Un teléfono conectado'
              : '${server.peers.length} teléfonos conectados',
          style: AppTextStyles.body(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        for (final item in server.items) ...[
          _ProgressRow(
            title: item.displayTitle,
            size: item.size,
            value: item.size > 0
                ? ((server.sent[item.id] ?? 0) / item.size).clamp(0.0, 1.0)
                : 0,
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _stop,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          icon: const Icon(LucideIcons.x, size: 18),
          label: const Text('Dejar de compartir'),
        ),
      ],
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.title,
    required this.size,
    required this.value,
    this.state,
  });

  final String title;
  final int size;
  final double value;
  final String? state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            state ?? '${_size((size * value).round())} de ${_size(size)}',
            style: AppTextStyles.body(
              fontSize: 11.5,
              color: value >= 1 ? AppColors.success : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: value,
            minHeight: 3,
            color: value >= 1 ? AppColors.success : AppColors.accent,
            backgroundColor: AppColors.border,
          ),
        ],
      ),
    );
  }
}

// ── Recibir ─────────────────────────────────────────────────────────────

class _ReceiveTab extends StatefulWidget {
  const _ReceiveTab();

  @override
  State<_ReceiveTab> createState() => _ReceiveTabState();
}

class _ReceiveTabState extends State<_ReceiveTab>
    with AutomaticKeepAliveClientMixin {
  final WifiShareClient _client = WifiShareClient();

  ({String host, int port, String pin, String name})? _peer;
  List<ShareItem> _items = const [];
  final Set<String> _selected = {};
  bool _loading = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _client.addListener(_changed);
    unawaited(_client.startDiscovery());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _client.removeListener(_changed);
    _client.dispose();
    super.dispose();
  }

  Future<void> _connect(String host, int port, String name) async {
    final pin = await _askPin(name);
    if (pin == null || !mounted) return;
    setState(() => _loading = true);
    try {
      final m = await _client.manifest(host, port, pin);
      if (!mounted) return;
      setState(() {
        _peer = (host: host, port: port, pin: pin, name: m.name);
        _items = m.items;
        _selected
          ..clear()
          ..addAll([
            for (final i in m.items)
              if (!ReceivedStore.instance.has(i)) i.id,
          ]);
      });
    } on ShareAuthException {
      _snack('PIN incorrecto.');
    } catch (_) {
      _snack('No se pudo conectar con $name.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<String?> _askPin(String name) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Recibir de $name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'PIN',
            helperText: 'El que se ve en el otro teléfono',
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text),
            child: const Text('Conectar'),
          ),
        ],
      ),
    );
  }

  Future<void> _manual() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conectar con dirección'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: '192.168.1.5:40123',
            helperText: 'La "Dirección" que se ve en el otro teléfono',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text),
            child: const Text('Seguir'),
          ),
        ],
      ),
    );
    final m = RegExp(r'^\s*([\d.]+):(\d+)\s*$').firstMatch(text ?? '');
    if (m == null) {
      if (text != null && text.isNotEmpty) _snack('Dirección no válida.');
      return;
    }
    await _connect(m.group(1)!, int.parse(m.group(2)!), m.group(1)!);
  }

  Future<void> _receive() async {
    final peer = _peer;
    if (peer == null) return;
    final items = [
      for (final i in _items)
        if (_selected.contains(i.id)) i,
    ];
    await _client.receive(peer.host, peer.port, peer.pin, items);
    if (!mounted) return;
    final ok = _client.done.length;
    final bad = _client.failed.length;
    _snack(
      bad == 0
          ? '$ok ${ok == 1 ? 'archivo recibido' : 'archivos recibidos'}: '
                'ya están en tu gestor de descargas.'
          : '$ok recibidos, $bad no se pudieron recibir. Vuelve a intentarlo '
                'para continuarlos.',
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final peer = _peer;
    if (peer != null) return _manifestView(peer.name);

    final peers = _client.peers;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        _hint(
          LucideIcons.radar,
          'Busca teléfonos que estén compartiendo en tu red Wi-Fi (o en el '
          'punto de acceso al que estás conectado).',
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              peers.isEmpty ? 'Buscando…' : 'Teléfonos encontrados',
              style: AppTextStyles.body(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        for (final p in peers)
          Card(
            color: AppColors.surfaceSecondary,
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              side: const BorderSide(color: AppColors.border),
            ),
            child: ListTile(
              leading: const Icon(
                LucideIcons.smartphone,
                color: AppColors.accent,
              ),
              title: Text(
                p.announce.name,
                style: AppTextStyles.body(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                '${p.announce.count} '
                '${p.announce.count == 1 ? 'archivo' : 'archivos'} · '
                '${_size(p.announce.size)}',
                style: AppTextStyles.body(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
              trailing: const Icon(LucideIcons.chevronRight, size: 18),
              onTap: _loading
                  ? null
                  : () => _connect(p.host, p.announce.port, p.announce.name),
            ),
          ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _loading ? null : _manual,
          icon: const Icon(LucideIcons.keyRound, size: 16),
          label: const Text('¿No aparece? Conectar con la dirección'),
        ),
      ],
    );
  }

  Widget _manifestView(String name) {
    final receiving = _client.receiving;
    final total = _items
        .where((i) => _selected.contains(i.id))
        .fold<int>(0, (s, i) => s + i.size);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            children: [
              Text(
                'De $name',
                style: AppTextStyles.body(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              for (final item in _items)
                if (receiving ||
                    _client.done.contains(item.id) ||
                    _client.failed.contains(item.id))
                  if (_selected.contains(item.id)) ...[
                    _ProgressRow(
                      title: item.displayTitle,
                      size: item.size,
                      value: _client.progress[item.id] ?? 0,
                      state: _client.failed.contains(item.id)
                          ? 'No se pudo recibir'
                          : _client.done.contains(item.id)
                          ? 'Recibido'
                          : null,
                    ),
                    const SizedBox(height: 8),
                  ] else
                    const SizedBox.shrink()
                else
                  CheckboxListTile(
                    value: _selected.contains(item.id),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(item.id);
                      } else {
                        _selected.remove(item.id);
                      }
                    }),
                    activeColor: AppColors.accent,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      item.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      ReceivedStore.instance.has(item)
                          ? '${_size(item.size)} · ya lo tienes'
                          : _size(item.size),
                      style: AppTextStyles.body(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: receiving
                ? OutlinedButton.icon(
                    onPressed: _client.cancel,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    icon: const Icon(LucideIcons.x, size: 18),
                    label: const Text('Cancelar'),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setState(() {
                            _peer = null;
                            _items = const [];
                          }),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                          ),
                          child: const Text('Atrás'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            minimumSize: const Size.fromHeight(50),
                          ),
                          onPressed: _selected.isEmpty ? null : _receive,
                          icon: const Icon(LucideIcons.download, size: 18),
                          label: Text(
                            _selected.isEmpty
                                ? 'Elige qué recibir'
                                : 'Recibir ${_selected.length} · ${_size(total)}',
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
