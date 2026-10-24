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
    this.poster,
    this.genres,
    this.itemKey,
    this.chatId,
    this.msgId,
    this.size,
    this.groupKind,
    this.episodeCount = 0,
    this.popularity,
    this.isNew = false,
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
      poster: json['poster'] as String?,
      genres: json['genres'] as String?,
      itemKey: json['item_key'] as String?,
      chatId: (json['chat_id'] as num?)?.toInt(),
      msgId: (json['msg_id'] as num?)?.toInt(),
      size: (json['size'] as num?)?.toInt(),
      groupKind: json['group_kind'] as String?,
      episodeCount: (json['episode_count'] as num?)?.toInt() ?? 0,
      popularity: (json['popularity'] as num?)?.toInt(),
      isNew: json['is_new'] == true,
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
  final String? poster;
  final String? genres;
  final String? itemKey;
  final int? chatId;
  final int? msgId;
  final int? size;
  final String? groupKind;
  final int episodeCount;
  final int? popularity;
  final bool isNew;
  final String? kind;
  final String? episode;
  final double? progressPct;
  final double? positionSeconds;

  String get posterUrl => absoluteMediaUrl(poster);

  bool get isSeries => groupKind == 'series';

  bool get isAlbum => groupKind == 'album';

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
          ? rawLetters.map((e) => e.toString()).toList()
          : const [],
    );
  }

  final List<CatalogItem> items;
  final int page;
  final int pages;
  final int total;
  final List<String> letters;

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
