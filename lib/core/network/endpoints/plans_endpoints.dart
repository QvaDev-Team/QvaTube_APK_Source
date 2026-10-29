final class PlansEndpoints {
  const PlansEndpoints();

  /// GET: List plan catalog with limits, prices (CUP/USD) and discounts
  final String plans = '/api/plans';

  /// GET: User's plan usage and pending subscription request
  final String me = '/api/plans/me';

  /// POST: Request a plan subscription (CUP / Transfermóvil)
  final String subscribe = '/api/plans/subscribe';

  /// POST: Pay a plan with QvaPay (USD)
  final String subscribeQvapay = '/api/plans/subscribe-qvapay';

  /// POST: Pay QvaTube Ultra with mobile balance (Saldo Móvil)
  final String subscribeMobileBalance = '/api/plans/subscribe-mobile-balance';

  /// POST: Upload payment proof photo (CUP)
  final String uploadProof = '/api/plans/upload-proof';

  /// POST: Cancel pending plan request
  final String cancelPending = '/api/plans/cancel-pending';
}

