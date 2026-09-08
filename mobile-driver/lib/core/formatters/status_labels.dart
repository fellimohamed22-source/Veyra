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

  static const Map<String, String> _kycStatusFr = {
    'DRAFT': 'Dossier à compléter',
    'SUBMITTED': 'Vérification en cours',
    'APPROVED': 'Dossier approuvé',
    'REJECTED': 'Dossier refusé',
  };

  static const Map<String, String> _kycStatusEn = {
    'DRAFT': 'Application to complete',
    'SUBMITTED': 'Under review',
    'APPROVED': 'Application approved',
    'REJECTED': 'Application rejected',
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

  static String kycStatus(String? code) {
    if (code == null) return '—';
    final map = _isEnglish ? _kycStatusEn : _kycStatusFr;
    return map[code] ?? map['DRAFT']!;
  }

  static const Map<String, String> _notificationTemplateFr = {
    'NEW_BOOKING': 'Nouvelle demande disponible',
    'NEW_OFFER': 'Nouvelle offre reçue',
    'OFFER_ACCEPTED': 'Votre offre a été retenue',
    'BOOKING_STATUS': 'Mise à jour de votre réservation',
  };

  static const Map<String, String> _notificationTemplateEn = {
    'NEW_BOOKING': 'New request available',
    'NEW_OFFER': 'New offer received',
    'OFFER_ACCEPTED': 'Your offer was selected',
    'BOOKING_STATUS': 'Booking update',
  };

  static String notificationTemplate(String? code) {
    if (code == null) return '—';
    final map = _isEnglish ? _notificationTemplateEn : _notificationTemplateFr;
    return map[code] ?? 'Notification';
  }

  // 6 event_type réels postés par LedgerService, vérifiés dans
  // BookingController.complete()/FinanceOpsController -- aucun autre
  // n'existe dans le code.
  static const Map<String, String> _ledgerEventFr = {
    'BOOKING_COMPLETED_CASH': 'Course terminée (espèces)',
    'BOOKING_COMPLETED_ONLINE': 'Course terminée (paiement en ligne)',
    'BOOKING_COMPLETED_PARTNER_INVOICE': 'Course terminée (facturation partenaire)',
    'DRIVER_CASH_DEBT_SETTLED': 'Dette CASH réglée',
    'DRIVER_PAYABLE_PAID': 'Versement reçu',
    'CUSTOMER_CASH_DEBT_PAID': 'Compensation annulation',
  };

  static const Map<String, String> _ledgerEventEn = {
    'BOOKING_COMPLETED_CASH': 'Trip completed (cash)',
    'BOOKING_COMPLETED_ONLINE': 'Trip completed (online payment)',
    'BOOKING_COMPLETED_PARTNER_INVOICE': 'Trip completed (partner invoicing)',
    'DRIVER_CASH_DEBT_SETTLED': 'CASH debt settled',
    'DRIVER_PAYABLE_PAID': 'Payout received',
    'CUSTOMER_CASH_DEBT_PAID': 'Cancellation compensation',
  };

  static String ledgerEvent(String? code) {
    if (code == null) return '—';
    final map = _isEnglish ? _ledgerEventEn : _ledgerEventFr;
    return map[code] ?? 'Transaction';
  }
}
