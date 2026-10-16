abstract final class AdsEndpoints {
  const AdsEndpoints._();

  /// GET: Ad configuration (enabled status and VAST tag URL)
  static const String config = '/api/ads/config';

  /// POST: Start an ad session to unlock quota (returns nonce and TTL)
  static const String request = '/api/ads/request';

  /// POST: Redeem the nonce after watching the ad to claim quota
  static const String claim = '/api/ads/claim';
}

