import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/app_locale.dart';
import 'package:veyra_driver/core/formatters/error_messages.dart';

void main() {
  // Le kit UI (10_ANTI_ERROR_PROTOCOL/ERROR_MAPPING.md) fixe le wording
  // exact et autoritaire pour ces 19 codes. Ce test garde ce wording
  // synchronisé plutôt que de laisser dériver silencieusement.
  const officialFrenchMapping = {
    'LEAD_TIME_TOO_SHORT': "Choisissez un départ au moins 2 heures à l'avance.",
    'PICKUP_OUTSIDE_SERVICE_ZONE': "Cette adresse de départ est hors de la zone pilote actuelle (Sud de la France, Marseille - Menton).",
    'OFFERS_CLOSED': "Cette demande n'accepte plus de nouvelles offres.",
    'BOOKING_OFFERS_CLOSED': "Cette demande n'accepte plus de nouvelles offres.",
    'ACTIVE_OFFER_EXISTS': "Vous avez déjà une offre active pour cette demande.",
    'DRIVER_SCHEDULE_CONFLICT': "Cette course chevauche une autre réservation confirmée.",
    'CASH_DEBT_LIMIT_REACHED': "Votre dette de commissions CASH bloque les nouvelles réservations en espèces.",
    'CASH_DEBT_RESTRICTED': "Votre accès aux demandes CASH est actuellement limité.",
    'BOOKING_CLOSED': "Cette réservation a déjà été mise à jour.",
    'OFFER_CLOSED': "Cette offre n'est plus disponible. Actualisez la liste.",
    'PARTNER_CREDIT_LIMIT_EXCEEDED': "Le plafond de facturation du partenaire est atteint.",
    'INVALID_PIN': "Code incorrect. Vérifiez le code avec le client.",
    'PIN_TEMPORARILY_LOCKED': "Trop de tentatives. Réessayez plus tard.",
    'PAYMENT_REQUIRED': "Le paiement en ligne doit être confirmé avant le démarrage.",
    'INVALID_BOOKING_TRANSITION': "Cette action n'est plus disponible dans l'état actuel.",
    'NOT_SELECTED_DRIVER': "Cette réservation n'est pas attribuée à votre compte.",
    'DRIVER_NOT_ELIGIBLE': "Votre compte chauffeur n'est pas encore éligible.",
    'PARTNER_SCOPE_FORBIDDEN': "Vous n'avez pas accès à ce compte partenaire.",
    'PARTNER_INVOICE_NOT_ELIGIBLE': "La facturation partenaire n'est pas disponible pour ce compte.",
  };

  setUp(() => AppLocale.code.value = 'fr');

  test('every officially mapped code matches the kit wording exactly', () {
    for (final entry in officialFrenchMapping.entries) {
      expect(VeyraErrorMessages.forCode(entry.key), entry.value, reason: entry.key);
    }
  });

  test('an unknown backend code never leaks raw and never crashes', () {
    final message = VeyraErrorMessages.forCode('SOME_FUTURE_BACKEND_CODE_NOT_YET_MAPPED');
    expect(message, isNot(contains('SOME_FUTURE_BACKEND_CODE')));
    expect(message, isNotEmpty);
  });

  test('a null code returns the generic fallback, never null', () {
    expect(VeyraErrorMessages.forCode(null), isNotEmpty);
  });

  test('switches to English when the app locale is English', () {
    AppLocale.code.value = 'en';
    expect(VeyraErrorMessages.forCode('INVALID_PIN'), 'Incorrect code. Check the code with the customer.');
  });

  // Real gap fixed here: DriverLocationTracker throws a plain
  // StateError (not a DioException) when the device's location service
  // is off or permission was refused. forException() previously only
  // recognized DioException, so these silently fell through to the
  // generic "Une erreur est survenue" message -- giving the driver zero
  // indication of what was actually wrong or how to fix it.
  test('a StateError with a known location code gets its real message, not the generic one', () {
    final message = VeyraErrorMessages.forException(StateError('LOCATION_SERVICE_DISABLED'));
    expect(message, "Activez la localisation de votre appareil pour partager votre position pendant la course.");
  });

  test('a StateError for denied permission gets its real message too', () {
    final message = VeyraErrorMessages.forException(StateError('LOCATION_PERMISSION_DENIED'));
    expect(message, contains('position'));
    expect(message, isNot(VeyraErrorMessages.forCode('SOME_FUTURE_BACKEND_CODE_NOT_YET_MAPPED')));
  });

  test('a StateError with an unrecognized message still falls back safely', () {
    final message = VeyraErrorMessages.forException(StateError('something totally unexpected'));
    expect(message, isNotEmpty);
    expect(message, isNot(contains('something totally unexpected')));
  });
}
