import 'package:dio/dio.dart';
import '../../app_locale.dart';

/// Mapping backend -> message utilisateur, conforme à
/// 10_ANTI_ERROR_PROTOCOL/ERROR_MAPPING.md du kit UI Veyra.
///
/// "Ne montre jamais au Client : INTERNAL_ERROR, stack trace, SQL error,
/// nom de classe Java, exception brute." Les 19 codes ci-dessous
/// reprennent le wording exact et autoritaire du kit. Le backend expose
/// aujourd'hui davantage de codes que ces 19 (audité : 80+) ; tout code
/// non listé retombe sur un message générique sûr plutôt que d'être
/// affiché brut — à enrichir au fil des lots suivants au fur et à mesure
/// que chaque écran rencontre un nouveau code, plutôt que d'inventer
/// maintenant un wording non validé pour des cas non encore travaillés.
///
/// LOT 3 (authentification) a ajouté les 3 entrées ci-dessous
/// (INVALID_CREDENTIALS, ACCOUNT_LOCKED, ACCOUNT_NOT_ACTIVE) : vérifiées
/// dans AuthController.login() comme étant les codes réellement levés,
/// absents des 19 officiels du kit.
class VeyraErrorMessages {
  VeyraErrorMessages._();

  static const Map<String, String> _fr = {
    'LEAD_TIME_TOO_SHORT': "Choisissez un départ au moins 2 heures à l'avance.",
    'PICKUP_OUTSIDE_SERVICE_ZONE': "Cette adresse de départ n'est pas encore desservie par Veyra.",
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
    'DRIVER_PROFILE_REQUIRED': "Complétez votre dossier chauffeur avant de continuer.",
    'PARTNER_SCOPE_FORBIDDEN': "Vous n'avez pas accès à ce compte partenaire.",
    'PARTNER_INVOICE_NOT_ELIGIBLE': "La facturation partenaire n'est pas disponible pour ce compte.",
    // LOT 3 additions -- vérifiés dans AuthController.login().
    'INVALID_CREDENTIALS': "Email ou mot de passe incorrect.",
    'ACCOUNT_LOCKED': "Compte temporairement verrouillé suite à plusieurs échecs. Réessayez plus tard.",
    'ACCOUNT_NOT_ACTIVE': "Ce compte n'est pas actif. Contactez le support.",
    'EMAIL_ALREADY_USED': "Un compte existe déjà avec cet email.",
  };

  static const Map<String, String> _en = {
    'LEAD_TIME_TOO_SHORT': 'Choose a pickup time at least 2 hours from now.',
    'PICKUP_OUTSIDE_SERVICE_ZONE': "This pickup address isn't covered by Veyra yet.",
    'OFFERS_CLOSED': 'This request no longer accepts new offers.',
    'BOOKING_OFFERS_CLOSED': 'This request no longer accepts new offers.',
    'ACTIVE_OFFER_EXISTS': 'You already have an active offer on this request.',
    'DRIVER_SCHEDULE_CONFLICT': 'This trip overlaps another confirmed booking.',
    'CASH_DEBT_LIMIT_REACHED': 'Your CASH commission debt is blocking new cash bookings.',
    'CASH_DEBT_RESTRICTED': 'Your access to CASH requests is currently limited.',
    'BOOKING_CLOSED': 'This booking has already been updated.',
    'OFFER_CLOSED': 'This offer is no longer available. Refresh the list.',
    'PARTNER_CREDIT_LIMIT_EXCEEDED': "The partner's billing limit has been reached.",
    'INVALID_PIN': 'Incorrect code. Check the code with the customer.',
    'PIN_TEMPORARILY_LOCKED': 'Too many attempts. Try again later.',
    'PAYMENT_REQUIRED': 'Online payment must be confirmed before starting.',
    'INVALID_BOOKING_TRANSITION': 'This action is no longer available in the current state.',
    'NOT_SELECTED_DRIVER': "This booking isn't assigned to your account.",
    'DRIVER_NOT_ELIGIBLE': "Your driver account isn't eligible yet.",
    'DRIVER_PROFILE_REQUIRED': 'Complete your driver profile before continuing.',
    'PARTNER_SCOPE_FORBIDDEN': "You don't have access to this partner account.",
    'PARTNER_INVOICE_NOT_ELIGIBLE': 'Partner invoicing is not available for this account.',
    // LOT 3 additions.
    'INVALID_CREDENTIALS': 'Incorrect email or password.',
    'ACCOUNT_LOCKED': 'Account temporarily locked after several failed attempts. Try again later.',
    'ACCOUNT_NOT_ACTIVE': 'This account is not active. Contact support.',
    'EMAIL_ALREADY_USED': 'An account already exists with this email.',
  };

  static bool get _isEnglish => AppLocale.code.value == 'en';

  /// [code] : le code d'erreur backend (ex: extrait de
  /// `response.data['code']`). Ne jamais passer le message brut du
  /// serveur ou une exception ici.
  static String forCode(String? code) {
    if (code == null) return _generic;
    final map = _isEnglish ? _en : _fr;
    return map[code] ?? _generic;
  }

  static String get _generic => _isEnglish
      ? 'Something went wrong. Please try again.'
      : "Une erreur est survenue. Veuillez réessayer.";

  static String get offline => _isEnglish
      ? 'No internet connection. Check your network and try again.'
      : 'Pas de connexion internet. Vérifiez votre réseau et réessayez.';

  /// Distingue OFFLINE (pas de réponse serveur du tout) de ERROR (le
  /// serveur a répondu avec un code métier) -- les deux sont des états
  /// UX distincts et obligatoires selon chaque fiche écran du kit,
  /// jamais fondus en un seul message générique.
  ///
  /// Centralise un pattern auparavant dupliqué manuellement dans
  /// plusieurs écrans (ex: `(e.response?.data is Map) ? ... : null`).
  static String forException(Object error) {
    if (error is DioException) {
      final isConnectivityIssue = error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout;
      if (isConnectivityIssue) return offline;
      final data = error.response?.data;
      final code = (data is Map) ? data['code']?.toString() : null;
      return forCode(code);
    }
    return _generic;
  }

  /// Extrait uniquement le code (utile quand l'appelant a besoin du code
  /// brut, ex: pour une logique de branchement, en plus du message).
  static String? codeFromException(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      return (data is Map) ? data['code']?.toString() : null;
    }
    return null;
  }
}
