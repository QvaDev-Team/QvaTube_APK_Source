import 'package:flutter_test/flutter_test.dart';
import 'package:qvatube_apk/core/theme/season_calendar.dart';

void main() {
  DateTime cuba(int y, int m, int d, [int h = 12]) =>
      DateTime.utc(y, m, d, h).add(const Duration(hours: 5));

  test('ventanas de temporada (hora de Cuba, días inclusive)', () {
    expect(SeasonCalendar.current(cuba(2026, 9, 30)), isNull);
    expect(SeasonCalendar.current(cuba(2026, 10, 1, 0)), 'halloween');
    expect(SeasonCalendar.current(cuba(2026, 11, 2, 23)), 'halloween');
    expect(SeasonCalendar.current(cuba(2026, 11, 3, 0)), isNull);
    expect(SeasonCalendar.current(cuba(2026, 12, 1)), 'navidad');
    expect(SeasonCalendar.current(cuba(2027, 1, 6)), 'navidad');
    expect(SeasonCalendar.current(cuba(2027, 1, 7)), isNull);
    expect(SeasonCalendar.current(cuba(2027, 2, 7)), 'sanvalentin');
    expect(SeasonCalendar.current(cuba(2027, 2, 14)), 'sanvalentin');
    expect(SeasonCalendar.current(cuba(2027, 2, 15)), isNull);
  });

  test('imagen de la pantalla de carga', () {
    expect(SeasonCalendar.splashFor(cuba(2026, 11, 4)), 'assets/icons/icon-512.png');
    expect(SeasonCalendar.splashFor(cuba(2026, 12, 24)), 'assets/splash/navidad.png');
  });
}
