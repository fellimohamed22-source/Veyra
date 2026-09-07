import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/app_locale.dart';
import 'package:veyra_driver/core/formatters/status_labels.dart';

void main() {
  setUp(() => AppLocale.code.value = 'fr');

  test('booking status codes are humanized per BACKEND_ENUM_UI_MAPPING.md', () {
    expect(VeyraStatusLabels.bookingStatus('OPEN_FOR_OFFERS'), 'Demande publiée');
    expect(VeyraStatusLabels.bookingStatus('OFFERS_RECEIVED'), 'Offres reçues');
    expect(VeyraStatusLabels.bookingStatus('CONFIRMED'), 'Réservation confirmée');
    expect(VeyraStatusLabels.bookingStatus('DRIVER_EN_ROUTE'), 'Chauffeur en route');
    expect(VeyraStatusLabels.bookingStatus('DRIVER_ARRIVED'), 'Chauffeur arrivé');
    expect(VeyraStatusLabels.bookingStatus('IN_PROGRESS'), 'Course en cours');
    expect(VeyraStatusLabels.bookingStatus('COMPLETED'), 'Terminée');
    expect(VeyraStatusLabels.bookingStatus('CANCELLED'), 'Annulée');
    expect(VeyraStatusLabels.bookingStatus('EXPIRED'), 'Demande expirée');
  });

  test('offer visibility modes never show the raw backend enum', () {
    expect(VeyraStatusLabels.offerVisibilityMode('PRIVATE'), 'Offre privée');
    expect(VeyraStatusLabels.offerVisibilityMode('BEST_VISIBLE'), 'Meilleure offre visible');
    expect(VeyraStatusLabels.offerVisibilityMode('PRIVATE'), isNot('PRIVATE'));
    expect(VeyraStatusLabels.offerVisibilityMode('BEST_VISIBLE'), isNot('BEST_VISIBLE'));
  });

  test('an unmapped booking status never leaks the raw code', () {
    final label = VeyraStatusLabels.bookingStatus('SOME_FUTURE_STATUS');
    expect(label, isNot(contains('SOME_FUTURE_STATUS')));
  });

  test('a null status renders a neutral placeholder, never crashes', () {
    expect(VeyraStatusLabels.bookingStatus(null), '—');
    expect(VeyraStatusLabels.offerVisibilityMode(null), '—');
    expect(VeyraStatusLabels.offerStatus(null), '—');
  });

  test('offer statuses map to the D18 "Mes offres" tab labels', () {
    expect(VeyraStatusLabels.offerStatus('ACTIVE'), 'En attente');
    expect(VeyraStatusLabels.offerStatus('ACCEPTED'), 'Retenue');
    expect(VeyraStatusLabels.offerStatus('REJECTED_BY_SELECTION'), 'Non retenue');
  });

  test('switches to English when the app locale is English', () {
    AppLocale.code.value = 'en';
    expect(VeyraStatusLabels.bookingStatus('CONFIRMED'), 'Booking confirmed');
    expect(VeyraStatusLabels.offerVisibilityMode('BEST_VISIBLE'), 'Best offer visible');
  });
}
