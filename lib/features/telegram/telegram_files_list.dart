import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_cached_image.dart';
import '../catalog/application/catalog_providers.dart';
import '../catalog/domain/catalog_models.dart';
import '../home/presentation/widgets/media_player_screen.dart';
import '../reader/book_reader_screen.dart';
import 'telegram_files.dart';
import 'telegram_library.dart';

/// "Mis archivos de Telegram": lo que el bot de QvaTube envió al chat del
/// usuario, para descargarlo cuando quiera y verlo sin conexión.
///
/// Dividido en secciones como el catálogo (Películas, Series, Música…),
/// cada una con buscador y filtro por estado; los episodios se agrupan por
/// serie.
class TelegramFilesList extends ConsumerStatefulWidget {
  const TelegramFilesList({super.key});

  @override
  ConsumerState<TelegramFilesList> createState() => _TelegramFilesListState();
}

class _TelegramFilesListState extends ConsumerState<TelegramFilesList> {
  final TelegramFiles _files = TelegramFiles.instance;
  final TextEditingController _search = TextEditingController();

  TgSection? _section;
  String _query = '';
  TgStatusFilter _status = TgStatusFilter.all;

  /// Series desplegadas (por título en minúsculas).
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _files.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _files.removeListener(_onChanged);
    _search.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    // Título y carátula del catálogo (lo enviado con el gestor de
    // descargas). Sin conexión con QvaTube se muestran los nombres de
    // archivo de Telegram.
    unawaited(
      ref
          .read(catalogApiProvider)
          .telegramFiles()
          .then(_files.applyCatalog)
          .catchError((_) {}),
    );
    final config = await ref
        .read(siteConfigProvider.future)
        .catchError((_) => const SiteConfig());
    await _files.load(config.botUsername ?? 'qvatube_bot');
  }

  /// Reproduce [file] y, a continuación, los demás ya descargados de
  /// [queue] (episodios de la misma serie, pistas de la sección…).
  void _play(TgFile file, [List<TgFile>? queue]) {
    final items = (queue ?? [file])
        .where((f) => f.completed && f.playable)
        .toList();
    if (!items.contains(file)) items.insert(0, file);
    openMediaPlayer(
      context,
      initialIndex: items.indexOf(file),
      playlist: [
        for (final f in items)
          PlayableMediaItem(
            chatId: 0,
            msgId: f.messageId,
            title: f.title,
            isAudio: f.kind == TgFileKind.audio,
            localPath: f.localPath,
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
          '${file.title} se borrará de tu teléfono para liberar espacio. '
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
              onPressed: _files.loading || _files.syncing ? null : _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_files.syncing && files.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_files.loading && files.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_files.waitingForConnection)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Conectando con Telegram… Tus archivos aparecerán en '
                    'cuanto haya conexión.',
                    style: AppTextStyles.body(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
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
          _note(
            'Todavía no hay archivos. Toca "Descargar" en una película o '
            'serie y el bot te los enviará: aparecerán aquí.',
          )
        else
          ..._library(files),
      ],
    );
  }

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(
      text,
      style: AppTextStyles.body(
        fontSize: 13,
        color: AppColors.textSecondary,
        height: 1.45,
      ),
    ),
  );

  /// Secciones, buscador, filtro y el contenido de la sección elegida.
  List<Widget> _library(List<TgFile> files) {
    final counts = sectionCounts(files);
    final section = counts.containsKey(_section)
        ? _section!
        : counts.keys.first;
    final visible = filterFiles(
      files,
      section: section,
      query: _query,
      status: _status,
    );

    return [
      SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final entry in counts.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _Pill(
                  label: entry.key.label,
                  count: entry.value,
                  selected: entry.key == section,
                  onTap: () => setState(() => _section = entry.key),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _search,
        onChanged: (v) => setState(() => _query = v),
        textInputAction: TextInputAction.search,
        style: AppTextStyles.body(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Buscar en ${section.label}',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Borrar búsqueda',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() {
                    _search.clear();
                    _query = '';
                  }),
                ),
          isDense: true,
          filled: true,
          fillColor: AppColors.surfaceSecondary,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            borderSide: const BorderSide(color: AppColors.border),
          ),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final s in TgStatusFilter.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _Pill(
                  label: s.label,
                  selected: s == _status,
                  small: true,
                  onTap: () => setState(() => _status = s),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      if (visible.isEmpty)
        _note(
          _query.isNotEmpty
              ? 'Nada en ${section.label} coincide con "$_query".'
              : 'No hay archivos en ${section.label} con este filtro.',
        )
      else if (section.groupsBySeries)
        for (final group in groupSeries(visible)) ...[
          _seriesCard(group),
          const SizedBox(height: 10),
        ]
      else
        for (final file in visible) ...[
          _tile(file, queue: visible),
          const SizedBox(height: 10),
        ],
    ];
  }

  Widget _tile(TgFile file, {List<TgFile>? queue, String? title}) => _FileTile(
    file: file,
    title: title,
    onDownload: () => _files.download(file),
    onPause: () => _files.pause(file),
    onPlay: () => _play(file, queue),
    onRead: () => openBookReader(
      context,
      chatId: 0,
      msgId: file.messageId,
      title: file.title,
      localPath: file.localPath,
    ),
    onRemove: () => _confirmRemove(file),
  );

  /// Tarjeta de una serie: carátula, episodios y cuántos están en el
  /// teléfono; al tocarla se despliegan los episodios.
  Widget _seriesCard(TgSeriesGroup group) {
    final key = group.title.toLowerCase();
    final open = _expanded.contains(key) || _query.isNotEmpty;
    final pending = group.episodes
        .where((e) => !e.completed && !e.downloading)
        .toList();
    final poster = absoluteMediaUrl(group.poster);
    final placeholder = const ColoredBox(
      color: AppColors.surface,
      child: Icon(Icons.live_tv, color: AppColors.accent, size: 22),
    );
    final count = group.episodes.length;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadii.md),
            onTap: () => setState(() {
              if (!_expanded.remove(key)) _expanded.add(key);
            }),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 46,
                      height: 66,
                      child: poster.isEmpty
                          ? placeholder
                          : AppCachedImage(
                              imageUrl: poster,
                              placeholder: placeholder,
                              errorWidget: placeholder,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$count ${count == 1 ? 'episodio' : 'episodios'} · '
                          '${group.downloadedCount} en el teléfono',
                          style: AppTextStyles.body(
                            fontSize: 12,
                            color: group.downloadedCount == count
                                ? AppColors.success
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (pending.isNotEmpty)
                    IconButton(
                      tooltip: 'Descargar los ${pending.length} pendientes',
                      onPressed: () {
                        for (final e in pending) {
                          _files.download(e);
                        }
                      },
                      icon: const Icon(
                        Icons.download_for_offline_outlined,
                        color: AppColors.accent,
                        size: 28,
                      ),
                    ),
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                children: [
                  for (final e in group.episodes) ...[
                    _tile(e, queue: group.episodes, title: _episodeTitle(e)),
                    const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// "T1 · E07" si se sabe el episodio; si no, el nombre del archivo.
  static String _episodeTitle(TgFile f) {
    final ep = episodeOf(f);
    if (ep == null) return f.title;
    return 'T${ep.season} · E${ep.episode.toString().padLeft(2, '0')}';
  }
}

/// Botón tipo píldora para secciones y filtros.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.small = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accent : AppColors.surfaceSecondary,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? AppColors.accent : AppColors.border),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: small ? 12 : 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTextStyles.body(
                  fontSize: small ? 12 : 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.textSecondary,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: AppTextStyles.body(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: selected
                        ? Colors.white.withValues(alpha: 0.85)
                        : AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.file,
    this.title,
    required this.onDownload,
    required this.onPause,
    required this.onPlay,
    required this.onRead,
    required this.onRemove,
  });

  final TgFile file;

  /// Título a mostrar en lugar de [TgFile.title] (p. ej. "T1 · E07"
  /// dentro de la tarjeta de su serie).
  final String? title;
  final VoidCallback onDownload;
  final VoidCallback onPause;
  final VoidCallback onPlay;
  final VoidCallback onRead;
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
      // Recién empezada todavía no hay bytes: "0 MB", no "—".
      final done = file.downloaded > 0 ? _size(file.downloaded) : '0 MB';
      return '$done de ${_size(file.size)} · '
          '${(file.progress * 100).floor()} %';
    }
    if (file.downloaded > 0) {
      return 'En pausa · ${_size(file.downloaded)} de ${_size(file.size)}';
    }
    return _size(file.size);
  }

  /// Carátula del catálogo; si no hay, la miniatura que trae el mensaje
  /// de Telegram; si tampoco, un icono.
  Widget _thumb(IconData icon) {
    final fallback = ColoredBox(
      color: AppColors.surface,
      child: Icon(icon, color: AppColors.accent, size: 22),
    );
    final thumb = file.thumbnail;
    final local = thumb != null
        ? Image.memory(thumb, fit: BoxFit.cover, gaplessPlayback: true)
        : fallback;
    final poster = absoluteMediaUrl(file.catalog?.poster);
    if (poster.isEmpty) return local;
    return AppCachedImage(
      imageUrl: poster,
      placeholder: local,
      errorWidget: local,
    );
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
          if (!file.playable && file.readable)
            IconButton(
              tooltip: 'Leer',
              onPressed: onRead,
              icon: const Icon(
                Icons.menu_book_rounded,
                color: AppColors.accent,
                size: 28,
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
                child: SizedBox(width: 46, height: 46, child: _thumb(icon)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title ?? file.title,
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
