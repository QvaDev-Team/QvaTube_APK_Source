import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/endpoints/media_endpoints.dart';
import '../../../../core/platform/device_channel.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/widgets/app_cached_image.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../../catalog/application/catalog_providers.dart';
import '../../../catalog/domain/catalog_models.dart';
import '../../../reader/book_reader_screen.dart';
import '../../../telegram/telegram_delivery.dart';
import '../../../telegram/telegram_files.dart';
import 'media_player_screen.dart';
import 'report_content_dialog.dart';

/// Modal interactivo de detalle y descarga de contenido (película o serie/anime/novela)
/// diseñado idéntico a las pantallas de referencia de QvaTube.
void showContentDetailSheet(BuildContext context, CatalogItem item) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF0D0E11),
    barrierColor: AppColors.modalBackdrop,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
    ),
    builder: (context) => _ContentDetailSheet(item: item),
  );
}

class _ContentDetailSheet extends ConsumerStatefulWidget {
  const _ContentDetailSheet({required this.item});

  final CatalogItem item;

  @override
  ConsumerState<_ContentDetailSheet> createState() =>
      _ContentDetailSheetState();
}

class _ContentDetailSheetState extends ConsumerState<_ContentDetailSheet> {
  bool _loadingAction = false;
  bool _loadingEpisodes = false;
  bool _loadingInfo = false;
  bool _isUnlimitedPlan = false;
  ContentInfo? _info;
  List<Map<String, dynamic>> _episodes = [];
  String? _episodesError;
  int _selectedSeason = 1;
  late bool _favorited = widget.item.favorited;
  bool _togglingFavorite = false;

  // "Ver más archivos con el mismo nombre" (películas/libros con dup_count).
  bool _sameNameOpen = false;
  bool _sameNameLoading = false;
  String? _sameNameError;
  List<SameNameFile>? _sameNameFiles;

  // Descarga en lote de pistas (álbum, solo Ultra): modo selección y claves
  // `chat_id:msg_id` marcadas.
  bool _selectingTracks = false;
  final Set<String> _selectedTrackKeys = <String>{};
  bool _batchLoading = false;

  bool _sharing = false;

  bool get _isSeries =>
      widget.item.isSeries ||
      widget.item.categoryKey == 'series' ||
      widget.item.categoryKey == 'anime' ||
      widget.item.categoryKey == 'novela';

  bool get _isAlbum =>
      widget.item.isAlbum ||
      (widget.item.categoryKey == 'music' && widget.item.episodeCount > 1);

  bool get _isAudio =>
      widget.item.categoryKey == 'music' || widget.item.kind == 'audio';

  bool get _isBook =>
      widget.item.categoryKey == 'book' || widget.item.kind == 'book';

  String? get _title {
    final title = widget.item.title;
    return title == null || title.isEmpty ? null : title;
  }

  @override
  void initState() {
    super.initState();
    _fetchInfo();
    if (_isSeries) {
      _fetchEpisodes();
      _fetchPlan();
    } else if (_isAlbum) {
      _fetchAlbumTracks();
      _fetchPlan();
    }
  }

  Future<void> _toggleFavorite() async {
    if (_togglingFavorite) return;
    final next = !_favorited;
    setState(() {
      _togglingFavorite = true;
      _favorited = next;
    });
    try {
      final result = await ref
          .read(catalogApiProvider)
          .setFavorite(widget.item, favorite: next);
      if (!mounted) return;
      setState(() => _favorited = result);
      ref.invalidate(favoritesProvider);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _favorited = !next);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.statusCode == 401
                ? 'Inicia sesión para guardar favoritos.'
                : 'No se pudo actualizar. Intenta de nuevo.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _favorited = !next);
    } finally {
      if (mounted) setState(() => _togglingFavorite = false);
    }
  }

  /// Check de "visto" de un episodio (`POST /api/watched`). Se marca al
  /// instante y se revierte si el servidor falla.
  Future<void> _toggleEpisodeWatched(Map<String, dynamic> ep) async {
    final chatId = (ep['chat_id'] as num?)?.toInt();
    final msgId = (ep['msg_id'] as num?)?.toInt();
    if (chatId == null || msgId == null) return;
    final next = ep['watched'] != true;
    setState(() => ep['watched'] = next);
    try {
      await ref
          .read(catalogApiProvider)
          .setWatched(chatId: chatId, msgId: msgId, watched: next);
    } catch (error) {
      if (!mounted) return;
      setState(() => ep['watched'] = !next);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException && error.statusCode == 401
                ? 'Inicia sesión para marcar episodios como vistos.'
                : 'No se pudo actualizar. Intenta de nuevo.',
          ),
        ),
      );
    }
  }

  Future<void> _fetchInfo() async {
    final title = _title;
    final type = widget.item.tmdbType;
    if (title == null || type == null || type.isEmpty) return;

    setState(() => _loadingInfo = true);
    try {
      final info = await ref.read(catalogApiProvider).info(title, type: type);
      if (!mounted) return;
      setState(() {
        _info = info;
        _loadingInfo = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingInfo = false);
    }
  }

  Future<void> _fetchPlan() async {
    try {
      final result = await ref.read(planUsageProvider.future);
      if (!mounted) return;
      setState(() => _isUnlimitedPlan = result.usage?.unlimited ?? false);
    } catch (_) {
      // Sin sesión o sin red: se mantiene oculto el botón de temporada.
    }
  }

  Future<void> _fetchEpisodes() async {
    setState(() {
      _loadingEpisodes = true;
      _episodesError = null;
    });

    try {
      final list = await ref
          .read(catalogApiProvider)
          .episodes(categoryKey: widget.item.categoryKey, title: _title);
      if (!mounted) return;
      setState(() {
        _episodes = list;
        _loadingEpisodes = false;
        _selectedSeason = _defaultSeason(list);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingEpisodes = false;
        _episodes = const [];
        _episodesError = 'No se pudieron cargar los episodios.';
      });
    }
  }

  Future<void> _fetchAlbumTracks() async {
    setState(() {
      _loadingEpisodes = true;
      _episodesError = null;
    });

    try {
      final list = await ref
          .read(catalogApiProvider)
          .albumTracks(
            categoryKey: widget.item.categoryKey ?? 'music',
            artist: widget.item.artist ?? '',
            album: widget.item.album ?? '',
          );
      if (!mounted) return;
      setState(() {
        _episodes = list;
        _loadingEpisodes = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingEpisodes = false;
        _episodes = const [];
      });
    }
  }

  int _defaultSeason(List<Map<String, dynamic>> episodes) {
    final seasons = <int>{
      for (final ep in episodes) (ep['season'] as num?)?.toInt() ?? 0,
    };
    if (seasons.isEmpty) return 1;
    final numbered = seasons.where((s) => s > 0).toList()..sort();
    if (numbered.isNotEmpty) return numbered.first;
    final all = seasons.toList()..sort();
    return all.first;
  }

  List<int> get _seasons {
    final seasons = <int>{
      for (final ep in _episodes) (ep['season'] as num?)?.toInt() ?? 0,
    };
    return seasons.toList()..sort();
  }

  List<Map<String, dynamic>> get _seasonEpisodes => _episodes
      .where((ep) => ((ep['season'] as num?)?.toInt() ?? 0) == _selectedSeason)
      .toList();

  String _seasonLabel(int season) {
    if (season > 0) return 'Temporada $season';
    if (season == -1) return 'OVA';
    if (season == -2) return 'Especiales';
    if (season == -3) return 'ONA';
    if (season < -3) return 'Especial T${season + 1000}';
    return 'Otros';
  }

  String _episodeLabel(Map<String, dynamic> ep, int index) {
    final season = (ep['season'] as num?)?.toInt() ?? 0;
    final number = (ep['episode'] as num?)?.toInt();
    final padded = number != null
        ? number.toString().padLeft(2, '0')
        : (index + 1).toString().padLeft(2, '0');
    if (season > 0) return 'T$season · E$padded';
    if (season == -1) return 'OVA $padded';
    if (season == -2) return 'Especial $padded';
    if (season == -3) return 'ONA $padded';
    return 'E$padded';
  }

  String? _downloadLink(Map<String, dynamic> response) {
    final url =
        response['url']?.toString() ??
        response['deep_link']?.toString() ??
        response['telegram_url']?.toString();
    return url == null || url.isEmpty ? null : url;
  }

  Future<void> _openTelegram(String fallbackPayload) async {
    final botConfig = await ref
        .read(siteConfigProvider.future)
        .catchError((_) => const SiteConfig());
    final bot = botConfig.botUsername ?? 'qvatube_bot';
    await _openLink('https://t.me/$bot?start=$fallbackPayload');
  }

  /// Abre el enlace (Telegram primero, sin depender del navegador) y avisa si
  /// ninguna app del teléfono pudo abrirlo.
  Future<void> _openLink(String url) async {
    final opened = await DeviceChannel.openUrl(url);
    if (opened || !mounted) return;
    final telegram = url.contains('t.me/') || url.startsWith('tg:');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          telegram
              ? 'No se pudo abrir Telegram. Instálalo o actualízalo para '
                    'recibir el archivo.'
              : 'No hay ninguna app para abrir este enlace.',
        ),
      ),
    );
  }

  /// Reproduce/lee la película o libro de la tarjeta, o [file] si se eligió
  /// otro de la lista de archivos con el mismo nombre.
  Future<void> _handlePlayMovie({SameNameFile? file}) async {
    if (file == null && _isAlbum && _episodes.isNotEmpty) {
      await _handlePlayAlbumTrack(0);
      return;
    }

    final chatId = file?.chatId ?? widget.item.chatId;
    final msgId = file?.msgId ?? widget.item.msgId;
    final isFront = chatId == widget.item.chatId && msgId == widget.item.msgId;

    if (chatId == null || msgId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este contenido no tiene identificador de reproducción asignado.',
          ),
        ),
      );
      return;
    }

    if (_isBook) {
      await openBookReader(
        context,
        chatId: chatId,
        msgId: msgId,
        title: widget.item.title ?? _info?.title ?? 'Libro',
        initialPositionSeconds: isFront ? widget.item.positionSeconds : null,
      );
      if (mounted) ref.invalidate(continueWatchingProvider);
      return;
    }

    final title = _info?.title ?? widget.item.title ?? 'Reproduciendo';
    final subtitle = widget.item.artist ?? _info?.year;
    final tg = TelegramFiles.instance.fileFor(chatId, msgId);
    final playable = PlayableMediaItem(
      chatId: chatId,
      msgId: msgId,
      title: title,
      subtitle: subtitle,
      posterUrl: _isAudio
          ? absoluteMediaUrl(MediaEndpoints.cover(chatId, msgId))
          : widget.item.posterUrl,
      fallbackPosterUrl: widget.item.posterUrl,
      thumbnail: tg?.thumbnail,
      isAudio: _isAudio,
      isBook: _isBook,
      initialPositionSeconds: isFront ? widget.item.positionSeconds : null,
      localPath: (tg != null && tg.completed && tg.localPath.isNotEmpty)
          ? tg.localPath
          : null,
    );

    await openMediaPlayer(context, playlist: [playable]);
    if (mounted) {
      ref.invalidate(continueWatchingProvider);
    }
  }

  Future<void> _handlePlayEpisode(int index) async {
    final eps = _seasonEpisodes;
    if (eps.isEmpty || index < 0 || index >= eps.length) return;

    final seriesTitle = _info?.title ?? widget.item.title ?? 'Serie';
    final playlist = <PlayableMediaItem>[];
    var targetIndex = 0;

    for (var i = 0; i < eps.length; i++) {
      final ep = eps[i];
      final chatId = (ep['chat_id'] as num?)?.toInt() ?? widget.item.chatId;
      final msgId = (ep['msg_id'] as num?)?.toInt() ?? widget.item.msgId;
      if (chatId == null || msgId == null) continue;

      if (i == index) {
        targetIndex = playlist.length;
      }

      final epTitle = ep['title']?.toString();
      final label = _episodeLabel(ep, i);
      playlist.add(
        PlayableMediaItem(
          chatId: chatId,
          msgId: msgId,
          title: seriesTitle,
          subtitle: epTitle != null && epTitle.isNotEmpty
              ? '$label · $epTitle'
              : label,
          posterUrl: widget.item.posterUrl,
        ),
      );
    }

    if (playlist.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo iniciar la reproducción del episodio.'),
        ),
      );
      return;
    }

    await openMediaPlayer(
      context,
      playlist: playlist,
      initialIndex: targetIndex,
    );
    if (mounted) {
      ref.invalidate(continueWatchingProvider);
    }
  }

  Future<void> _handlePlayAlbumTrack(int index) async {
    if (_episodes.isEmpty || index < 0 || index >= _episodes.length) return;

    final albumTitle = _info?.title ?? widget.item.title ?? 'Álbum';
    final playlist = <PlayableMediaItem>[];
    var targetIndex = 0;

    for (var i = 0; i < _episodes.length; i++) {
      final track = _episodes[i];
      final chatId = (track['chat_id'] as num?)?.toInt() ?? widget.item.chatId;
      final msgId = (track['msg_id'] as num?)?.toInt() ?? widget.item.msgId;
      if (chatId == null || msgId == null) continue;

      if (i == index) {
        targetIndex = playlist.length;
      }

      final trackTitle =
          track['title']?.toString() ??
          'Pista ${(i + 1).toString().padLeft(2, '0')}';
      final artist =
          track['artist']?.toString() ?? widget.item.artist ?? albumTitle;
      final tg = TelegramFiles.instance.fileFor(chatId, msgId);
      playlist.add(
        PlayableMediaItem(
          chatId: chatId,
          msgId: msgId,
          title: trackTitle,
          subtitle: artist,
          posterUrl: absoluteMediaUrl(MediaEndpoints.cover(chatId, msgId)),
          fallbackPosterUrl: widget.item.posterUrl,
          thumbnail: tg?.thumbnail,
          isAudio: true,
          localPath: (tg != null && tg.completed && tg.localPath.isNotEmpty)
              ? tg.localPath
              : null,
        ),
      );
    }

    if (playlist.isEmpty) return;

    await openMediaPlayer(
      context,
      playlist: playlist,
      initialIndex: targetIndex,
    );
    if (mounted) {
      ref.invalidate(continueWatchingProvider);
    }
  }

  /// Gestor de descargas: si Telegram está conectado en la app con la misma
  /// cuenta verificada, pide `delivery: "app"` y el bot envía el archivo al
  /// chat sin abrir Telegram; aparece en Cuenta → Telegram.
  ///
  /// Devuelve `false` si no aplica (o el servidor no tiene el modo app
  /// activo) para que el botón siga con el deep link de siempre.
  /// Archivos (chat_id/msg_id) de una lista de pistas o episodios.
  static List<({int chatId, int msgId})> _sources(
    Iterable<Map<String, dynamic>> rows,
  ) => [
    for (final r in rows)
      if (r['chat_id'] is num && r['msg_id'] is num)
        (
          chatId: (r['chat_id'] as num).toInt(),
          msgId: (r['msg_id'] as num).toInt(),
        ),
  ];

  /// Si todos [items] ya se enviaron al gestor, avisa y devuelve `true`
  /// (no se vuelven a mandar al chat).
  bool _alreadyDelivered(List<({int chatId, int msgId})> items, String what) {
    if (items.isEmpty) return false;
    if (!canDeliverToApp(ref.read(authControllerProvider).user)) return false;
    final files = TelegramFiles.instance;
    if (!items.every((i) => files.wasDelivered(i.chatId, i.msgId))) {
      return false;
    }
    final router = GoRouter.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Ya pediste estos $what: están en tu gestor de '
            'descargas.',
          ),
          persist: false,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Ver',
            onPressed: () => router.push('/cuenta/telegram'),
          ),
        ),
      );
    return true;
  }

  /// Pedidos al gestor en curso (estático: sobrevive a cerrar y abrir la
  /// ficha). Evita que dos toques seguidos en "Descargar" manden el mismo
  /// archivo dos veces al chat.
  static final Set<String> _appInFlight = {};

  Future<bool> _tryAppDelivery(
    Future<Map<String, dynamic>> Function() request, {
    bool showLoading = true,
    String unit = 'episodio',
    ({int chatId, int msgId})? source,
    String? batchKey,
  }) async {
    if (!canDeliverToApp(ref.read(authControllerProvider).user)) return false;
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    void notice(String text) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(text),
            persist: false,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Ver',
              onPressed: () => router.push('/cuenta/telegram'),
            ),
          ),
        );
    }

    final key = source != null ? '${source.chatId}:${source.msgId}' : batchKey;
    if (key != null && _appInFlight.contains(key)) {
      notice('Ya lo estás pidiendo: espera un momento.');
      return true;
    }
    // Ya se pidió antes: no se vuelve a mandar al chat, se descarga lo que
    // ya llegó.
    if (source != null) {
      final files = TelegramFiles.instance;
      if (files.wasDelivered(source.chatId, source.msgId)) {
        final file = files.fileFor(source.chatId, source.msgId);
        if (file == null) {
          notice('Ya lo pediste: está llegando a tu gestor de descargas.');
        } else if (file.completed) {
          notice('Ya está descargado en tu teléfono.');
        } else if (file.downloading) {
          notice('Ya se está descargando en tu gestor de descargas.');
        } else {
          unawaited(files.download(file));
          notice('Empezó a descargarse en tu gestor de descargas.');
        }
        return true;
      }
    }

    void done() {
      if (key != null) _appInFlight.remove(key);
      if (showLoading && mounted) setState(() => _loadingAction = false);
    }

    if (key != null) _appInFlight.add(key);
    if (showLoading) setState(() => _loadingAction = true);
    try {
      final response = await request();
      done();
      if (response['delivery'] != 'app') {
        // Servidor sin el modo app: devolvió el deep link normal.
        final url = _downloadLink(response);
        if (url == null) return false;
        await _openLink(url);
        return true;
      }
      final queued = (response['queued'] as num?)?.toInt();
      final title = response['title']?.toString();
      if (queued == null) TelegramFiles.instance.addCatalogRow(response);
      final String text;
      if (queued == null) {
        text =
            '${title == null || title.isEmpty ? 'El archivo' : title} ya está '
            'en tu gestor de descargas.';
      } else if (queued == 0) {
        text = 'No hay nada para enviar.';
      } else {
        text =
            'El bot te enviará $queued '
            '${queued == 1 ? unit : '${unit}s'}. Irán apareciendo en '
            'tu gestor de descargas.';
      }
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(text),
          // Con botón de acción Flutter lo deja fijo; aquí tapaba la barra
          // de "Seleccionar" pistas.
          persist: false,
          duration: const Duration(seconds: 5),
          action: queued == 0
              ? null
              : SnackBarAction(
                  label: 'Ver',
                  onPressed: () => router.push('/cuenta/telegram'),
                ),
        ),
      );
      return true;
    } on ApiException catch (e) {
      done();
      switch (e.statusCode) {
        case 409:
          // El usuario bloqueó el bot: se abre como siempre (el token sigue
          // sin usar, no se pierde cupo).
          final link = e.details?['deep_link']?.toString();
          if (link == null || link.isEmpty) return false;
          messenger.showSnackBar(SnackBar(content: Text(e.message)));
          await _openLink(link);
          return true;
        case 503:
          return false;
        default:
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                e.network ? 'Sin conexión. Intenta de nuevo.' : e.message,
              ),
            ),
          );
          return true;
      }
    } catch (_) {
      done();
      return false;
    }
  }

  Future<void> _handleDownloadMovie({SameNameFile? file}) async {
    final chatId = file?.chatId ?? widget.item.chatId;
    final msgId = file?.msgId ?? widget.item.msgId;

    if (chatId == null || msgId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este contenido no tiene identificador de descarga asignado.',
          ),
        ),
      );
      return;
    }

    if (await _tryAppDelivery(
      () => ref
          .read(catalogApiProvider)
          .authorizeDownload(chatId: chatId, msgId: msgId, toApp: true),
      source: (chatId: chatId, msgId: msgId),
    )) {
      return;
    }
    if (!mounted) return;

    setState(() => _loadingAction = true);
    try {
      final response = await ref
          .read(catalogApiProvider)
          .authorizeDownload(chatId: chatId, msgId: msgId);
      if (!mounted) return;
      setState(() => _loadingAction = false);

      final url = _downloadLink(response);
      if (url != null) {
        await _openLink(url);
      } else {
        await _openTelegram('dl_${chatId}_$msgId');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadingAction = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingAction = false);
      await _openTelegram('dl_${chatId}_$msgId');
    }
  }

  Future<void> _handleDownloadSeason() async {
    final categoryKey = widget.item.categoryKey;
    final title = _title;
    if (categoryKey == null || categoryKey.isEmpty || title == null) return;
    if (_loadingAction) return;
    if (_alreadyDelivered(_sources(_seasonEpisodes), 'episodios')) return;

    if (await _tryAppDelivery(
      batchKey: 'season:$categoryKey:$title:$_selectedSeason',
      () => ref
          .read(catalogApiProvider)
          .authorizeSeasonDownload(
            categoryKey: categoryKey,
            title: title,
            season: _selectedSeason,
            toApp: true,
          ),
    )) {
      return;
    }
    if (!mounted) return;

    setState(() => _loadingAction = true);
    try {
      final response = await ref
          .read(catalogApiProvider)
          .authorizeSeasonDownload(
            categoryKey: categoryKey,
            title: title,
            season: _selectedSeason,
          );
      if (!mounted) return;
      setState(() => _loadingAction = false);

      final url = _downloadLink(response);
      if (url != null) {
        await _openLink(url);
      } else {
        await _openTelegram('season_${categoryKey}_$_selectedSeason');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadingAction = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingAction = false);
      await _openTelegram('season_${categoryKey}_$_selectedSeason');
    }
  }

  static String? _trackKey(Map<String, dynamic> track) {
    final chatId = (track['chat_id'] as num?)?.toInt();
    final msgId = (track['msg_id'] as num?)?.toInt();
    if (chatId == null || msgId == null) return null;
    return '$chatId:$msgId';
  }

  List<Map<String, dynamic>> get _selectableTracks =>
      _episodes.where((t) => _trackKey(t) != null).toList();

  void _toggleTrackSelectionMode() {
    setState(() {
      _selectingTracks = !_selectingTracks;
      _selectedTrackKeys.clear();
    });
  }

  void _toggleTrackSelected(Map<String, dynamic> track) {
    final key = _trackKey(track);
    if (key == null) return;
    setState(() {
      if (!_selectedTrackKeys.remove(key)) _selectedTrackKeys.add(key);
    });
  }

  void _toggleSelectAllTracks() {
    final rows = _selectableTracks;
    final allOn = rows.isNotEmpty && _selectedTrackKeys.length == rows.length;
    setState(() {
      _selectedTrackKeys.clear();
      if (!allOn) _selectedTrackKeys.addAll(rows.map((t) => _trackKey(t)!));
    });
  }

  /// Pide el deep link de un lote y lo abre en Telegram (el bot entrega los
  /// archivos uno por uno). Devuelve `true` si se abrió.
  Future<bool> _runBatchRequest(
    Future<Map<String, dynamic>> Function() request,
  ) async {
    if (_batchLoading) return false;
    setState(() => _batchLoading = true);
    try {
      final response = await request();
      final url = _downloadLink(response);
      if (url == null) {
        throw const ApiException('El servidor no devolvió el enlace.');
      }
      await _openLink(url);
      return true;
    } on ApiException catch (e) {
      if (!mounted) return false;
      final message = switch (e.statusCode) {
        401 => 'Inicia sesión para descargar en lote.',
        null => 'Sin conexión. Intenta de nuevo.',
        _ => e.message,
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      return false;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo preparar la descarga.')),
      );
      return false;
    } finally {
      if (mounted) setState(() => _batchLoading = false);
    }
  }

  /// Lote con el gestor de descargas: el bot los envía al chat sin abrir
  /// Telegram. `true` si se resolvió así (si no, se sigue con el bot).
  Future<bool> _tryAppBatch(
    Future<Map<String, dynamic>> Function() request, {
    required String unit,
    required List<({int chatId, int msgId})> items,
    required String batchKey,
  }) async {
    if (_batchLoading) return false;
    if (_alreadyDelivered(items, '${unit}s')) return true;
    setState(() => _batchLoading = true);
    try {
      return await _tryAppDelivery(
        request,
        showLoading: false,
        unit: unit,
        batchKey: batchKey,
      );
    } finally {
      if (mounted) setState(() => _batchLoading = false);
    }
  }

  Future<void> _handleDownloadAlbum() async {
    final item = widget.item;
    Future<Map<String, dynamic>> request({bool toApp = false}) => ref
        .read(catalogApiProvider)
        .authorizeAlbumDownload(
          categoryKey: item.categoryKey ?? 'music',
          artist: item.artist ?? '',
          album: item.album ?? '',
          toApp: toApp,
        );
    if (await _tryAppBatch(
      () => request(toApp: true),
      unit: 'pista',
      items: _sources(_episodes),
      batchKey: 'album:${item.categoryKey}:${item.artist}:${item.album}',
    )) {
      return;
    }
    await _runBatchRequest(request);
  }

  Future<void> _handleDownloadSelectedTracks() async {
    // En el orden en que se ven, no en el que se tocaron.
    final items = <({int chatId, int msgId})>[
      for (final t in _selectableTracks)
        if (_selectedTrackKeys.contains(_trackKey(t)))
          (
            chatId: (t['chat_id'] as num).toInt(),
            msgId: (t['msg_id'] as num).toInt(),
          ),
    ];
    if (items.isEmpty) return;
    final api = ref.read(catalogApiProvider);
    final ok =
        await _tryAppBatch(
          () => api.authorizeBatchDownload(items, toApp: true),
          unit: 'archivo',
          items: items,
          batchKey:
              'batch:${items.map((i) => '${i.chatId}:${i.msgId}').join(',')}',
        ) ||
        await _runBatchRequest(() => api.authorizeBatchDownload(items));
    if (ok && mounted) {
      setState(() {
        _selectingTracks = false;
        _selectedTrackKeys.clear();
      });
    }
  }

  Future<void> _handleDownloadEpisode(Map<String, dynamic> episode) async {
    final chatId = (episode['chat_id'] as num?)?.toInt() ?? widget.item.chatId;
    final msgId = (episode['msg_id'] as num?)?.toInt() ?? widget.item.msgId;

    if (chatId == null || msgId == null) return;

    if (await _tryAppDelivery(
      () => ref
          .read(catalogApiProvider)
          .authorizeDownload(chatId: chatId, msgId: msgId, toApp: true),
      showLoading: false,
      source: (chatId: chatId, msgId: msgId),
    )) {
      return;
    }

    try {
      final response = await ref
          .read(catalogApiProvider)
          .authorizeDownload(chatId: chatId, msgId: msgId);
      final url = _downloadLink(response);

      if (url != null) {
        await _openLink(url);
      } else {
        await _openTelegram('dl_${chatId}_$msgId');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      await _openTelegram('dl_${chatId}_$msgId');
    }
  }

  /// Comparte el enlace público del título con el menú "Compartir" de
  /// Android (WhatsApp, Telegram...). Si no se puede abrir, lo copia.
  Future<void> _shareItem() async {
    setState(() => _sharing = true);
    final url = await ref.read(catalogApiProvider).shareUrl(widget.item);
    if (!mounted) return;
    setState(() => _sharing = false);
    if (await DeviceChannel.shareText(url)) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Enlace copiado al portapapeles.')),
    );
  }

  void _openTrailer() {
    final key = _info?.trailerKey;
    if (key == null || key.isEmpty) return;
    DeviceChannel.openUrl('https://www.youtube.com/watch?v=$key');
  }

  String _trackDuration(Map<String, dynamic> track) {
    final raw =
        track['duration'] ?? track['duration_s'] ?? track['duration_seconds'];
    final seconds = raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString() ?? '');
    if (seconds == null || seconds <= 0) return '';
    final total = seconds.round();
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final rest = total % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:'
          '${rest.toString().padLeft(2, '0')}';
    }
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  String _trackSubtitle(Map<String, dynamic> track) {
    final duration = _trackDuration(track);
    final size = formatFileSize((track['size'] as num?)?.toInt());
    return [duration, size].where((value) => value.isNotEmpty).join(' · ');
  }

  int _trackNumber(Map<String, dynamic> track, int index) {
    final number = (track['track_number'] as num?)?.toInt();
    return number == null || number <= 0 ? index + 1 : number;
  }

  Future<void> _toggleSameName() async {
    setState(() => _sameNameOpen = !_sameNameOpen);
    if (_sameNameOpen && _sameNameFiles == null && !_sameNameLoading) {
      await _fetchSameName();
    }
  }

  /// Se pide al abrir la sección por primera vez (como la web): el número del
  /// botón sale de `dup_count` sin llamar al servidor.
  Future<void> _fetchSameName() async {
    final categoryKey = widget.item.categoryKey;
    final title = widget.item.title;
    if (categoryKey == null || title == null) return;
    setState(() {
      _sameNameLoading = true;
      _sameNameError = null;
    });
    try {
      final files = await ref
          .read(catalogApiProvider)
          .sameNameFiles(categoryKey: categoryKey, title: title);
      if (!mounted) return;
      setState(() {
        _sameNameFiles = files;
        _sameNameLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sameNameLoading = false;
        _sameNameError = e.statusCode == null
            ? 'Sin conexión. Conéctate para ver los demás archivos.'
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sameNameLoading = false;
        _sameNameError = 'No se pudieron cargar los archivos.';
      });
    }
  }

  static String _formatFileDate(DateTime? date) {
    if (date == null) return '';
    const months = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Widget _buildSameNameSection() {
    final files = _sameNameFiles;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16181D),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: _toggleSameName,
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.files,
                    size: 16,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Ver más archivos con el mismo nombre',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${widget.item.dupCount}',
                      style: AppTextStyles.mono(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accentInk,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _sameNameOpen
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.white54,
                  ),
                ],
              ),
            ),
          ),
          if (_sameNameOpen) ...[
            const Divider(color: Colors.white10, height: 1),
            if (_sameNameLoading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_sameNameError != null)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Text(
                      _sameNameError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white60,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _fetchSameName,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              )
            else if (files != null && files.isEmpty)
              const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'No se encontraron otros archivos.',
                  style: TextStyle(fontSize: 12, color: Colors.white60),
                ),
              )
            else if (files != null)
              for (var i = 0; i < files.length; i++) ...[
                if (i > 0) const Divider(color: Colors.white10, height: 1),
                _buildSameNameRow(i, files[i]),
              ],
          ],
        ],
      ),
    );
  }

  Widget _buildSameNameRow(int index, SameNameFile file) {
    final isFront =
        file.chatId == widget.item.chatId && file.msgId == widget.item.msgId;
    final meta = [
      formatFileSize(file.size),
      _formatFileDate(file.date),
    ].where((v) => v.isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Archivo ${index + 1}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    if (isFront) ...[
                      const SizedBox(width: 6),
                      const Text(
                        '(el de arriba)',
                        style: TextStyle(fontSize: 11, color: Colors.white38),
                      ),
                    ],
                    if (file.watched) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.check_circle,
                        size: 14,
                        color: AppColors.success,
                      ),
                    ],
                  ],
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    style: AppTextStyles.mono(
                      fontSize: 11,
                      color: Colors.white54,
                    ),
                  ),
              ],
            ),
          ),
          _TrackActionButton(
            icon: _isBook ? LucideIcons.bookOpen : LucideIcons.play,
            onTap: () => _handlePlayMovie(file: file),
          ),
          const SizedBox(width: 8),
          _TrackActionButton(
            icon: LucideIcons.download,
            onTap: _loadingAction
                ? null
                : () => _handleDownloadMovie(file: file),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumSheet() {
    final item = widget.item;
    final title = (_info?.title ?? item.title ?? 'Álbum')
        .toString()
        .toUpperCase();
    final artist = item.artist ?? '';
    final showBatch =
        _isUnlimitedPlan && !_loadingEpisodes && _episodes.length > 1;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        final list = ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _AlbumCover(posterUrl: item.posterUrl),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.display(
                          fontSize: 22,
                          letterSpacing: 0.4,
                        ),
                      ),
                      if (artist.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _HeaderActionChip(
                  icon: Icons.flag_outlined,
                  tooltip: 'Reportar',
                  onTap: () => showReportContentDialog(context, item),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _loadingEpisodes || _episodes.isEmpty
                    ? null
                    : () => _handlePlayAlbumTrack(0),
                icon: const Icon(Icons.play_arrow_rounded, size: 22),
                label: const Text('Reproducir álbum'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.accent.withValues(
                    alpha: 0.4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  textStyle: AppTextStyles.body(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (showBatch) ...[
              const SizedBox(height: 10),
              _buildAlbumBatchActions(),
            ],
            const SizedBox(height: 16),
            if (_loadingEpisodes)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_episodes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'Sin pistas.',
                    style: TextStyle(color: Colors.white54, fontSize: 12.5),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: _episodes.length,
                itemBuilder: (context, index) {
                  final track = _episodes[index];
                  final trackTitle =
                      track['title']?.toString() ??
                      'Pista ${(index + 1).toString().padLeft(2, '0')}';
                  final subtitle = _trackSubtitle(track);
                  final selecting = _selectingTracks && showBatch;
                  final key = _trackKey(track);
                  final selected =
                      key != null && _selectedTrackKeys.contains(key);
                  return InkWell(
                    onTap: selecting
                        ? (key == null
                              ? null
                              : () => _toggleTrackSelected(track))
                        : () => _handlePlayAlbumTrack(index),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 9,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            child: selecting
                                ? Icon(
                                    selected
                                        ? Icons.check_box_rounded
                                        : Icons.check_box_outline_blank_rounded,
                                    size: 20,
                                    color: selected
                                        ? AppColors.accent
                                        : (key == null
                                              ? Colors.white12
                                              : Colors.white38),
                                  )
                                : Text(
                                    '${_trackNumber(track, index)}',
                                    textAlign: TextAlign.center,
                                    style: AppTextStyles.mono(
                                      fontSize: 11,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  trackTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.body(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    height: 1.2,
                                  ),
                                ),
                                if (subtitle.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.body(
                                      fontSize: 10.5,
                                      color: AppColors.textMuted,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (!selecting) ...[
                            const SizedBox(width: 8),
                            _TrackActionButton(
                              icon: Icons.play_arrow_rounded,
                              filled: true,
                              onTap: () => _handlePlayAlbumTrack(index),
                            ),
                            const SizedBox(width: 6),
                            _TrackActionButton(
                              icon: Icons.download_rounded,
                              onTap: () => _handleDownloadEpisode(track),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        );
        if (!(_selectingTracks && showBatch)) return list;
        return Column(
          children: [
            Expanded(child: list),
            _buildTrackBatchBar(),
          ],
        );
      },
    );
  }

  /// "Descargar álbum" + "Seleccionar" (solo Ultra), como en la web.
  Widget _buildAlbumBatchActions() {
    const accent = Color(0xFFFF3D1A);
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: _batchLoading ? null : _handleDownloadAlbum,
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF16181D),
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: accent),
              ),
              child: Row(
                children: [
                  if (_batchLoading && !_selectingTracks)
                    const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent,
                      ),
                    )
                  else
                    const Icon(Icons.arrow_downward, size: 15, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _batchLoading && !_selectingTracks
                          ? 'Preparando...'
                          : 'Descargar álbum',
                      style: const TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_episodes.length} pistas',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 44,
          child: OutlinedButton(
            onPressed: _batchLoading ? null : _toggleTrackSelectionMode,
            style: OutlinedButton.styleFrom(
              foregroundColor: _selectingTracks ? accent : Colors.white70,
              side: BorderSide(
                color: _selectingTracks ? accent : Colors.white24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: Text(
              _selectingTracks ? 'Cancelar' : 'Seleccionar',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  /// Barra fija al pie en modo selección: "Todo/Quitar · Descargar N · ✕".
  Widget _buildTrackBatchBar() {
    final rows = _selectableTracks;
    final n = _selectedTrackKeys.length;
    final allOn = rows.isNotEmpty && n == rows.length;
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF16181D),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: _batchLoading ? null : _toggleSelectAllTracks,
            child: Text(allOn ? 'Quitar' : 'Todo'),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: FilledButton.icon(
              onPressed: n == 0 || _batchLoading
                  ? null
                  : _handleDownloadSelectedTracks,
              icon: _batchLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_rounded, size: 16),
              label: Text(
                _batchLoading
                    ? 'Preparando...'
                    : 'Descargar $n ${n == 1 ? 'pista' : 'pistas'}',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.accent.withValues(
                  alpha: 0.4,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Cancelar selección',
            onPressed: _batchLoading ? null : _toggleTrackSelectionMode,
            icon: const Icon(Icons.close, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isAlbum) return _buildAlbumSheet();

    final item = widget.item;
    final info = _info;

    final title = info?.title ?? item.title ?? 'Sin título';
    final year = info?.hasYear == true ? info!.year : null;
    final rating = info?.hasRating == true ? info!.rating : null;
    final overview = info?.hasOverview == true
        ? info!.overview!
        : (item.genres != null && item.genres!.isNotEmpty
              ? 'Sin sinopsis disponible.'
              : 'Película y serie disponible para reproducir en streaming o '
                    'descargar directamente a tu dispositivo a través de Telegram '
                    'sin consumo extra de datos.');
    final cast = info?.cast ?? const <CastMember>[];
    final trailerKey = info?.trailerKey;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.toUpperCase(),
                        style: AppTextStyles.display(
                          fontSize: 22,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (year != null || rating != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (year != null)
                              Text(
                                year,
                                style: AppTextStyles.mono(
                                  fontSize: 12,
                                  color: const Color(0xFFFF3D1A),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            if (year != null && rating != null)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  '·',
                                  style: TextStyle(color: Colors.white38),
                                ),
                              ),
                            if (rating != null)
                              Text(
                                rating,
                                style: AppTextStyles.mono(
                                  fontSize: 12,
                                  color: const Color(0xFFFF3D1A),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (item.canFavorite) ...[
                  _HeaderActionChip(
                    icon: _favorited
                        ? LucideIcons.bookmarkCheck
                        : LucideIcons.bookmark,
                    active: _favorited,
                    tooltip: _favorited
                        ? 'Quitar de favoritos'
                        : 'Agregar a favoritos',
                    onTap: _toggleFavorite,
                  ),
                  const SizedBox(width: 8),
                ],
                _HeaderActionChip(
                  icon: Icons.share_outlined,
                  label: 'Compartir',
                  onTap: () {
                    if (!_sharing) _shareItem();
                  },
                ),
                const SizedBox(width: 8),
                _HeaderActionChip(
                  icon: Icons.flag_outlined,
                  label: 'Reportar',
                  onTap: () => showReportContentDialog(context, item),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loadingInfo && info == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else
              Text(
                overview,
                style: AppTextStyles.body(
                  fontSize: 12.5,
                  color: const Color(0xFF9CA3AF),
                  height: 1.4,
                ),
              ),
            if (cast.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'REPARTO PRINCIPAL',
                style: AppTextStyles.display(
                  fontSize: 13,
                  letterSpacing: 0.5,
                  color: const Color(0xFF9CA3AF),
                ),
              ),
              const SizedBox(height: 10),
              _CastRow(cast: cast),
            ],
            if (trailerKey != null && trailerKey.isNotEmpty) ...[
              const SizedBox(height: 16),
              InkWell(
                onTap: _openTrailer,
                borderRadius: BorderRadius.circular(AppRadii.md),
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF16181D),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Center(
                    child: Text(
                      'Ver tráiler',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (!_isSeries) ...[
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _handlePlayMovie,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3D1A),
                          borderRadius: BorderRadius.circular(AppRadii.md),
                        ),
                        child: Center(
                          child: Text(
                            _isBook ? 'Leer' : 'Reproducir',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: _loadingAction ? null : _handleDownloadMovie,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFF16181D),
                          borderRadius: BorderRadius.circular(AppRadii.md),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Center(
                          child: _loadingAction
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Descargar',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  canDeliverToApp(ref.watch(authControllerProvider).user)
                      ? 'Se descarga en tu gestor de descargas'
                      : 'La descarga necesita Telegram instalado',
                  style: const TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ),
              if (!_isAlbum && widget.item.dupCount > 1) ...[
                const SizedBox(height: 14),
                _buildSameNameSection(),
              ],
              if (_isAlbum && _episodes.isNotEmpty) ...[
                const SizedBox(height: 16),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _episodes.length,
                  separatorBuilder: (context, index) =>
                      const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (context, index) {
                    final track = _episodes[index];
                    final trackTitle =
                        track['title']?.toString() ??
                        'Pista ${(index + 1).toString().padLeft(2, '0')}';
                    final size = formatFileSize(
                      (track['size'] as num?)?.toInt(),
                    );

                    return InkWell(
                      onTap: () => _handlePlayAlbumTrack(index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.music_note_rounded,
                              size: 16,
                              color: Colors.white38,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    trackTitle,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (size.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      size,
                                      style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Container(
                              width: 32,
                              height: 32,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFFF3D1A),
                              ),
                              child: const Icon(
                                Icons.play_arrow,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
            if (_isSeries) ...[
              if (_loadingEpisodes)
                const Column(
                  children: [
                    SizedBox(height: 16),
                    CircularProgressIndicator(strokeWidth: 2),
                    SizedBox(height: 16),
                  ],
                )
              else if (_episodesError != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _episodesError!,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ),
                )
              else if (_episodes.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No hay episodios disponibles.',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                )
              else ...[
                if (_seasons.length > 1)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < _seasons.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          ChoiceChip(
                            label: Text(_seasonLabel(_seasons[i])),
                            selected: _seasons[i] == _selectedSeason,
                            onSelected: (_) =>
                                setState(() => _selectedSeason = _seasons[i]),
                            selectedColor: const Color(0xFFFF3D1A),
                            backgroundColor: const Color(0xFF16181D),
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _seasons[i] == _selectedSeason
                                  ? Colors.white
                                  : Colors.white70,
                            ),
                            side: BorderSide(
                              color: _seasons[i] == _selectedSeason
                                  ? const Color(0xFFFF3D1A)
                                  : Colors.white12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (_seasons.length > 1) const SizedBox(height: 12),
                if (_isUnlimitedPlan && _seasonEpisodes.length > 1) ...[
                  InkWell(
                    onTap: _loadingAction ? null : _handleDownloadSeason,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16181D),
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        border: Border.all(color: const Color(0xFFFF3D1A)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.arrow_downward,
                            size: 15,
                            color: Color(0xFFFF3D1A),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Descargar ${_seasonLabel(_selectedSeason)}',
                              style: const TextStyle(
                                color: Color(0xFFFF3D1A),
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF3D1A),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${_seasonEpisodes.length} EP',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _seasonEpisodes.length,
                  separatorBuilder: (context, index) =>
                      const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (context, index) {
                    final ep = _seasonEpisodes[index];
                    final size = formatFileSize((ep['size'] as num?)?.toInt());
                    final watched = ep['watched'] == true;

                    return InkWell(
                      onTap: () => _handlePlayEpisode(index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            InkResponse(
                              onTap: () => _toggleEpisodeWatched(ep),
                              radius: 18,
                              child: Tooltip(
                                message: watched
                                    ? 'Marcar como no visto'
                                    : 'Marcar como visto',
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    watched
                                        ? Icons.check_circle
                                        : Icons.check_circle_outline,
                                    size: 18,
                                    color: watched
                                        ? AppColors.success
                                        : Colors.white30,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _episodeLabel(ep, index),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (size.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      size,
                                      style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            InkWell(
                              onTap: () => _handlePlayEpisode(index),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFFFF3D1A),
                                ),
                                child: const Icon(
                                  Icons.play_arrow,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            InkWell(
                              onTap: () => _handleDownloadEpisode(ep),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                                child: const Icon(
                                  Icons.download,
                                  color: Colors.white70,
                                  size: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _AlbumCover extends StatelessWidget {
  const _AlbumCover({required this.posterUrl});

  final String posterUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: posterUrl.isEmpty
            ? const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF2A2A2E), Color(0xFF151517)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(
                  Icons.music_note_rounded,
                  color: Colors.white38,
                  size: 28,
                ),
              )
            : AppCachedImage(
                imageUrl: posterUrl,
                fit: BoxFit.cover,
                errorWidget: const ColoredBox(
                  color: Color(0xFF1C1C1F),
                  child: Icon(
                    Icons.music_note_rounded,
                    color: Colors.white38,
                    size: 28,
                  ),
                ),
              ),
      ),
    );
  }
}

class _TrackActionButton extends StatelessWidget {
  const _TrackActionButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled
              ? AppColors.accent
              : Colors.white.withValues(alpha: 0.08),
        ),
        child: Icon(
          icon,
          size: 18,
          color: filled ? Colors.white : Colors.white70,
        ),
      ),
    );
  }
}

class _HeaderActionChip extends StatelessWidget {
  const _HeaderActionChip({
    required this.icon,
    required this.onTap,
    this.label,
    this.tooltip,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;

  /// Sin etiqueta se dibuja solo el icono (con [tooltip]).
  final String? label;
  final String? tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accent : Colors.white70;
    final chip = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.accentSoft : const Color(0xFF16181D),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? AppColors.accent : Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(label!, style: TextStyle(fontSize: 11.5, color: color)),
            ],
          ],
        ),
      ),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}

class _CastRow extends StatelessWidget {
  const _CastRow({required this.cast});

  final List<CastMember> cast;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cast.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final actor = cast[index];
          return SizedBox(
            width: 58,
            child: Column(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: actor.photoUrl.isEmpty
                        ? Container(
                            color: Colors.white10,
                            child: const Icon(
                              Icons.person,
                              color: Colors.white54,
                              size: 22,
                            ),
                          )
                        : AppCachedImage(
                            imageUrl: actor.photoUrl,
                            fit: BoxFit.cover,
                            errorWidget: Container(
                              color: Colors.white10,
                              child: const Icon(
                                Icons.person,
                                color: Colors.white54,
                                size: 22,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  actor.name ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  actor.character ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9, color: Colors.white38),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
