import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/app_locale.dart';
import 'package:veyra_driver/core/formatters/date_formatter.dart';

void main() {
  // 2026-09-23 est un mercredi (vérifié indépendamment). Midi UTC est
  // utilisé pour que .toLocal() ne puisse jamais faire basculer la date
  // sur un autre jour calendaire, quel que soit le fuseau du runner CI.
  const iso = '2026-09-23T12:00:00Z';

  setUp(() => AppLocale.code.value = 'fr');

  test('no raw ISO date ever reaches the screen', () {
    final formatted = VeyraDateFormatter.dateTime(iso);
    expect(formatted, isNot(contains('T')));
    expect(formatted, isNot(contains('Z')));
    expect(formatted, contains('Mer.'));
    expect(formatted, contains('23'));
    expect(formatted, contains('sept.'));
  });

  test('dateOnly omits the time', () {
    expect(VeyraDateFormatter.dateOnly(iso), '23 sept.');
  });

  test('null or unparseable input renders a neutral placeholder, never crashes', () {
    expect(VeyraDateFormatter.dateTime(null), '—');
    expect(VeyraDateFormatter.dateTime('not-a-date'), '—');
  });

  test('switches to English month/weekday abbreviations', () {
    AppLocale.code.value = 'en';
    final formatted = VeyraDateFormatter.dateTime(iso);
    expect(formatted, contains('Wed.'));
    expect(formatted, contains('Sep.'));
  });

  test('relativeDay recognizes today', () {
    final now = DateTime.now();
    final todayIso = now.toUtc().toIso8601String();
    expect(VeyraDateFormatter.relativeDay(todayIso), contains("Aujourd'hui"));
  });
}
