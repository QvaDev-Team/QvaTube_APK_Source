import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_providers.dart';
import '../data/catalog_api.dart';
import '../domain/catalog_models.dart';

/// API del catálogo y de los datos públicos.
final catalogApiProvider = Provider<CatalogApi>((ref) {
  return CatalogApi(ref.watch(apiClientProvider));
});

/// Categorías del catálogo (`GET /api/categories`).
final categoriesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(catalogApiProvider).categories();
});

/// Estadísticas públicas del sitio (`GET /api/stats`).
/// Se refresca automáticamente cada 30 segundos para reflejar datos en tiempo real.
final siteStatsProvider = FutureProvider<SiteStats>((ref) async {
  // Timer para recargar periódicamente en tiempo real
  final timer = Stream.periodic(const Duration(seconds: 30)).listen((_) {
    ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);

  return ref.watch(catalogApiProvider).stats();
});

/// Configuración pública (`GET /api/config`).
final siteConfigProvider = FutureProvider<SiteConfig>((ref) async {
  return ref.watch(catalogApiProvider).config();
});

/// Filas de géneros del home (`GET /api/home-genres`).
final homeGenresProvider = FutureProvider<List<GenreRow>>((ref) async {
  return ref.watch(catalogApiProvider).homeGenres();
});

/// Recomendaciones del home (`GET /api/recommendations`).
final recommendationsProvider =
    FutureProvider<({List<CatalogItem> items, String? seasonLabel, String? source})>(
        (ref) async {
  return ref.watch(catalogApiProvider).recommendations();
});

/// "Seguir donde quedaste" (`GET /api/continue-watching`).
final continueWatchingProvider = FutureProvider<List<CatalogItem>>((ref) async {
  return ref.watch(catalogApiProvider).continueWatching();
});

/// Estrenos nuevos por categoría (`GET /api/new-content/counts`).
final newContentCountsProvider = FutureProvider<Map<String, int>>((ref) async {
  return ref.watch(catalogApiProvider).newContentCounts();
});

/// Notificaciones del usuario (`GET /api/notifications`).
final notificationsProvider =
    FutureProvider<({List<NotificationItem> items, int unread})>((ref) async {
  return ref.watch(catalogApiProvider).notifications();
});

/// Favoritos del usuario (`GET /api/favorites`).
final favoritesProvider = FutureProvider<List<CatalogItem>>((ref) async {
  return ref.watch(catalogApiProvider).favorites();
});

/// Catálogo de planes (`GET /api/plans`).
final plansProvider = FutureProvider<List<PlanInfo>>((ref) async {
  return ref.watch(catalogApiProvider).plans();
});

/// Consumo del plan del usuario (`GET /api/plans/me`).
final planUsageProvider =
    FutureProvider<({PlanUsage? usage, bool hasPendingRequest})>((ref) async {
  return ref.watch(catalogApiProvider).planUsage();
});

/// Reseñas de la comunidad (`GET /api/reviews`).
final reviewsProvider =
    FutureProvider<({double average, int total, List<ReviewItem> reviews})>(
        (ref) async {
  return ref.watch(catalogApiProvider).reviews();
});

/// Parámetros de una consulta al catálogo.
class CatalogQuery {
  const CatalogQuery({
    this.categoryKey,
    this.page = 1,
    this.genre,
    this.sort = 'recent',
  });

  final String? categoryKey;
  final int page;
  final String? genre;
  final String sort;

  @override
  bool operator ==(Object other) =>
      other is CatalogQuery &&
      other.categoryKey == categoryKey &&
      other.page == page &&
      other.genre == genre &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(categoryKey, page, genre, sort);
}

/// Página del catálogo (`GET /api/movies`).
final catalogPageProvider =
    FutureProvider.family<CatalogPage, CatalogQuery>((ref, query) async {
  return ref.watch(catalogApiProvider).catalog(
        categoryKey: query.categoryKey,
        page: query.page,
        genre: query.genre,
        sort: query.sort,
      );
});

/// Géneros de una categoría (`GET /api/genres`).
final categoryGenresProvider =
    FutureProvider.family<List<String>, String>((ref, categoryKey) async {
  return ref.watch(catalogApiProvider).genres(categoryKey);
});
