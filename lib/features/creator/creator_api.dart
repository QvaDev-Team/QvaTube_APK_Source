import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_providers.dart';
import '../../core/network/endpoints/endpoints.dart';

/// Persona que se registró con el código del creador.
class CreatorReferral {
  const CreatorReferral({
    this.displayName,
    this.createdAt,
    this.amountCup,
    this.commissionStatus,
  });

  factory CreatorReferral.fromJson(Map<String, dynamic> json) => CreatorReferral(
        displayName: json['display_name']?.toString(),
        createdAt: parseUtc(json['created_at']),
        amountCup: (json['amount_cup'] as num?)?.toInt(),
        commissionStatus: json['commission_status']?.toString(),
      );

  final String? displayName;
  final DateTime? createdAt;

  /// Comisión que generó; `null` si solo se registró (no compró por CUP).
  final int? amountCup;
  final String? commissionStatus;
}

/// Pago al creador (solicitado, pagado o cancelado).
class CreatorPayout {
  const CreatorPayout({
    required this.amountCup,
    required this.status,
    this.note,
    this.requestedAt,
    this.paidAt,
  });

  factory CreatorPayout.fromJson(Map<String, dynamic> json) => CreatorPayout(
        amountCup: (json['amount_cup'] as num?)?.toInt() ?? 0,
        status: json['status']?.toString() ?? '',
        note: json['note']?.toString(),
        requestedAt: parseUtc(json['requested_at']),
        paidAt: parseUtc(json['paid_at']),
      );

  final int amountCup;

  /// `requested`, `paid` o `cancelled`.
  final String status;

  /// Mensaje del admin.
  final String? note;
  final DateTime? requestedAt;
  final DateTime? paidAt;
}

/// Datos del panel de `GET /api/creator/me`.
class CreatorPanel {
  const CreatorPanel({
    required this.code,
    required this.rate,
    required this.payoutInfo,
    required this.minPayoutCup,
    required this.canRequest,
    required this.hasOpenRequest,
    required this.registered,
    required this.buyers,
    required this.totalCup,
    required this.pendingCup,
    required this.requestedCup,
    required this.paidCup,
    required this.referred,
    required this.payouts,
  });

  factory CreatorPanel.fromJson(Map<String, dynamic> json) {
    int n(String key) => (json[key] as num?)?.toInt() ?? 0;
    List<Map<String, dynamic>> list(String key) => [
          for (final e in (json[key] as List?) ?? const [])
            if (e is Map) Map<String, dynamic>.from(e),
        ];
    return CreatorPanel(
      code: json['code']?.toString() ?? '',
      rate: (json['rate'] as num?)?.toDouble() ?? 0.1,
      payoutInfo: json['payout_info']?.toString() ?? '',
      minPayoutCup: n('min_payout_cup'),
      canRequest: json['can_request'] == true,
      hasOpenRequest: json['has_open_request'] == true,
      registered: n('registered'),
      buyers: n('buyers'),
      totalCup: n('total_cup'),
      pendingCup: n('pending_cup'),
      requestedCup: n('requested_cup'),
      paidCup: n('paid_cup'),
      referred: list('referred').map(CreatorReferral.fromJson).toList(),
      payouts: list('payouts').map(CreatorPayout.fromJson).toList(),
    );
  }

  final String code;
  final double rate;
  final String payoutInfo;
  final int minPayoutCup;
  final bool canRequest;
  final bool hasOpenRequest;
  final int registered;
  final int buyers;
  final int totalCup;
  final int pendingCup;
  final int requestedCup;
  final int paidCup;
  final List<CreatorReferral> referred;
  final List<CreatorPayout> payouts;
}

/// Fechas del backend: `YYYY-MM-DD HH:MM:SS` en UTC y sin zona.
DateTime? parseUtc(Object? raw) {
  final text = raw?.toString();
  if (text == null || text.isEmpty) return null;
  final iso = text.contains('T') ? text : text.replaceFirst(' ', 'T');
  return DateTime.tryParse(iso.endsWith('Z') ? iso : '${iso}Z')?.toLocal();
}

/// Endpoints del Modo creador (todos con la cookie de sesión).
class CreatorApi {
  const CreatorApi(this._client);

  final ApiClient _client;

  Future<CreatorPanel> panel() async {
    final response = await _client.get(
      Endpoints.creator.me,
      operation: 'el panel de creador',
    );
    return CreatorPanel.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  /// Guarda dónde cobrar (máx. 120) y devuelve el texto ya limpio.
  Future<String> savePayoutInfo(String info) async {
    final response = await _client.post(
      Endpoints.creator.payoutInfo,
      body: <String, dynamic>{'payout_info': info},
      operation: 'los datos de cobro',
    );
    final data = response.data;
    return data is Map ? data['payout_info']?.toString() ?? info : info;
  }

  /// Agrupa todas las comisiones pendientes en un pago; devuelve el monto.
  Future<int> requestPayout() async {
    final response = await _client.post(
      Endpoints.creator.payoutRequest,
      body: const <String, dynamic>{},
      operation: 'la solicitud de pago',
    );
    final data = response.data;
    return data is Map ? (data['amount_cup'] as num?)?.toInt() ?? 0 : 0;
  }

  Future<bool> cancelPayout() async {
    final response = await _client.post(
      Endpoints.creator.payoutCancel,
      body: const <String, dynamic>{},
      operation: 'la cancelación del pago',
    );
    final data = response.data;
    return data is Map && data['ok'] == true;
  }
}

final creatorApiProvider = Provider<CreatorApi>((ref) {
  return CreatorApi(ref.watch(apiClientProvider));
});
