import 'package:flutter_test/flutter_test.dart';
import 'package:qvatube_apk/features/auth/domain/auth_models.dart';

void main() {
  test('lee telegram_user_id de /api/auth/me', () {
    final user = AuthUser.fromJson({
      'user': {'id': 1, 'telegram_linked': true, 'telegram_user_id': 123456789},
    });
    expect(user.telegramUserId, 123456789);
    expect(AuthUser.fromJson(user.toJson()).telegramUserId, 123456789);
  });

  test('sin telegram_user_id (servidor viejo o sin verificar) queda null', () {
    expect(
      AuthUser.fromJson({
        'user': {'id': 1},
      }).telegramUserId,
      isNull,
    );
    expect(
      AuthUser.fromJson({
        'user': {'id': 1, 'telegram_user_id': null},
      }).telegramUserId,
      isNull,
    );
  });

  test('copyWith conserva telegram_user_id', () {
    final user = AuthUser.fromJson({
      'user': {'id': 1, 'telegram_user_id': 42},
    }).copyWith(plan: 'ultra');
    expect(user.telegramUserId, 42);
  });
}
