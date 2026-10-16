abstract final class PromoEndpoints {
  const PromoEndpoints._();

  /// GET: Active collaborations for home banners
  static const String collabs = '/api/collabs';

  /// GET: Official partners list
  static const String partners = '/api/partners';

  /// GET: Testimonials list
  static const String testimonials = '/api/testimonials';

  /// GET: Music promo banner
  static const String musicPromo = '/api/music-promo';

  /// POST: Count music promo impression or click
  static const String musicPromoTrack = '/api/music-promo/track';
}

