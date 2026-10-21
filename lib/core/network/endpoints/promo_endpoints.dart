final class PromoEndpoints {
  const PromoEndpoints();

  /// GET: Active collaborations for home banners
  final String collabs = '/api/collabs';

  /// GET: Official partners list
  final String partners = '/api/partners';

  /// GET: Testimonials list
  final String testimonials = '/api/testimonials';

  /// GET: Music promo banner
  final String musicPromo = '/api/music-promo';

  /// POST: Count music promo impression or click
  final String musicPromoTrack = '/api/music-promo/track';
}

