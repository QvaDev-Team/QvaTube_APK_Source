import 'package:flutter/material.dart';

import '../../core/platform/device_channel.dart';
import '../../core/storage/download_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';

/// Gestor de descargas → "Ubicación de almacenamiento": elegir si los
/// archivos se guardan en la memoria interna o en la tarjeta SD.
class StorageLocationScreen extends StatefulWidget {
  const StorageLocationScreen({super.key});

  @override
  State<StorageLocationScreen> createState() => _StorageLocationScreenState();
}

class _StorageLocationScreenState extends State<StorageLocationScreen> {
  List<StorageVolume> _volumes = const [];
  String? _selected;
  String? _root;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final volumes = await DeviceChannel.storageVolumes();
    final selected = await DownloadStorage.selectedPath();
    final root = await DownloadStorage.root();
    if (!mounted) return;
    setState(() {
      _volumes = volumes;
      _selected = selected;
      _root = root;
      _loading = false;
    });
  }

  /// Volumen marcado: el elegido, o la memoria interna por defecto.
  String? get _currentPath {
    final sel = _selected;
    if (sel != null) return sel;
    for (final v in _volumes) {
      if (!v.removable) return v.path;
    }
    return null;
  }

  /// La SD elegida no está montada ahora mismo.
  bool get _selectedMissing =>
      _selected != null && !_volumes.any((v) => v.path == _selected);

  Future<void> _choose(StorageVolume volume) async {
    if (_saving || volume.path == _currentPath) return;
    setState(() => _saving = true);
    if (volume.removable && !await DownloadStorage.isWritable(volume.path)) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se puede escribir en la tarjeta SD.'),
        ),
      );
      return;
    }
    await DownloadStorage.select(volume.removable ? volume.path : null);
    await _load();
    if (!mounted) return;
    setState(() => _saving = false);

    // Telegram solo lee la carpeta al arrancar: hay que reiniciar la app.
    final active = DownloadStorage.telegramRoot;
    if (active != null && active != _root) {
      await _askRestart(volume.label);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Las descargas se guardarán en ${volume.label}.')),
      );
    }
  }

  Future<void> _askRestart(String label) async {
    final restart = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reiniciar la app'),
        content: Text(
          'Las nuevas descargas se guardarán en $label después de reiniciar '
          'QvaTube. Lo que ya descargaste se queda donde está y lo sigues '
          'viendo normal en el gestor.\n\n'
          'Si hay descargas en curso, se reanudarán al volver a abrir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Más tarde'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reiniciar ahora'),
          ),
        ],
      ),
    );
    if (restart == true) await DeviceChannel.restartApp();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Ubicación de almacenamiento'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: _body(),
              ),
            ),
    );
  }

  List<Widget> _body() {
    final hasSd = _volumes.any((v) => v.removable);
    final root = _root;
    return [
      _sectionTitle('Guardar descargas en'),
      for (final v in _volumes) ...[
        _VolumeTile(
          volume: v,
          selected: v.path == _currentPath,
          enabled: !_saving,
          onTap: () => _choose(v),
        ),
        const SizedBox(height: 10),
      ],
      if (_selectedMissing)
        _note(
          Icons.warning_amber_rounded,
          'La tarjeta SD elegida no está disponible. Mientras tanto, las '
          'descargas se guardan en el almacenamiento interno.',
          color: const Color(0xFFFFB020),
        )
      else if (!hasSd)
        _note(
          Icons.sd_card_alert_outlined,
          'No se detectó ninguna tarjeta SD. Insértala y desliza hacia abajo '
          'para volver a buscar.',
        ),
      if (root != null) ...[
        const SizedBox(height: 24),
        _sectionTitle('Detalles de ubicación'),
        _PathTile(
          icon: Icons.send_outlined,
          title: 'Descargas de Telegram',
          path: DownloadStorage.telegramFilesDir(root),
        ),
        _PathTile(
          icon: Icons.wifi,
          title: 'Recibido por Wi-Fi',
          path: DownloadStorage.receivedDir(root),
        ),
      ],
      const SizedBox(height: 16),
      _note(
        Icons.info_outline,
        'En la tarjeta SD los archivos se guardan en la carpeta de QvaTube '
        '(Android/data). Se borran si desinstalas la app.',
      ),
    ];
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 8),
    child: Text(
      text,
      style: AppTextStyles.body(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    ),
  );

  Widget _note(IconData icon, String text, {Color? color}) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color ?? AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.body(
              fontSize: 11.5,
              color: color ?? AppColors.textMuted,
            ),
          ),
        ),
      ],
    ),
  );
}

class _VolumeTile extends StatelessWidget {
  const _VolumeTile({
    required this.volume,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final StorageVolume volume;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final total = volume.totalBytes;
    final used = total > 0 ? (total - volume.freeBytes) / total : 0.0;
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? AppColors.accent : AppColors.textMuted,
              ),
              const SizedBox(width: 12),
              Icon(
                volume.removable ? Icons.sd_card_outlined : Icons.smartphone,
                size: 22,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      volume.label,
                      style: AppTextStyles.body(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (total > 0) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: used.clamp(0.0, 1.0),
                          minHeight: 5,
                          backgroundColor: AppColors.border,
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${_size(volume.freeBytes)} libres de ${_size(total)}',
                        style: AppTextStyles.body(
                          fontSize: 11.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _size(int bytes) {
    const gb = 1024 * 1024 * 1024;
    const mb = 1024 * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
    return '${(bytes / mb).toStringAsFixed(0)} MB';
  }
}

class _PathTile extends StatelessWidget {
  const _PathTile({
    required this.icon,
    required this.title,
    required this.path,
  });

  final IconData icon;
  final String title;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppColors.textSecondary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.body(fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  path,
                  style: AppTextStyles.body(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
