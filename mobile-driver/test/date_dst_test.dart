import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/app_locale.dart';
import 'package:veyra_driver/core/formatters/date_formatter.dart';

void main() {
  tearDown(() => AppLocale.code.value = 'fr');
  test('relative dates remain calendar dates across the Paris 23-hour day', () {
    // CI explicitly uses Europe/Paris so this is a real DST boundary.
    expect(DateTime(2026, 3, 30).difference(DateTime(2026, 3, 29)),
        const Duration(hours: 23));
    final now = DateTime(2026, 3, 29, 12);
    for (final language in ['fr', 'en']) {
      AppLocale.code.value = language;
      final tomorrow = VeyraDateFormatter.relativeDay(
          DateTime(2026, 3, 30, 12).toUtc().toIso8601String(),
          now: now);
      expect(
          tomorrow, language == 'fr' ? 'Demain • 12:00' : 'Tomorrow • 12:00');
      final later = VeyraDateFormatter.relativeDay(
          DateTime(2026, 3, 31, 12).toUtc().toIso8601String(),
          now: now);
      expect(later,
          language == 'fr' ? 'Mar. 31 mars • 12:00' : 'Tue. Mar. 31 • 12:00');
    }
  });
}
