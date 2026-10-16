abstract final class PlansEndpoints {
  const PlansEndpoints._();

  /// GET: List plan catalog with limits, prices (CUP/USD) and discounts
  static const String plans = '/api/plans';

  /// GET: User's plan usage and pending subscription request
  static const String me = '/api/plans/me';

  /// POST: Request a plan subscription (CUP / Transfermóvil)
  static const String subscribe = '/api/plans/subscribe';

  /// POST: Pay a plan with QvaPay (USD)
  static const String subscribeQvapay = '/api/plans/subscribe-qvapay';

  /// POST: Upload payment proof photo (CUP)
  static const String uploadProof = '/api/plans/upload-proof';

  /// POST: Cancel pending plan request
  static const String cancelPending = '/api/plans/cancel-pending';
}

