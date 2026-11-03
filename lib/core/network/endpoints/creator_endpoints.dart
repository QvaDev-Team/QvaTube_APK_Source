/// Programa de creadores oficiales (Modo creador).
final class CreatorEndpoints {
  const CreatorEndpoints();

  /// GET: Creator panel data (404 if the user is not an active creator)
  final String me = '/api/creator/me';

  /// POST: Save where the creator wants to be paid ({payout_info})
  final String payoutInfo = '/api/creator/payout-info';

  /// POST: Request payout of every pending commission ({})
  final String payoutRequest = '/api/creator/payout/request';

  /// POST: Cancel the open payout request ({})
  final String payoutCancel = '/api/creator/payout/cancel';
}
