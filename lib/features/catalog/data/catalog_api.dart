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
    String? genre,
    String sort = 'recent',
    String? search,
  }) async {
    final query = <String, dynamic>{'page': page, 'sort': sort};
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
              .map((e) => NotificationItem.fromJson(Map<String, dynamic>.from(e)))
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
    return _list(response.data)
        .map(PlanInfo.fromJson)
        .toList();
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

  /// POST /api/suggest-content
  /// body: { category_key, title, note, search_query }
  Future<void> suggestContent({
    required String categoryKey,
    required String title,
    String note = '',
    String searchQuery = '',
  }) async {
    await _client.post(
      Endpoints.reportsSuggestions.suggestContent,
      body: <String, dynamic>{
        'category_key': categoryKey,
        'title': title,
        'note': note,
        'search_query': searchQuery,
      },
      operation: 'el envío de la sugerencia',
    );
  }

  /// GET /api/reviews
  Future<({double average, int total, List<ReviewItem> reviews})> reviews() async {
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
      body: <String, dynamic>{
        'chat_id': chatId,
        'msg_id': msgId,
      },
      operation: 'la autorización de descarga',
    );
    return _map(response.data);
  }

  /// POST /api/download/authorize-season
  /// Autoriza la descarga de una temporada completa y devuelve el deep link.
  Future<Map<String, dynamic>> authorizeSeasonDownload({
    required int chatId,
    required String seasonId,
  }) async {
    final response = await _client.post(
      Endpoints.downloads.authorizeSeason,
      body: <String, dynamic>{
        'chat_id': chatId,
        'season_id': seasonId,
      },
      operation: 'la autorización de descarga de temporada',
    );
    return _map(response.data);
  }

  /// GET /api/episodes
  /// Obtiene los episodios de una serie o temporada.
  Future<List<Map<String, dynamic>>> episodes({
    int? chatId,
    int? msgId,
    String? itemKey,
  }) async {
    final query = <String, dynamic>{};
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
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (data is Map) {
      final items = data['items'] ?? data['episodes'];
      if (items is List) {
        return items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    }
    return const [];
  }
}

