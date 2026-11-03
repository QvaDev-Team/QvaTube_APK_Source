export 'ads_endpoints.dart';
export 'auth_endpoints.dart';
export 'catalog_endpoints.dart';
export 'creator_endpoints.dart';
export 'downloads_endpoints.dart';
export 'favorites_progress_endpoints.dart';
export 'media_endpoints.dart';
export 'misc_endpoints.dart';
export 'music_endpoints.dart';
export 'notifications_endpoints.dart';
export 'plans_endpoints.dart';
export 'playback_endpoints.dart';
export 'promo_endpoints.dart';
export 'reports_suggestions_endpoints.dart';
export 'reviews_endpoints.dart';
export 'tv_endpoints.dart';

import 'ads_endpoints.dart';
import 'auth_endpoints.dart';
import 'catalog_endpoints.dart';
import 'creator_endpoints.dart';
import 'downloads_endpoints.dart';
import 'favorites_progress_endpoints.dart';
import 'media_endpoints.dart';
import 'misc_endpoints.dart';
import 'music_endpoints.dart';
import 'notifications_endpoints.dart';
import 'plans_endpoints.dart';
import 'playback_endpoints.dart';
import 'promo_endpoints.dart';
import 'reports_suggestions_endpoints.dart';
import 'reviews_endpoints.dart';
import 'tv_endpoints.dart';

/// Centralized access to all API endpoints grouped by domain.
final class Endpoints {
  const Endpoints();

  static const AuthEndpoints auth = AuthEndpoints();
  static const CatalogEndpoints catalog = CatalogEndpoints();
  static const MusicEndpoints music = MusicEndpoints();
  static const PlaybackEndpoints playback = PlaybackEndpoints();
  static const MediaEndpoints media = MediaEndpoints();
  static const DownloadsEndpoints downloads = DownloadsEndpoints();
  static const FavoritesProgressEndpoints favoritesProgress =
      FavoritesProgressEndpoints();
  static const PlansEndpoints plans = PlansEndpoints();
  static const AdsEndpoints ads = AdsEndpoints();
  static const NotificationsEndpoints notifications = NotificationsEndpoints();
  static const ReportsSuggestionsEndpoints reportsSuggestions =
      ReportsSuggestionsEndpoints();
  static const ReviewsEndpoints reviews = ReviewsEndpoints();
  static const TvEndpoints tv = TvEndpoints();
  static const PromoEndpoints promo = PromoEndpoints();
  static const MiscEndpoints misc = MiscEndpoints();
  static const CreatorEndpoints creator = CreatorEndpoints();
}

