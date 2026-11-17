import 'package:flutter_test/flutter_test.dart';
import 'package:qvatube_apk/core/utils/compact_number.dart';

void main() {
  test('formatea la popularidad en forma corta', () {
    expect(formatCompactNumber(0), '0');
    expect(formatCompactNumber(779), '779');
    expect(formatCompactNumber(999), '999');
    expect(formatCompactNumber(1000), '1K');
    expect(formatCompactNumber(1900), '1.9K');
    expect(formatCompactNumber(1999), '1.9K');
    expect(formatCompactNumber(2000), '2K');
    expect(formatCompactNumber(15430), '15.4K');
    expect(formatCompactNumber(150000), '150K');
    expect(formatCompactNumber(999999), '999K');
    expect(formatCompactNumber(1000000), '1M');
    expect(formatCompactNumber(2450000), '2.4M');
    expect(formatCompactNumber(1200000000), '1.2B');
  });
}
