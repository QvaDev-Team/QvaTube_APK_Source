import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/endpoints/endpoints.dart';
import '../domain/catalog_models.dart';

/// Cliente del catálogo, home y datos públicos de QvaTube.
///
/// Rutas verificadas contra `doc/openapi.json` y contra las respuestas reales
/// de la API.
class CatalogApi {
  const CatalogApi(this._client);

  final ApiClient _client;

  Map<String, dynamic> _map(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _list(dynamic data) {
    if (data is List) {
      return data.whereType<Map>().map(Map<String, dynamic>.from).toList();
    }
    return <Map<String, dynamic>>[];
  }

  /// GET /api/config
  Future<SiteConfig> config() async {
    final response = await _client.get(
      Endpoints.misc.config,
      operation: 'la configuración del sitio',
    );
    return SiteConfig.fromJson(_map(response.data));
  }

  /// GET /api/stats
  Future<SiteStats> stats() async {
    final response = await _client.get(
      Endpoints.misc.stats,
      operation: 'las estadísticas del sitio',
    );
    return SiteStats.fromJson(_map(response.data));
  }

  /// GET /api/apk-info
  Future<Map<String, dynamic>> apkInfo() async {
    final response = await _client.get(
      Endpoints.misc.apkInfo,
      operation: 'la información de la APK',
    );
    return _map(response.data);
  }

  /// GET /api/categories
  Future<List<Map<String, dynamic>>> categories() async {
    final response = await _client.get(
      Endpoints.catalog.categories,
      operation: 'las categorías del catálogo',
    );
    return _list(response.data);
  }

  /// GET /api/genres con el parametro `cat`
  Future<List<String>> genres(String categoryKey) async {
    final response = await _client.get(
      Endpoints.catalog.genres,
      query: <String, dynamic>{'cat': categoryKey},
      operation: 'los géneros',
    );
    final data = _map(response.data);
    final raw = data['genres'];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return const [];
  }

  /// GET /api/movies con los parametros `cat`, `page`, `sort` y `genre`
  Future<CatalogPage> catalog({
    String? categoryKey,
    int page = 1,
    int limit = 30,
    String? genre,
    String sort = 'recent',
    String? search,
  }) async {
    final query = <String, dynamic>{'page': page, 'limit': limit, 'sort': sort};
    if (categoryKey != null && categoryKey.isNotEmpty) {
      query['cat'] = categoryKey;
    }
    if (genre != null && genre.isNotEmpty) query['genre'] = genre;
    if (search != null && search.isNotEmpty) query['q'] = search;

    final response = await _client.get(
      Endpoints.catalog.movies,
      query: query,
      operation: 'el catálogo',
    );
    return CatalogPage.fromJson(_map(response.data));
  }

  /// GET /api/home-genres
  Future<List<GenreRow>> homeGenres() async {
    final response = await _client.get(
      Endpoints.catalog.homeGenres,
      operation: 'las filas de géneros',
    );
    final data = _map(response.data);
    final rows = data['rows'];
    if (rows is List) {
      return rows
          .whereType<Map>()
          .map((e) => GenreRow.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

  /// GET /api/recommendations
  Future<({List<CatalogItem> items, String? seasonLabel, String? source})>
  recommendations() async {
    final response = await _client.get(
      Endpoints.catalog.recommendations,
      operation: 'las recomendaciones',
    );
    final data = _map(response.data);
    final rawItems = data['items'];
    return (
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map((e) => CatalogItem.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const <CatalogItem>[],
      seasonLabel: data['season_label'] as String?,
      source: data['source'] as String?,
    );
  }

  /// GET /api/continue-watching
  Future<List<CatalogItem>> continueWatching() async {
    final response = await _client.get(
      Endpoints.favoritesProgress.continueWatching,
      operation: 'la lista de "seguir donde quedaste"',
    );
    final data = _map(response.data);
    final items = data['items'];
    if (items is List) {
      return items
          .whereType<Map>()
          .map((e) => CatalogItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

  /// GET /api/new-content/counts
  Future<Map<String, int>> newContentCounts() async {
    final response = await _client.get(
      Endpoints.catalog.newContentCounts,
      operation: 'los estrenos nuevos',
    );
    final data = _map(response.data);
    final counts = data['counts'];
    if (counts is Map) {
      return counts.map(
        (key, value) => MapEntry(key.toString(), (value as num?)?.toInt() ?? 0),
      );
    }
    return const {};
  }

  /// GET /api/favorites
  Future<List<CatalogItem>> favorites() async {
    final response = await _client.get(
      Endpoints.favoritesProgress.favorites,
      operation: 'los favoritos',
    );
    final data = _map(response.data);
    final items = data['items'];
    if (items is List) {
      return items
          .whereType<Map>()
          .map((e) => CatalogItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

  /// POST /api/favorites (archivo puntual) o POST /api/favorites/series
  /// (serie, anime o novela completa). Devuelve el estado final.
  Future<bool> setFavorite(CatalogItem item, {required bool favorite}) async {
    final response = item.isSeries
        ? await _client.post(
            Endpoints.favoritesProgress.seriesFavorites,
            body: <String, dynamic>{
              'cat': item.categoryKey,
              'title': item.title,
              'favorite': favorite,
            },
            operation: 'el cambio de favorito',
          )
        : await _client.post(
            Endpoints.favoritesProgress.favorites,
            body: <String, dynamic>{
              'chat_id': item.chatId,
              'msg_id': item.msgId,
              'favorite': favorite,
            },
            operation: 'el cambio de favorito',
          );
    final data = _map(response.data);
    return data['favorite'] is bool ? data['favorite'] as bool : favorite;
  }

  /// DELETE /api/progress
  /// Quita un ítem de "Seguir donde quedaste" borrando su progreso guardado.
  Future<void> removeProgress({required int chatId, required int msgId}) async {
    await _client.delete(
      Endpoints.favoritesProgress.progress,
      body: <String, dynamic>{'chat_id': chatId, 'msg_id': msgId},
      operation: 'el borrado del progreso',
    );
  }

  /// GET /api/notifications
  Future<({List<NotificationItem> items, int unread})> notifications() async {
    final response = await _client.get(
      Endpoints.notifications.notifications,
      operation: 'las notificaciones',
    );
    final data = _map(response.data);
    final rawItems = data['items'];
    return (
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (e) =>
                      NotificationItem.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const <NotificationItem>[],
      unread: (data['unread'] as num?)?.toInt() ?? 0,
    );
  }

  /// POST /api/notifications/read
  /// body: { id }
  Future<void> markNotificationRead(int id) async {
    await _client.post(
      Endpoints.notifications.read,
      body: <String, dynamic>{'id': id},
      operation: 'el marcado de la notificación',
    );
  }

  /// POST /api/notifications/read-all
  Future<void> markAllNotificationsRead() async {
    await _client.post(
      Endpoints.notifications.readAll,
      operation: 'el marcado de las notificaciones',
    );
  }

  /// POST /api/notifications/clear-all
  Future<void> clearAllNotifications() async {
    await _client.post(
      Endpoints.notifications.clearAll,
      operation: 'el borrado de las notificaciones',
    );
  }

  /// GET /api/plans
  Future<List<PlanInfo>> plans() async {
    final response = await _client.get(
      Endpoints.plans.plans,
      operation: 'el catálogo de planes',
    );
    return _list(response.data).map(PlanInfo.fromJson).toList();
  }

  /// GET /api/plans/me
  Future<({PlanUsage? usage, bool hasPendingRequest})> planUsage() async {
    final response = await _client.get(
      Endpoints.plans.me,
      operation: 'el estado de tu suscripción',
    );
    final data = _map(response.data);
    final usage = data['usage'];
    return (
      usage: usage is Map
          ? PlanUsage.fromJson(Map<String, dynamic>.from(usage))
          : null,
      hasPendingRequest: data['pending_request'] != null,
    );
  }

  /// GET /api/report-reasons
  /// Motivos de reporte definidos por el backend (`[{key, label}]`).
  Future<List<({String key, String label})>> reportReasons() async {
    final response = await _client.get(
      Endpoints.reportsSuggestions.reportReasons,
      operation: 'los motivos de reporte',
    );
    return [
      for (final e in _list(response.data))
        if (e['key'] != null)
          (key: e['key'].toString(), label: e['label']?.toString() ?? ''),
    ];
  }

  /// POST /api/report
  /// Los grupos (series, álbumes) se reportan por título, sin archivo puntual.
  Future<void> submitReport({
    required CatalogItem item,
    required String reasonKey,
    String detail = '',
  }) async {
    final isGroup = item.groupKind != null && item.groupKind!.isNotEmpty;
    await _client.post(
      Endpoints.reportsSuggestions.report,
      body: <String, dynamic>{
        'chat_id': isGroup ? null : item.chatId,
        'msg_id': isGroup ? null : item.msgId,
        'category_key': item.categoryKey,
        'title': item.title,
        'reason_key': reasonKey,
        'detail': detail,
      },
      operation: 'el envío del reporte',
    );
  }

  /// GET /api/plans/me con la solicitud de pago pendiente completa.
  /// Sin sesión (401) devuelve todo `null`.
  Future<({PlanUsage? usage, PendingPlanRequest? pending})> planStatus() async {
    try {
      final response = await _client.get(
        Endpoints.plans.me,
        operation: 'el estado de tu suscripción',
      );
      final data = _map(response.data);
      final usage = data['usage'];
      final pending = data['pending_request'];
      return (
        usage: usage is Map
            ? PlanUsage.fromJson(Map<String, dynamic>.from(usage))
            : null,
        pending: pending is Map
            ? PendingPlanRequest.fromJson(Map<String, dynamic>.from(pending))
            : null,
      );
    } on ApiException catch (error) {
      if (error.statusCode == 401) return (usage: null, pending: null);
      rethrow;
    }
  }

  /// POST /api/plans/upload-proof (multipart `photo`)
  /// Pre-sube la captura del pago y devuelve el `upload_token`.
  Future<String> uploadPlanProof(String photoPath) async {
    final response = await _client.postForm(
      Endpoints.plans.uploadProof,
      formData: FormData.fromMap(<String, dynamic>{
        'photo': await MultipartFile.fromFile(
          photoPath,
          filename: photoPath.split('/').last,
        ),
      }),
      operation: 'la subida de la captura',
    );
    final token = _map(response.data)['upload_token']?.toString();
    if (token == null || token.isEmpty) {
      throw const ApiException('No se pudo subir la captura');
    }
    return token;
  }

  /// POST /api/plans/subscribe (Transfermóvil en CUP).
  ///
  /// Con `uploadToken` confirma una captura ya subida; si la pre-subida
  /// falló, manda la foto en el mismo POST (`photoPath`), igual que la web.
  Future<void> subscribePlan({
    required String planKey,
    required int weeks,
    String? uploadToken,
    String? photoPath,
  }) async {
    if (uploadToken != null) {
      await _client.post(
        Endpoints.plans.subscribe,
        body: <String, dynamic>{
          'plan_key': planKey,
          'upload_token': uploadToken,
          'weeks': weeks,
        },
        operation: 'el envío del comprobante',
      );
      return;
    }
    if (photoPath == null) {
      throw const ApiException('Adjunta la captura del comprobante primero.');
    }
    await _client.postForm(
      Endpoints.plans.subscribe,
      formData: FormData.fromMap(<String, dynamic>{
        'plan_key': planKey,
        'weeks': '$weeks',
        'photo': await MultipartFile.fromFile(
          photoPath,
          filename: photoPath.split('/').last,
        ),
      }),
      operation: 'el envío del comprobante',
    );
  }

  /// POST /api/plans/subscribe-mobile-balance (solo plan Ultra).
  Future<void> subscribeMobileBalance({
    required String uploadToken,
    required String senderPhone,
  }) async {
    await _client.post(
      Endpoints.plans.subscribeMobileBalance,
      body: <String, dynamic>{
        'plan_key': 'ultra',
        'upload_token': uploadToken,
        'sender_phone': senderPhone,
      },
      operation: 'la solicitud de saldo móvil',
    );
  }

  /// POST /api/plans/subscribe-qvapay → URL de pago de QvaPay.
  Future<String> subscribeQvaPay(String planKey) async {
    final response = await _client.post(
      Endpoints.plans.subscribeQvapay,
      body: <String, dynamic>{'plan_key': planKey},
      operation: 'el pago con QvaPay',
    );
    final url = _map(response.data)['payment_url']?.toString();
    if (url == null || url.isEmpty) {
      throw const ApiException('No se pudo iniciar el pago con QvaPay');
    }
    return url;
  }

  /// POST /api/plans/cancel-pending
  Future<void> cancelPendingPlan() async {
    await _client.post(
      Endpoints.plans.cancelPending,
      operation: 'la cancelación de la solicitud',
    );
  }

  /// POST /api/suggest-content
  /// Soporta envío JSON o `multipart/form-data` cuando se adjunta una foto.
  Future<void> suggestContent({
    required String categoryKey,
    required String title,
    String note = '',
    String searchQuery = '',
    String? photoPath,
  }) async {
    if (photoPath != null && photoPath.isNotEmpty) {
      final fileName = photoPath.split('/').last;
      final formData = FormData.fromMap(<String, dynamic>{
        'category_key': categoryKey,
        'type': categoryKey,
        'title': title,
        'note': note,
        'details': note,
        'search_query': searchQuery,
        'photo': await MultipartFile.fromFile(photoPath, filename: fileName),
      });
      await _client.postForm(
        Endpoints.reportsSuggestions.suggestContent,
        formData: formData,
        operation: 'el envío de la sugerencia',
      );
      return;
    }

    await _client.post(
      Endpoints.reportsSuggestions.suggestContent,
      body: <String, dynamic>{
        'category_key': categoryKey,
        'type': categoryKey,
        'title': title,
        'note': note,
        'details': note,
        'search_query': searchQuery,
      },
      operation: 'el envío de la sugerencia',
    );
  }

  /// GET /api/reviews
  Future<({double average, int total, List<ReviewItem> reviews})>
  reviews() async {
    final response = await _client.get(
      Endpoints.reviews.reviews,
      operation: 'las reseñas',
    );
    final data = _map(response.data);
    final rawReviews = data['reviews'];
    return (
      average: (data['average'] as num?)?.toDouble() ?? 0,
      total: (data['total'] as num?)?.toInt() ?? 0,
      reviews: rawReviews is List
          ? rawReviews
                .whereType<Map>()
                .map((e) => ReviewItem.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const <ReviewItem>[],
    );
  }

  /// POST /api/download/authorize
  /// Autoriza la descarga de un archivo o episodio y devuelve el deep link de Telegram o URL directa.
  Future<Map<String, dynamic>> authorizeDownload({
    required int chatId,
    required int msgId,
  }) async {
    final response = await _client.post(
      Endpoints.downloads.authorize,
      body: <String, dynamic>{'chat_id': chatId, 'msg_id': msgId},
      operation: 'la autorización de descarga',
    );
    return _map(response.data);
  }

  /// POST /api/download/authorize-season
  /// Autoriza la descarga de una temporada completa y devuelve el deep link.
  Future<Map<String, dynamic>> authorizeSeasonDownload({
    required String categoryKey,
    required String title,
    required int season,
  }) async {
    final response = await _client.post(
      Endpoints.downloads.authorizeSeason,
      body: <String, dynamic>{
        'category_key': categoryKey,
        'title': title,
        'season': season,
      },
      operation: 'la autorización de descarga de temporada',
    );
    return _map(response.data);
  }

  /// POST /api/download/authorize-album
  /// Autoriza la descarga del álbum completo (solo Ultra). El servidor arma la
  /// lista de pistas a partir de `artist` + `album` (igual que
  /// `/api/album-tracks`, así que `album` se envía aunque sea `""`).
  Future<Map<String, dynamic>> authorizeAlbumDownload({
    required String categoryKey,
    required String artist,
    required String album,
  }) async {
    final response = await _client.post(
      Endpoints.downloads.authorizeAlbum,
      body: <String, dynamic>{
        'category_key': categoryKey,
        'artist': artist,
        'album': album,
      },
      operation: 'la autorización de descarga del álbum',
    );
    return _map(response.data);
  }

  /// POST /api/download/authorize-batch
  /// Autoriza una selección libre de archivos (1–200, solo Ultra), en el orden
  /// en que se ven en pantalla.
  Future<Map<String, dynamic>> authorizeBatchDownload(
    List<({int chatId, int msgId})> items,
  ) async {
    final response = await _client.post(
      Endpoints.downloads.authorizeBatch,
      body: <String, dynamic>{
        'items': [
          for (final it in items) {'chat_id': it.chatId, 'msg_id': it.msgId},
        ],
      },
      operation: 'la autorización de descarga en lote',
    );
    return _map(response.data);
  }

  /// GET /api/info
  /// Ficha TMDb del título (sinopsis, reparto, tráiler, año y nota).
  Future<ContentInfo> info(String title, {String? type}) async {
    final response = await _client.get(
      Endpoints.catalog.info,
      query: <String, dynamic>{
        'title': title,
        if (type != null && type.isNotEmpty) 'type': type,
      },
      operation: 'la ficha del contenido',
    );
    return ContentInfo.fromJson(_map(response.data));
  }

  /// GET /api/same-name
  /// Todos los archivos con el mismo nombre que la tarjeta (incluido el que
  /// muestra), del más reciente al más antiguo. Se pide solo al abrir la
  /// sección "Ver más archivos con el mismo nombre".
  Future<List<SameNameFile>> sameNameFiles({
    required String categoryKey,
    required String title,
  }) async {
    final response = await _client.get(
      Endpoints.catalog.sameName,
      query: <String, dynamic>{'cat': categoryKey, 'title': title},
      operation: 'los archivos con el mismo nombre',
    );
    final files = _map(response.data)['files'];
    if (files is! List) return const [];
    return files
        .whereType<Map>()
        .map((f) => SameNameFile.fromJson(Map<String, dynamic>.from(f)))
        .toList();
  }

  /// GET /api/episodes
  /// Obtiene los episodios de una serie o temporada.
  ///
  /// La web usa `cat` + `title`; el servidor ignora `chat_id`/`msg_id` cuando
  /// se envía el título agrupado.
  Future<List<Map<String, dynamic>>> episodes({
    String? categoryKey,
    String? title,
    int? chatId,
    int? msgId,
    String? itemKey,
  }) async {
    final query = <String, dynamic>{};
    if (categoryKey != null && categoryKey.isNotEmpty) {
      query['cat'] = categoryKey;
    }
    if (title != null && title.isNotEmpty) query['title'] = title;
    if (chatId != null) query['chat_id'] = chatId;
    if (msgId != null) query['msg_id'] = msgId;
    if (itemKey != null && itemKey.isNotEmpty) query['item_key'] = itemKey;

    final response = await _client.get(
      Endpoints.catalog.episodes,
      query: query,
      operation: 'los episodios',
    );
    final data = response.data;
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (data is Map) {
      final items = data['items'] ?? data['episodes'];
      if (items is List) {
        return items
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    return const [];
  }

  /// GET /api/search
  /// Búsqueda global en todas las categorías y canales de TV/Radio en vivo.
  Future<SearchResponse> search({
    required String query,
    int perCategory = 12,
    String? categories,
    bool includeTv = true,
  }) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      return SearchResponse(query: trimmed);
    }
    final params = <String, dynamic>{
      'q': trimmed,
      'per_category': perCategory,
      'tv': includeTv,
    };
    if (categories != null && categories.isNotEmpty) {
      params['categories'] = categories;
    }
    final response = await _client.get(
      Endpoints.catalog.search,
      query: params,
      operation: 'la búsqueda global',
    );
    return SearchResponse.fromJson(_map(response.data));
  }

  /// GET /api/tv/channels
  /// Lista los canales de televisión y emisoras de radio en vivo.
  Future<TvChannelList> tvChannels({
    String? kind,
    String? group,
    String? query,
  }) async {
    final params = <String, dynamic>{};
    if (kind != null && kind.isNotEmpty) params['kind'] = kind;
    if (group != null && group.isNotEmpty) params['group'] = group;
    if (query != null && query.trim().isNotEmpty) params['q'] = query.trim();

    final response = await _client.get(
      Endpoints.tv.channels,
      query: params.isEmpty ? null : params,
      operation: 'los canales de TV y radio',
    );
    return TvChannelList.fromJson(_map(response.data));
  }

  /// GET /api/tv/channels/{channel_id}
  Future<TvChannel> tvChannel(String channelId) async {
    final response = await _client.get(
      Endpoints.tv.channel(channelId),
      operation: 'el canal de TV',
    );
    return TvChannel.fromJson(_map(response.data));
  }

  /// GET /api/tv/viewers
  /// Devuelve los espectadores actuales por canal (`{"counts": {"cubavision": 7}}`).
  Future<Map<String, int>> tvViewers() async {
    final response = await _client.get(
      Endpoints.tv.viewers,
      operation: 'los espectadores de TV',
    );
    final data = _map(response.data);
    final counts = data['counts'];
    if (counts is Map) {
      return counts.map(
        (key, value) => MapEntry(key.toString(), (value as num?)?.toInt() ?? 0),
      );
    }
    return const {};
  }

  /// POST /api/tv/heartbeat
  Future<void> tvHeartbeat({
    required String sessionId,
    required String contentId,
  }) async {
    try {
      await _client.post(
        Endpoints.tv.heartbeat,
        body: <String, dynamic>{
          'session_id': sessionId,
          'content_id': contentId,
          'channel': contentId,
          'channel_id': contentId,
        },
        operation: 'la presencia en TV',
      );
    } catch (_) {
      // Silencioso si no hay sesión o falla el heartbeat.
    }
  }

  /// POST /api/tv/leave
  Future<void> tvLeave({required String sessionId, String? contentId}) async {
    try {
      await _client.post(
        Endpoints.tv.leave,
        body: <String, dynamic>{
          'session_id': sessionId,
          'content_id': ?contentId,
          'channel': ?contentId,
        },
        operation: 'la salida de TV',
      );
    } catch (_) {
      // Silencioso al cerrar el reproductor.
    }
  }

  /// GET /api/progress
  /// Obtiene la posición de reproducción guardada en segundos.
  Future<double> getProgress({required int chatId, required int msgId}) async {
    try {
      final response = await _client.get(
        Endpoints.favoritesProgress.progress,
        query: <String, dynamic>{'chat_id': chatId, 'msg_id': msgId},
        operation: 'el progreso de reproducción',
      );
      final data = _map(response.data);
      return (data['position_s'] as num?)?.toDouble() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// POST /api/progress
  /// Guarda la posición actual de reproducción.
  Future<void> saveProgress({
    required int chatId,
    required int msgId,
    required double positionSeconds,
    double? durationSeconds,
    String kind = 'video',
  }) async {
    try {
      await _client.post(
        Endpoints.favoritesProgress.progress,
        body: <String, dynamic>{
          'chat_id': chatId,
          'msg_id': msgId,
          'position_s': positionSeconds,
          'duration_s': ?durationSeconds,
          'kind': kind,
        },
        operation: 'el guardado del progreso',
      );
    } catch (_) {
      // Silencioso si no hay sesión o falla el guardado periódico.
    }
  }

  /// POST /api/watched
  /// Marca un archivo o episodio como visto.
  Future<void> markWatched({
    required int chatId,
    required int msgId,
    bool watched = true,
  }) async {
    try {
      await _client.post(
        Endpoints.favoritesProgress.watched,
        body: <String, dynamic>{
          'chat_id': chatId,
          'msg_id': msgId,
          'watched': watched,
        },
        operation: 'el marcado como visto',
      );
    } catch (_) {
      // Silencioso si falla.
    }
  }

  /// POST /api/watched — toggle manual de "visto" (a diferencia de
  /// [markWatched], propaga el error para revertir la interfaz).
  Future<void> setWatched({
    required int chatId,
    required int msgId,
    required bool watched,
  }) async {
    await _client.post(
      Endpoints.favoritesProgress.watched,
      body: <String, dynamic>{
        'chat_id': chatId,
        'msg_id': msgId,
        'watched': watched,
      },
      operation: 'el marcado como visto',
    );
  }

  /// GET /api/category-tracks
  /// Obtiene todas las pistas musicales de una categoría (todos los álbumes).
  Future<List<Map<String, dynamic>>> categoryTracks({
    String? categoryKey,
  }) async {
    final query = <String, dynamic>{};
    if (categoryKey != null && categoryKey.isNotEmpty) {
      query['cat'] = categoryKey;
    }

    final response = await _client.get(
      Endpoints.music.categoryTracks,
      query: query,
      operation: 'el catálogo completo de música',
    );
    return _tracks(response.data);
  }

  /// GET /api/album-tracks
  /// Obtiene las pistas de un álbum musical.
  ///
  /// El grupo se identifica por `artist` + `album` tal como vienen en el
  /// item del catálogo; `album` es `""` en los grupos de sencillos (su título
  /// "N sencillos" no es un álbum real), así que se envía siempre aunque
  /// esté vacío, igual que la web.
  Future<List<Map<String, dynamic>>> albumTracks({
    required String categoryKey,
    required String artist,
    required String album,
  }) async {
    final query = <String, dynamic>{
      'cat': categoryKey,
      'artist': artist,
      'album': album,
    };

    final response = await _client.get(
      Endpoints.music.albumTracks,
      query: query,
      operation: 'las pistas del álbum',
    );
    return _tracks(response.data);
  }

  List<Map<String, dynamic>> _tracks(dynamic data) {
    if (data is List) {
      return data.whereType<Map>().map(Map<String, dynamic>.from).toList();
    }
    if (data is Map) {
      final items = data['tracks'] ?? data['items'];
      if (items is List) {
        return items.whereType<Map>().map(Map<String, dynamic>.from).toList();
      }
    }
    return const [];
  }
}
