import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../catalog/application/catalog_providers.dart';
import '../catalog/domain/catalog_models.dart';
import '../home/presentation/widgets/media_player_screen.dart';
import 'telegram_files.dart';

/// "Mis archivos de Telegram": lo que el bot de QvaTube envió al chat del
/// usuario, para descargarlo cuando quiera y verlo sin conexión.
class TelegramFilesList extends ConsumerStatefulWidget {
  const TelegramFilesList({super.key});

  @override
  ConsumerState<TelegramFilesList> createState() => _TelegramFilesListState();
}

class _TelegramFilesListState extends ConsumerState<TelegramFilesList> {
  final TelegramFiles _files = TelegramFiles.instance;

  @override
  void initState() {
    super.initState();
    _files.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _files.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    final config = await ref
        .read(siteConfigProvider.future)
        .catchError((_) => const SiteConfig());
    await _files.load(config.botUsername ?? 'qvatube_bot');
  }

  void _play(TgFile file) {
    openMediaPlayer(
      context,
      playlist: [
        PlayableMediaItem(
          chatId: 0,
          msgId: file.messageId,
          title: file.name,
          isAudio: file.kind == TgFileKind.audio,
          localPath: file.localPath,
        ),
      ],
    );
  }

  Future<void> _confirmRemove(TgFile file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar del teléfono'),
        content: Text(
          '${file.name} se borrará de tu teléfono para liberar espacio. '
          'Sigue en el chat del bot por si lo quieres descargar otra vez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok == true) await _files.remove(file);
  }

  @override
  Widget build(BuildContext context) {
    final files = _files.files;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Archivos del bot',
                style: AppTextStyles.body(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _files.loading ? null : _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_files.loading && files.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_files.error != null && files.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              _files.error!,
              style: AppTextStyles.body(fontSize: 13, color: AppColors.danger),
            ),
          )
        else if (files.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Todavía no hay archivos. Toca "Descargar" en una película o '
              'serie y el bot te los enviará: aparecerán aquí.',
              style: AppTextStyles.body(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          )
        else
          for (final file in files) ...[
            _FileTile(
              file: file,
              onDownload: () => _files.download(file),
              onPause: () => _files.pause(file),
              onPlay: () => _play(file),
              onRemove: () => _confirmRemove(file),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.file,
    required this.onDownload,
    required this.onPause,
    required this.onPlay,
    required this.onRemove,
  });

  final TgFile file;
  final VoidCallback onDownload;
  final VoidCallback onPause;
  final VoidCallback onPlay;
  final VoidCallback onRemove;

  static String _size(int bytes) {
    if (bytes <= 0) return '—';
    const mb = 1024 * 1024;
    if (bytes >= 1024 * mb) {
      return '${(bytes / (1024 * mb)).toStringAsFixed(2)} GB';
    }
    return '${(bytes / mb).toStringAsFixed(bytes >= 100 * mb ? 0 : 1)} MB';
  }

  String get _status {
    if (file.completed) return 'Descargado · ${_size(file.size)}';
    if (file.downloading) {
      return '${_size(file.downloaded)} de ${_size(file.size)} · '
          '${(file.progress * 100).floor()} %';
    }
    if (file.downloaded > 0) {
      return 'En pausa · ${_size(file.downloaded)} de ${_size(file.size)}';
    }
    return _size(file.size);
  }

  @override
  Widget build(BuildContext context) {
    final icon = switch (file.kind) {
      TgFileKind.video => Icons.movie_outlined,
      TgFileKind.audio => Icons.music_note,
      TgFileKind.document => Icons.insert_drive_file_outlined,
    };
    final Widget action;
    if (file.completed) {
      action = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (file.playable)
            IconButton(
              tooltip: 'Ver',
              onPressed: onPlay,
              icon: const Icon(
                Icons.play_circle_fill,
                color: AppColors.accent,
                size: 30,
              ),
            ),
          IconButton(
            tooltip: 'Borrar del teléfono',
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline, color: AppColors.textMuted),
          ),
        ],
      );
    } else if (file.downloading) {
      action = IconButton(
        tooltip: 'Pausar',
        onPressed: onPause,
        icon: const Icon(
          Icons.pause_circle_outline,
          color: Colors.white,
          size: 30,
        ),
      );
    } else {
      action = IconButton(
        tooltip: file.downloaded > 0 ? 'Reanudar' : 'Descargar',
        onPressed: onDownload,
        icon: Icon(
          file.downloaded > 0
              ? Icons.play_for_work
              : Icons.download_for_offline_outlined,
          color: AppColors.accent,
          size: 30,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: file.thumbnail != null
                      ? Image.memory(
                          file.thumbnail!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        )
                      : ColoredBox(
                          color: AppColors.surface,
                          child: Icon(icon, color: AppColors.accent, size: 22),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _status,
                      style: AppTextStyles.body(
                        fontSize: 11.5,
                        color: file.completed
                            ? AppColors.success
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              action,
            ],
          ),
          if (file.downloading || (file.downloaded > 0 && !file.completed)) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: file.progress,
              minHeight: 3,
              color: file.downloading ? AppColors.accent : AppColors.textMuted,
              backgroundColor: AppColors.border,
            ),
          ],
        ],
      ),
    );
  }
}
