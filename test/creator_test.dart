import 'package:flutter_test/flutter_test.dart';
import 'package:qvatube_apk/features/auth/domain/auth_models.dart';
import 'package:qvatube_apk/features/creator/creator_api.dart';
import 'package:qvatube_apk/features/creator/creator_screen.dart';

void main() {
  test('user.creator decide si hay Modo creador', () {
    final creator = AuthUser.fromJson({
      'user': {
        'id': 42,
        'email': 'alex@correo.com',
        'creator': {'code': 'ALEX', 'rate': 0.1},
      },
    });
    expect(creator.creator?.code, 'ALEX');
    expect(creator.creator?.rate, 0.1);
    expect(creator.copyWith(displayName: 'Alex').creator?.code, 'ALEX');

    final normal = AuthUser.fromJson({
      'user': {'id': 7, 'creator': null},
    });
    expect(normal.creator, isNull);
  });

  test('lee el panel de /api/creator/me', () {
    final panel = CreatorPanel.fromJson({
      'code': 'ALEX',
      'rate': 0.1,
      'payout_info': '9200 1234 5678 9012',
      'min_payout_cup': 1,
      'can_request': true,
      'has_open_request': false,
      'registered': 4,
      'buyers': 2,
      'total_cup': 560,
      'pending_cup': 560,
      'requested_cup': 0,
      'paid_cup': 0,
      'referred': [
        {
          'display_name': 'Bob',
          'created_at': '2026-11-03 14:20:11',
          'amount_cup': 200,
          'base_cup': 2000,
          'commission_status': 'pending',
        },
        {
          'display_name': 'Eve',
          'created_at': '2026-11-03 15:02:40',
          'amount_cup': null,
          'commission_status': null,
        },
      ],
      'payouts': [
        {
          'id': 3,
          'amount_cup': 560,
          'status': 'paid',
          'note': 'Transferido',
          'requested_at': '2026-11-05 10:00:00',
          'paid_at': '2026-11-05 18:30:00',
        },
      ],
    });
    expect(panel.pendingCup, 560);
    expect(panel.canRequest, isTrue);
    expect(panel.referred.first.amountCup, 200);
    expect(panel.referred.last.amountCup, isNull);
    expect(panel.payouts.single.status, 'paid');
    expect(
      panel.payouts.single.paidAt,
      DateTime.utc(2026, 11, 5, 18, 30).toLocal(),
    );
  });

  test('montos en CUP con miles separados por espacio', () {
    expect(formatCup(0), '0 CUP');
    expect(formatCup(560), '560 CUP');
    expect(formatCup(2000), '2 000 CUP');
    expect(formatCup(1234567), '1 234 567 CUP');
  });
}
