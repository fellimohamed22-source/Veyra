import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Deliberately lightweight: no new state-management dependency, no ARB
/// files/code generation (retrofitting flutter gen-l10n onto an
/// already-large, already-shipped single-file app would mean rewriting
/// every string reference twice -- once to extract it, once to reference
/// the generated class). Uses the French text itself as the lookup key:
/// t('Bienvenue') returns 'Bienvenue' in French (no lookup needed at
/// all) or the English translation when one exists, falling back to the
/// French original if a string was missed rather than showing a raw key
/// or crashing -- a missed translation is a display-language bug, never
/// a functional one.
class AppLocale {
  AppLocale._();

  static const _storage = FlutterSecureStorage();
  static const _storageKey = 'locale';

  /// 'fr' or 'en'. ValueNotifier so the root App widget can rebuild
  /// (via ValueListenableBuilder) the instant the person changes it,
  /// without needing a full state-management package for one value.
  static final ValueNotifier<String> code = ValueNotifier('fr');

  static Future<void> load() async {
    try {
      final saved = await _storage.read(key: _storageKey);
      if (saved == 'en' || saved == 'fr') code.value = saved!;
    } catch (_) {
      // No saved preference yet, or secure storage unavailable this run --
      // French remains the default, never a crash on startup over a
      // preference that isn't essential to the app functioning.
    }
  }

  static Future<void> set(String newCode) async {
    code.value = newCode;
    try {
      await _storage.write(key: _storageKey, value: newCode);
    } catch (_) {}
  }

  static String t(String french) {
    if (code.value != 'en') return french;
    return _en[french] ?? french;
  }

  static const Map<String, String> _en = {
    'Bienvenue': 'Welcome',
    'Connexion Veyra': 'Veyra sign in',
    'Email': 'Email',
    'Mot de passe': 'Password',
    'Se connecter': 'Sign in',
    'Mot de passe oublié ?': 'Forgot password?',
    'Créer un compte': 'Create an account',
    'Identifiants invalides ou service indisponible.': 'Invalid credentials or the service is unavailable.',
    'Prénom': 'First name',
    'Nom': 'Last name',
    'Téléphone': 'Phone',
    'Créer mon compte': 'Create my account',
    'Création…': 'Creating…',
    'Prénom, e-mail et mot de passe de 10 caractères minimum requis.': 'First name, email, and a password of at least 10 characters are required.',
    'Création du compte impossible. Vérifiez les informations ou utilisez un autre e-mail.': 'Could not create the account. Check the details or use a different email.',
    'Mot de passe oublié': 'Forgot password',
    'Saisissez votre e-mail. Le message ne révèle pas si un compte existe.': 'Enter your email. The message never reveals whether an account exists.',
    'Envoyer les instructions': 'Send instructions',
    'Si cet e-mail existe, les instructions de réinitialisation ont été envoyées.': 'If this email exists, reset instructions have been sent.',
    'Planifiez votre trajet': 'Plan your trip',
    'Nouvelle réservation': 'New booking',
    'Mes réservations': 'My bookings',
    'Aucune réservation': 'No bookings yet',
    'Votre prochain trajet apparaîtra ici.': 'Your next trip will appear here.',
    'Impossible de charger vos réservations': 'Could not load your bookings',
    'Réessayer': 'Try again',
    'Adresse de départ': 'Pickup address',
    'Destination': 'Destination',
    'Départ': 'Pickup',
    'Date et heure de départ': 'Departure date and time',
    'Minimum 2 h à l’avance': 'At least 2 hours ahead',
    'Passagers': 'Passengers',
    'Bagages': 'Luggage',
    'Catégorie de véhicule': 'Vehicle category',
    'Catégories indisponibles.': 'Categories unavailable.',
    'Mode de paiement': 'Payment method',
    'Cash — le total inclut la commission Veyra': 'Cash — the total includes the Veyra commission',
    'En ligne — paiement sécurisé': 'Online — secure payment',
    'Publier la demande': 'Publish the request',
    'Publication…': 'Publishing…',
    'Le départ doit être planifié au moins 2 heures à l’avance.': 'Departure must be scheduled at least 2 hours ahead.',
    'Complétez le trajet, la date et la catégorie.': 'Complete the route, date, and category.',
    'La réservation n’a pas pu être publiée. Vérifiez les informations puis réessayez.': 'The booking could not be published. Check the details and try again.',
    'Cette adresse de départ est hors de la zone de service actuelle (Marseille → Menton).': 'This pickup address is outside the current service area (Marseille → Menton).',
    'Utiliser ma position actuelle': 'Use my current location',
    'Activez la localisation du téléphone.': 'Turn on the phone\'s location.',
    'La localisation est nécessaire pour utiliser votre position actuelle.': 'Location access is needed to use your current location.',
    'Aucune adresse trouvée pour votre position actuelle.': 'No address was found for your current location.',
    'Impossible d’obtenir votre position actuelle.': 'Could not get your current location.',
    'Planifier une réservation': 'Plan a booking',
    'Choisissez librement selon le prix, le véhicule et le chauffeur.': 'Choose freely based on price, vehicle, and driver.',
    'Les chauffeurs VTC éligibles recevront la demande et pourront proposer leur prix. Vous verrez toutes les offres reçues.': 'Eligible drivers will receive the request and can propose their price. You\'ll see every offer received.',
    'Offres reçues': 'Offers received',
    'Aucune offre pour le moment. Vous serez notifié dès qu’un chauffeur propose un prix.': 'No offers yet. You\'ll be notified as soon as a driver proposes a price.',
    'Choisir': 'Choose',
    'Détail réservation': 'Booking details',
    'Statut': 'Status',
    'Chauffeur confirmé': 'Confirmed driver',
    'Afficher le PIN': 'Show PIN',
    'PIN : ': 'PIN: ',
    'Le PIN sera disponible à H-1.': 'The PIN will be available 1 hour before pickup.',
    'Annuler la réservation': 'Cancel the booking',
    'Réservation annulée. Frais éventuels : ': 'Booking cancelled. Any fee: ',
    'Annulation impossible dans l’état actuel.': 'Cancellation isn\'t possible in the current state.',
    'Noter le chauffeur': 'Rate the driver',
    'Merci pour votre avis !': 'Thanks for your feedback!',
    'Envoyer la note': 'Send rating',
    'Impossible d’envoyer la note pour le moment.': 'Could not send the rating right now.',
    'Cette réservation n’est plus ouverte aux offres.': 'This booking is no longer open for offers.',
    'Cette offre n’est plus disponible.': 'This offer is no longer available.',
    'Limite de crédit partenaire dépassée pour cette réservation.': 'Partner credit limit exceeded for this booking.',
    'Impossible de choisir cette offre pour le moment.': 'Could not choose this offer right now.',
    'Payer en ligne': 'Pay online',
    'Chat Veyra': 'Veyra chat',
    'Message non envoyé, réessayez': 'Message not sent, try again',
    'Suivre la course': 'Track the ride',
    'Paiement': 'Payment',
    'Impossible de charger le paiement.': 'Could not load the payment.',
    'Paiement en ligne non configuré sur cette version.': 'Online payment isn\'t configured on this version.',
    'Total à payer : ': 'Total to pay: ',
    'Paiement sécurisé': 'Secure payment',
    'Payer maintenant': 'Pay now',
    'Paiement…': 'Paying…',
    'Le paiement n’a pas été finalisé.': 'The payment wasn\'t completed.',
    'Total client': 'Customer total',
    'Ce total inclut le prix proposé par le chauffeur et la commission Veyra.': 'This total includes the driver\'s proposed price and the Veyra commission.',
    'Votre message': 'Your message',
    'Aucun message pour le moment.': 'No messages yet.',
    'Suivi en direct': 'Live tracking',
    'Position actuelle du chauffeur': 'Driver\'s current location',
    'Position en cours de mise à jour.': 'Position updating.',
    'Position indisponible': 'Position unavailable',
    'En attente de la première position GPS.': 'Waiting for the first GPS position.',
    'Mise à jour automatique toutes les 10 secondes.': 'Updates automatically every 10 seconds.',
    'Dernière position : ': 'Last position: ',
    'ETA destination : ': 'ETA to destination: ',
    'Appeler le chauffeur': 'Call the driver',
    'Notifications': 'Notifications',
    'Aucune notification pour le moment.': 'No notifications yet.',
    'Notifications indisponibles.': 'Notifications unavailable.',
    'Vérifiez votre connexion puis réessayez.': 'Check your connection and try again.',
    'Recherche d’adresse indisponible.': 'Address search unavailable.',
    'Impossible d’envoyer la demande pour le moment.': 'Could not send the request right now.',
  };
}
