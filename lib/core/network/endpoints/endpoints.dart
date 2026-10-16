export 'ads_endpoints.dart';
export 'auth_endpoints.dart';
export 'catalog_endpoints.dart';
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
abstract final class Endpoints {
  const Endpoints._();

  static const auth = AuthEndpoints;
  static const catalog = CatalogEndpoints;
  static const music = MusicEndpoints;
  static const playback = PlaybackEndpoints;
  static const media = MediaEndpoints;
  static const downloads = DownloadsEndpoints;
  static const favoritesProgress = FavoritesProgressEndpoints;
  static const plans = PlansEndpoints;
  static const ads = AdsEndpoints;
  static const notifications = NotificationsEndpoints;
  static const reportsSuggestions = ReportsSuggestionsEndpoints;
  static const reviews = ReviewsEndpoints;
  static const tv = TvEndpoints;
  static const promo = PromoEndpoints;
  static const misc = MiscEndpoints;
}

