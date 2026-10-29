import 'package:flutter_test/flutter_test.dart';
import 'package:qvatube_apk/features/account/presentation/plan_payment_screen.dart';

void main() {
  // Mismos valores que la web (computeCupTotalPreview en js/plans.js).
  test('sin descuento por debajo del mínimo de semanas', () {
    final r = computeCupTotal(
      pricePerWeek: 20,
      weeks: 3,
      discountMinWeeks: 4,
      discountRate: 0.1,
    );
    expect(r.total, 60);
    expect(r.discounted, isFalse);
  });

  test('aplica el descuento a partir del mínimo de semanas', () {
    final r = computeCupTotal(
      pricePerWeek: 100,
      weeks: 4,
      discountMinWeeks: 4,
      discountRate: 0.1,
    );
    expect(r.total, 360);
    expect(r.discounted, isTrue);
  });
}
