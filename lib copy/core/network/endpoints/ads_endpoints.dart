final class AdsEndpoints {
  const AdsEndpoints();

  /// GET: Ad configuration (enabled status and VAST tag URL)
  final String config = '/api/ads/config';

  /// POST: Start an ad session to unlock quota (returns nonce and TTL)
  final String request = '/api/ads/request';

  /// POST: Redeem the nonce after watching the ad to claim quota
  final String claim = '/api/ads/claim';
}

