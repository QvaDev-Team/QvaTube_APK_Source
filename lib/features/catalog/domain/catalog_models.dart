import '../../../core/config/app_config.dart';

/// Convierte una ruta relativa del servidor (`/poster/x.jpg?v=2`) en URL
/// absoluta.
String absoluteMediaUrl(String? path) {
  if (path == null || path.isEmpty) return '';
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  final base = AppConfig.apiBaseUrl.endsWith('/')
      ? AppConfig.apiBaseUrl.substring(0, AppConfig.apiBaseUrl.length - 1)
      : AppConfig.apiBaseUrl;
  return '$base$path';
}

/// Formatea un tamaño en bytes como `1.4 GB` / `820 MB`.
String formatFileSize(num? bytes) {
  if (bytes == null || bytes <= 0) return '';
  if (bytes >= 1e9) {
    return '${(bytes / 1e9).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1e6) {
    return '${(bytes / 1e6).toStringAsFixed(0)} MB';
  }
  if (bytes >= 1e3) {
    return '${(bytes / 1e3).toStringAsFixed(0)} KB';
  }
  return '$bytes B';
}

/// Contenido del catálogo (película, serie, anime, novela, libro o álbum).
class CatalogItem {
  const CatalogItem({
    this.title,
    this.categoryKey,
    this.categoryIcon,
    this.tmdbType,
    this.square = false,
    this.artist,
    this.album,
    this.poster,
    this.genres,
    this.itemKey,
    this.chatId,
    this.msgId,
    this.size,
    this.groupKind,
    this.episodeCount = 0,
    this.popularity,
    this.letter,
    this.isNew = false,
    this.favorited = false,
    this.watched = false,
    this.kind,
    this.episode,
    this.progressPct,
    this.positionSeconds,
  });

  factory CatalogItem.fromJson(Map<String, dynamic> json) {
    return CatalogItem(
      title: json['title'] as String?,
      categoryKey: json['category_key'] as String?,
      categoryIcon: json['category_icon'] as String?,
      tmdbType: json['tmdb_type'] as String?,
      square: json['square'] == true,
      artist: json['artist'] as String?,
      album: json['album']?.toString(),
      poster: json['poster'] as String?,
      genres: json['genres'] as String?,
      itemKey: json['item_key'] as String?,
      chatId: (json['chat_id'] as num?)?.toInt(),
      msgId: (json['msg_id'] as num?)?.toInt(),
      size: (json['size'] as num?)?.toInt(),
      groupKind: json['group_kind'] as String?,
      episodeCount: (json['episode_count'] as num?)?.toInt() ?? 0,
      popularity: (json['popularity'] as num?)?.toInt(),
      letter: json['letter']?.toString(),
      isNew: json['is_new'] == true,
      favorited: json['favorited'] == true,
      watched: json['watched'] == true,
      kind: json['kind'] as String?,
      episode: json['episode'] as String?,
      progressPct: (json['progress_pct'] as num?)?.toDouble(),
      positionSeconds: (json['position_s'] as num?)?.toDouble(),
    );
  }

  final String? title;
  final String? categoryKey;
  final String? categoryIcon;
  final String? tmdbType;
  final bool square;
  final String? artist;

  /// Álbum de un grupo de música (puede ser `""` para los sencillos).
  final String? album;
  final String? poster;
  final String? genres;
  final String? itemKey;
  final int? chatId;
  final int? msgId;
  final int? size;
  final String? groupKind;
  final int episodeCount;
  final int? popularity;

  /// Letra del índice A-Z (`sort=alpha`), calculada por el backend.
  final String? letter;
  final bool isNew;

  /// Marcado como favorito por el usuario (`/api/movies`, `/api/favorites`).
  final bool favorited;
  final bool watched;
  final String? kind;
  final String? episode;
  final double? progressPct;
  final double? positionSeconds;

  String get posterUrl => absoluteMediaUrl(poster);

  bool get isSeries => groupKind == 'series';

  bool get isAlbum => groupKind == 'album';

  /// Películas, series y libros se pueden marcar como favoritos; la música
  /// queda fuera a propósito (igual que en el backend).
  bool get canFavorite =>
      categoryKey != 'music' && (groupKind == null || isSeries);

  /// Texto del badge inferior (tamaño o cantidad de episodios).
  String get bottomBadge {
    if (isSeries && episode != null) return episode!;
    if (isSeries && episodeCount > 0) return '$episodeCount ep';
    if (isAlbum && episodeCount > 0) {
      return '$episodeCount ${episodeCount == 1 ? 'pista' : 'pistas'}';
    }
    return formatFileSize(size);
  }
}

/// Integrante del reparto (`GET /api/info`).
class CastMember {
  const CastMember({this.name, this.character, this.photo});

  factory CastMember.fromJson(Map<String, dynamic> json) {
    return CastMember(
      name: json['name'] as String?,
      character: json['character'] as String?,
      photo: json['photo'] as String?,
    );
  }

  final String? name;
  final String? character;
  final String? photo;

  String get photoUrl => absoluteMediaUrl(photo);
}

/// Ficha de un título (`GET /api/info?title=...&type=...`).
class ContentInfo {
  const ContentInfo({
    this.title,
    this.posterUrl,
    this.overview,
    this.rating,
    this.genres,
    this.year,
    this.cast = const [],
    this.trailerKey,
  });

  factory ContentInfo.fromJson(Map<String, dynamic> json) {
    final rawCast = json['cast'];
    return ContentInfo(
      title: json['title'] as String?,
      posterUrl: json['poster_url'] as String?,
      overview: json['overview'] as String?,
      rating: json['rating']?.toString(),
      genres: json['genres'] as String?,
      year: json['year']?.toString(),
      cast: rawCast is List
          ? rawCast
                .whereType<Map>()
                .map((e) => CastMember.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      trailerKey: json['trailer_key']?.toString(),
    );
  }

  final String? title;
  final String? posterUrl;
  final String? overview;
  final String? rating;
  final String? genres;
  final String? year;
  final List<CastMember> cast;
  final String? trailerKey;

  bool get hasYear => year != null && year!.isNotEmpty && year != 'N/A';

  bool get hasRating => rating != null && rating!.isNotEmpty && rating != 'N/A';

  bool get hasOverview =>
      overview != null &&
      overview!.isNotEmpty &&
      overview != 'Sinopsis no disponible.';
}

/// Fila de género del home (`GET /api/home-genres`).
class GenreRow {
  const GenreRow({
    this.id,
    this.label,
    this.accent,
    this.rgb,
    this.icon,
    this.items = const [],
  });

  factory GenreRow.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return GenreRow(
      id: json['id'] as String?,
      label: json['label'] as String?,
      accent: json['accent'] as String?,
      rgb: json['rgb'] as String?,
      icon: json['icon'] as String?,
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map((e) => CatalogItem.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
    );
  }

  final String? id;
  final String? label;
  final String? accent;
  final String? rgb;
  final String? icon;
  final List<CatalogItem> items;
}

/// Punto de salto del índice A-Z (`letters` de `GET /api/movies?sort=alpha`).
///
/// `index` es la posición global del primer título que empieza por `letter`
/// dentro de todo el listado ordenado; el índice lateral la usa para pedir la
/// página exacta donde cae esa letra.
class CatalogLetter {
  const CatalogLetter({required this.letter, required this.index});

  factory CatalogLetter.fromJson(Map<String, dynamic> json) {
    return CatalogLetter(
      letter: json['letter']?.toString() ?? '',
      index: (json['index'] as num?)?.toInt() ?? 0,
    );
  }

  final String letter;
  final int index;
}

/// Página de catálogo (`GET /api/movies`).
class CatalogPage {
  const CatalogPage({
    this.items = const [],
    this.page = 1,
    this.pages = 1,
    this.total = 0,
    this.letters = const [],
  });

  factory CatalogPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final rawLetters = json['letters'];
    return CatalogPage(
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map((e) => CatalogItem.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      page: (json['page'] as num?)?.toInt() ?? 1,
      pages: (json['pages'] as num?)?.toInt() ?? 1,
      total: (json['total'] as num?)?.toInt() ?? 0,
      letters: rawLetters is List
          ? rawLetters
                .whereType<Map>()
                .map(
                  (e) => CatalogLetter.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const [],
    );
  }

  final List<CatalogItem> items;
  final int page;
  final int pages;
  final int total;
  final List<CatalogLetter> letters;

  bool get hasMore => page < pages;
}

/// Estadísticas públicas del sitio (`GET /api/stats`).
class SiteStats {
  const SiteStats({
    this.registeredUsers,
    this.onlineNow,
    this.totalDownloads,
    this.totalStreams,
    this.activeSubscriptions,
    this.catalogSize,
    this.moviesCount,
    this.seriesCount,
    this.animeCount,
    this.novelasCount,
    this.musicCount,
    this.newToday,
    this.activityToday,
    this.watchingNow,
    this.watchingCapacity,
  });

  factory SiteStats.fromJson(Map<String, dynamic> json) {
    return SiteStats(
      registeredUsers: (json['registered_users'] as num?)?.toInt(),
      onlineNow: (json['online_now'] as num?)?.toInt(),
      totalDownloads: (json['total_downloads'] as num?)?.toInt(),
      totalStreams: (json['total_streams'] as num?)?.toInt(),
      activeSubscriptions: (json['active_subscriptions'] as num?)?.toInt(),
      catalogSize: (json['catalog_size'] as num?)?.toInt(),
      moviesCount: (json['movies_count'] as num?)?.toInt(),
      seriesCount: (json['series_count'] as num?)?.toInt(),
      animeCount: (json['anime_count'] as num?)?.toInt(),
      novelasCount: (json['novelas_count'] as num?)?.toInt(),
      musicCount: (json['music_count'] as num?)?.toInt(),
      newToday: (json['new_today'] as num?)?.toInt(),
      activityToday: (json['activity_today'] as num?)?.toInt(),
      watchingNow: (json['watching_now'] as num?)?.toInt(),
      watchingCapacity: (json['watching_capacity'] as num?)?.toInt(),
    );
  }

  final int? registeredUsers;
  final int? onlineNow;
  final int? totalDownloads;
  final int? totalStreams;
  final int? activeSubscriptions;
  final int? catalogSize;
  final int? moviesCount;
  final int? seriesCount;
  final int? animeCount;
  final int? novelasCount;
  final int? musicCount;
  final int? newToday;
  final int? activityToday;
  final int? watchingNow;
  final int? watchingCapacity;
}

/// Configuración pública del sitio (`GET /api/config`).
class SiteConfig {
  const SiteConfig({
    this.botUsername,
    this.whatsappUrl,
    this.paymentCard,
    this.paymentPhone,
    this.paymentName,
    this.mobileBalancePhone,
  });

  factory SiteConfig.fromJson(Map<String, dynamic> json) {
    return SiteConfig(
      botUsername: json['bot_username'] as String?,
      whatsappUrl: json['whatsapp_url'] as String?,
      paymentCard: json['payment_card'] as String?,
      paymentPhone: json['payment_phone'] as String?,
      paymentName: json['payment_name'] as String?,
      mobileBalancePhone: json['mobile_balance_phone'] as String?,
    );
  }

  final String? botUsername;
  final String? whatsappUrl;
  final String? paymentCard;
  final String? paymentPhone;
  final String? paymentName;
  final String? mobileBalancePhone;
}

/// Plan del catálogo de suscripciones (`GET /api/plans`).
class PlanInfo {
  const PlanInfo({
    this.key,
    this.name,
    this.priceCup,
    this.priceUsd,
    this.downloadLimit,
    this.streamLimit,
    this.compressedLimit,
    this.musicDownloadLimit,
    this.musicStreamLimit,
    this.unlimited = false,
    this.cupMinWeeks,
    this.cupMaxWeeks,
    this.cupDiscountMinWeeks,
    this.cupDiscountRate,
  });

  factory PlanInfo.fromJson(Map<String, dynamic> json) {
    return PlanInfo(
      key: json['key'] as String?,
      name: json['name'] as String?,
      priceCup: (json['price_cup'] as num?)?.toDouble(),
      priceUsd: (json['price_usd'] as num?)?.toDouble(),
      downloadLimit: (json['download_limit'] as num?)?.toInt(),
      streamLimit: (json['stream_limit'] as num?)?.toInt(),
      compressedLimit: (json['compressed_limit'] as num?)?.toInt(),
      musicDownloadLimit: (json['music_download_limit'] as num?)?.toInt(),
      musicStreamLimit: (json['music_stream_limit'] as num?)?.toInt(),
      unlimited: json['unlimited'] == true,
      cupMinWeeks: (json['cup_min_weeks'] as num?)?.toInt(),
      cupMaxWeeks: (json['cup_max_weeks'] as num?)?.toInt(),
      cupDiscountMinWeeks: (json['cup_discount_min_weeks'] as num?)?.toInt(),
      cupDiscountRate: (json['cup_discount_rate'] as num?)?.toDouble(),
    );
  }

  final String? key;
  final String? name;
  final double? priceCup;
  final double? priceUsd;
  final int? downloadLimit;
  final int? streamLimit;
  final int? compressedLimit;
  final int? musicDownloadLimit;
  final int? musicStreamLimit;
  final bool unlimited;
  final int? cupMinWeeks;
  final int? cupMaxWeeks;
  final int? cupDiscountMinWeeks;
  final double? cupDiscountRate;
}

/// Consumo del plan del usuario (`GET /api/plans/me`).
class PlanUsage {
  const PlanUsage({
    this.plan,
    this.planName,
    this.unlimited = false,
    this.downloadsUsed,
    this.downloadLimit,
    this.streamsUsed,
    this.streamLimit,
    this.compressedUsed,
    this.compressedLimit,
    this.musicDownloadsUsed,
    this.musicDownloadLimit,
    this.musicStreamsUsed,
    this.musicStreamLimit,
    this.bonusDownloads,
    this.bonusStreams,
    this.resetInSeconds,
  });

  factory PlanUsage.fromJson(Map<String, dynamic> json) {
    return PlanUsage(
      plan: json['plan'] as String?,
      planName: json['plan_name'] as String?,
      unlimited: json['unlimited'] == true,
      downloadsUsed: (json['downloads_used'] as num?)?.toInt(),
      downloadLimit: (json['download_limit'] as num?)?.toInt(),
      streamsUsed: (json['streams_used'] as num?)?.toInt(),
      streamLimit: (json['stream_limit'] as num?)?.toInt(),
      compressedUsed: (json['compressed_used'] as num?)?.toInt(),
      compressedLimit: (json['compressed_limit'] as num?)?.toInt(),
      musicDownloadsUsed: (json['music_downloads_used'] as num?)?.toInt(),
      musicDownloadLimit: (json['music_download_limit'] as num?)?.toInt(),
      musicStreamsUsed: (json['music_streams_used'] as num?)?.toInt(),
      musicStreamLimit: (json['music_stream_limit'] as num?)?.toInt(),
      bonusDownloads: (json['bonus_downloads'] as num?)?.toInt(),
      bonusStreams: (json['bonus_streams'] as num?)?.toInt(),
      resetInSeconds: (json['reset_in_seconds'] as num?)?.toInt(),
    );
  }

  final String? plan;
  final String? planName;
  final bool unlimited;
  final int? downloadsUsed;
  final int? downloadLimit;
  final int? streamsUsed;
  final int? streamLimit;
  final int? compressedUsed;
  final int? compressedLimit;
  final int? musicDownloadsUsed;
  final int? musicDownloadLimit;
  final int? musicStreamsUsed;
  final int? musicStreamLimit;
  final int? bonusDownloads;
  final int? bonusStreams;
  final int? resetInSeconds;
}

/// Solicitud de pago pendiente de revisión (`pending_request` de
/// `GET /api/plans/me`).
class PendingPlanRequest {
  const PendingPlanRequest({
    required this.planKey,
    this.method,
    this.weeks,
    this.totalCup,
  });

  factory PendingPlanRequest.fromJson(Map<String, dynamic> json) {
    return PendingPlanRequest(
      planKey: json['plan_key']?.toString() ?? '',
      method: json['method']?.toString(),
      weeks: (json['weeks'] as num?)?.toInt(),
      totalCup: (json['total_cup'] as num?)?.toInt(),
    );
  }

  final String planKey;

  /// `transfermovil` (CUP), `qvapay` o `mobile_balance`.
  final String? method;
  final int? weeks;
  final int? totalCup;

  bool get isQvaPay => method == 'qvapay';
}

/// Notificación del usuario (`GET /api/notifications`).
class NotificationItem {
  const NotificationItem({
    this.id,
    this.title,
    this.body,
    this.url,
    this.imageUrl,
    this.read = false,
    this.createdAt,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: (json['id'] as num?)?.toInt(),
      title: json['title'] as String?,
      body: json['body'] as String?,
      url: json['url'] as String?,
      imageUrl: json['image_url'] as String?,
      read: json['read'] == true || json['read'] == 1,
      createdAt: json['created_at'] as String?,
    );
  }

  final int? id;
  final String? title;
  final String? body;
  final String? url;
  final String? imageUrl;
  final bool read;
  final String? createdAt;

  String get image => absoluteMediaUrl(imageUrl);
}

/// Reseña de la comunidad (`GET /api/reviews`).
class ReviewItem {
  const ReviewItem({
    this.displayName,
    this.rating,
    this.comment,
    this.createdAt,
    this.avatarUrl,
  });

  factory ReviewItem.fromJson(Map<String, dynamic> json) {
    return ReviewItem(
      displayName: json['display_name'] as String?,
      rating: (json['rating'] as num?)?.toInt(),
      comment: json['comment'] as String?,
      createdAt: json['created_at'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  final String? displayName;
  final int? rating;
  final String? comment;
  final String? createdAt;
  final String? avatarUrl;
}

/// Información de reproducción de un canal (`stream` en `TvChannel`).
class TvStreamInfo {
  const TvStreamInfo({required this.type, required this.url});

  factory TvStreamInfo.fromJson(Map<String, dynamic> json) {
    return TvStreamInfo(
      type: json['type']?.toString() ?? 'hls',
      url: json['url']?.toString() ?? '',
    );
  }

  /// `hls` (.m3u8) o `embed` (iframe de terceros como teveo.cu).
  final String type;
  final String url;

  bool get isHls => type == 'hls';
  bool get isEmbed => type == 'embed';
}

/// Canal de televisión o emisora de radio en vivo (`GET /api/tv/channels`).
class TvChannel {
  const TvChannel({
    required this.id,
    required this.kind,
    required this.group,
    required this.groupTitle,
    required this.name,
    required this.logo,
    required this.stream,
    this.tag,
    this.viewers,
  });

  factory TvChannel.fromJson(Map<String, dynamic> json) {
    final rawStream = json['stream'];
    return TvChannel(
      id: json['id']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'tv',
      group: json['group']?.toString() ?? 'cu',
      groupTitle: json['group_title']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      tag: json['tag']?.toString(),
      logo: json['logo']?.toString() ?? '',
      stream: rawStream is Map
          ? TvStreamInfo.fromJson(Map<String, dynamic>.from(rawStream))
          : const TvStreamInfo(type: 'hls', url: ''),
      viewers: (json['viewers'] as num?)?.toInt(),
    );
  }

  final String id;
  final String kind;
  final String group;
  final String groupTitle;
  final String name;
  final String? tag;
  final String logo;
  final TvStreamInfo stream;
  final int? viewers;

  String get logoUrl => absoluteMediaUrl(logo);
  bool get isRadio => kind == 'radio' || group == 'radio';

  TvChannel copyWith({int? viewers}) {
    return TvChannel(
      id: id,
      kind: kind,
      group: group,
      groupTitle: groupTitle,
      name: name,
      tag: tag,
      logo: logo,
      stream: stream,
      viewers: viewers ?? this.viewers,
    );
  }
}

/// Grupo de canales en `TvChannelList` (`cu`, `intl`, `radio`).
class TvChannelGroup {
  const TvChannelGroup({
    required this.key,
    required this.title,
    required this.count,
  });

  factory TvChannelGroup.fromJson(Map<String, dynamic> json) {
    return TvChannelGroup(
      key: json['key']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }

  final String key;
  final String title;
  final int count;
}

/// Respuesta de `GET /api/tv/channels`.
class TvChannelList {
  const TvChannelList({
    this.total = 0,
    this.groups = const [],
    this.channels = const [],
  });

  factory TvChannelList.fromJson(Map<String, dynamic> json) {
    final rawGroups = json['groups'];
    final rawChannels = json['channels'];
    return TvChannelList(
      total: (json['total'] as num?)?.toInt() ?? 0,
      groups: rawGroups is List
          ? rawGroups
                .whereType<Map>()
                .map(
                  (e) => TvChannelGroup.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const [],
      channels: rawChannels is List
          ? rawChannels
                .whereType<Map>()
                .map((e) => TvChannel.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
    );
  }

  final int total;
  final List<TvChannelGroup> groups;
  final List<TvChannel> channels;
}

/// Resultados de búsqueda en una categoría (`SearchCategoryResult`).
class SearchCategoryResult {
  const SearchCategoryResult({
    required this.key,
    required this.name,
    this.icon,
    this.grouping,
    this.total = 0,
    this.items = const [],
  });

  factory SearchCategoryResult.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return SearchCategoryResult(
      key: json['key']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      icon: json['icon']?.toString(),
      grouping: json['grouping']?.toString(),
      total: (json['total'] as num?)?.toInt() ?? 0,
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map((e) => CatalogItem.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
    );
  }

  final String key;
  final String name;
  final String? icon;
  final String? grouping;
  final int total;
  final List<CatalogItem> items;
}

/// Respuesta de búsqueda global (`GET /api/search`).
class SearchResponse {
  const SearchResponse({
    this.query = '',
    this.total = 0,
    this.categories = const [],
    this.tv = const [],
  });

  factory SearchResponse.fromJson(Map<String, dynamic> json) {
    final rawCategories = json['categories'];
    final rawTv = json['tv'];
    return SearchResponse(
      query: json['query']?.toString() ?? '',
      total: (json['total'] as num?)?.toInt() ?? 0,
      categories: rawCategories is List
          ? rawCategories
                .whereType<Map>()
                .map(
                  (e) => SearchCategoryResult.fromJson(
                    Map<String, dynamic>.from(e),
                  ),
                )
                .toList()
          : const [],
      tv: rawTv is List
          ? rawTv
                .whereType<Map>()
                .map((e) => TvChannel.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
    );
  }

  final String query;
  final int total;
  final List<SearchCategoryResult> categories;
  final List<TvChannel> tv;
}
