import '../../app_locale.dart';

/// Mapping strict backend -> UI, conforme à
/// 06_API_DB/BACKEND_ENUM_UI_MAPPING.md du kit UI Veyra.
///
/// "Interdiction : ces codes ne sont jamais rendus tels quels dans
/// l'interface." Toute nouvelle valeur backend rencontrée doit être
/// ajoutée ici plutôt que laissée passer brute (fallback explicite ci-
/// dessous plutôt que planter, mais visuellement signalé en dev).
class VeyraStatusLabels {
  VeyraStatusLabels._();

  static const Map<String, String> _bookingStatusFr = {
    'OPEN_FOR_OFFERS': 'Demande publiée',
    'OFFERS_RECEIVED': 'Offres reçues',
    'CONFIRMED': 'Réservation confirmée',
    'DRIVER_EN_ROUTE': 'Chauffeur en route',
    'DRIVER_ARRIVED': 'Chauffeur arrivé',
    'IN_PROGRESS': 'Course en cours',
    'COMPLETED': 'Terminée',
    'CLOSED': 'Terminée',
    'CANCELLED': 'Annulée',
    'CANCELLED_BY_CLIENT': 'Annulée',
    'CANCELLED_BY_DRIVER': 'Annulée par le chauffeur',
    'CUSTOMER_NO_SHOW': 'Client absent',
    'EXPIRED': 'Demande expirée',
    'NO_OFFER': 'Aucune offre reçue',
    'NO_DRIVER': 'Aucune offre reçue',
    'PAYMENT_PENDING': 'Paiement en attente',
    'PAYMENT_FAILED': 'Échec du paiement',
    'DISPUTED': 'Litige en cours',
  };

  static const Map<String, String> _bookingStatusEn = {
    'OPEN_FOR_OFFERS': 'Request published',
    'OFFERS_RECEIVED': 'Offers received',
    'CONFIRMED': 'Booking confirmed',
    'DRIVER_EN_ROUTE': 'Driver on the way',
    'DRIVER_ARRIVED': 'Driver arrived',
    'IN_PROGRESS': 'Trip in progress',
    'COMPLETED': 'Completed',
    'CLOSED': 'Completed',
    'CANCELLED': 'Cancelled',
    'CANCELLED_BY_CLIENT': 'Cancelled',
    'CANCELLED_BY_DRIVER': 'Cancelled by driver',
    'CUSTOMER_NO_SHOW': 'Customer no-show',
    'EXPIRED': 'Request expired',
    'NO_OFFER': 'No offer received',
    'NO_DRIVER': 'No offer received',
    'PAYMENT_PENDING': 'Payment pending',
    'PAYMENT_FAILED': 'Payment failed',
    'DISPUTED': 'Under dispute',
  };

  static const Map<String, String> _offerVisibilityFr = {
    'PRIVATE': 'Offre privée',
    'BEST_VISIBLE': 'Meilleure offre visible',
  };

  static const Map<String, String> _offerVisibilityEn = {
    'PRIVATE': 'Private offer',
    'BEST_VISIBLE': 'Best offer visible',
  };

  static const Map<String, String> _offerStatusFr = {
    'ACTIVE': 'En attente',
    'ACCEPTED': 'Retenue',
    'REJECTED_BY_SELECTION': 'Non retenue',
    'EXPIRED': 'Expirée',
    'WITHDRAWN': 'Retirée',
  };

  static const Map<String, String> _offerStatusEn = {
    'ACTIVE': 'Pending',
    'ACCEPTED': 'Won',
    'REJECTED_BY_SELECTION': 'Not selected',
    'EXPIRED': 'Expired',
    'WITHDRAWN': 'Withdrawn',
  };

  static bool get _isEnglish => AppLocale.code.value == 'en';

  static String bookingStatus(String? code) {
    if (code == null) return '—';
    final map = _isEnglish ? _bookingStatusEn : _bookingStatusFr;
    return map[code] ?? (_isEnglish ? 'Status update' : 'Mise à jour du statut');
  }

  static String offerVisibilityMode(String? code) {
    if (code == null) return '—';
    final map = _isEnglish ? _offerVisibilityEn : _offerVisibilityFr;
    return map[code] ?? map['PRIVATE']!;
  }

  static String offerStatus(String? code) {
    if (code == null) return '—';
    final map = _isEnglish ? _offerStatusEn : _offerStatusFr;
    return map[code] ?? (_isEnglish ? 'Update' : 'Mise à jour');
  }
}
