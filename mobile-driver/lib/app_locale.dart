import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Same design as the client app's AppLocale -- see that file's own
/// comment for the full reasoning (French text as the lookup key itself,
/// no ARB/codegen, no new state-management dependency).
class AppLocale {
  AppLocale._();

  static const _storage = FlutterSecureStorage();
  static const _storageKey = 'locale';

  static final ValueNotifier<String> code = ValueNotifier('fr');

  static Future<void> load() async {
    try {
      final saved = await _storage.read(key: _storageKey);
      if (saved == 'en' || saved == 'fr') code.value = saved!;
    } catch (_) {}
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
    'Veyra Chauffeur': 'Veyra Driver',
    'Espace Chauffeur': 'Driver space',
    'Connectez-vous à votre compte': 'Sign in to your account',
    'Email': 'Email',
    'Mot de passe': 'Password',
    'Se connecter': 'Sign in',
    'Connexion impossible.': 'Could not sign in.',
    'Créer un compte Chauffeur': 'Create a Driver account',
    'Prénom': 'First name',
    'Nom': 'Last name',
    'Téléphone': 'Phone',
    'Création…': 'Creating…',
    'Prénom, e-mail et mot de passe de 10 caractères minimum requis.': 'First name, email, and a password of at least 10 characters are required.',
    'Création du compte impossible.': 'Could not create the account.',
    'Espace Chauffeur VTC': 'Driver space',
    'Dossier Chauffeur VTC': 'Driver file',
    'Complétez les informations professionnelles et le véhicule.': 'Complete your professional details and vehicle.',
    'Informations professionnelles': 'Professional details',
    'Raison sociale': 'Company name',
    'N° inscription registre VTC': 'VTC registry number',
    'N° carte professionnelle VTC': 'VTC professional card number',
    'Enregistrer les informations': 'Save the details',
    'Enregistrement…': 'Saving…',
    'Informations professionnelles enregistrées.': 'Professional details saved.',
    'Impossible d’enregistrer les informations professionnelles.': 'Could not save the professional details.',
    'Véhicule': 'Vehicle',
    'Catégorie': 'Category',
    'Marque': 'Brand',
    'Modèle': 'Model',
    'Année': 'Year',
    'Année du véhicule invalide.': 'Invalid vehicle year.',
    'Couleur': 'Color',
    'Immatriculation': 'License plate',
    'Documents obligatoires': 'Required documents',
    'Carte professionnelle VTC': 'VTC professional card',
    'Carte grise du véhicule': 'Vehicle registration',
    'Permis de conduire': 'Driving license',
    'Pièce d’identité': 'ID document',
    'PDF, JPG ou PNG — 10 Mo max': 'PDF, JPG, or PNG — 10 MB max',
    'Document envoyé. Il sera vérifié par Veyra.': 'Document sent. It will be reviewed by Veyra.',
    'Échec de l’envoi du document.': 'The document failed to send.',
    'Après envoi, l’équipe Veyra vérifie le dossier avant d’activer l’accès aux demandes.': 'Once submitted, the Veyra team reviews the file before enabling access to requests.',
    'Continuer vers mon dossier VTC': 'Continue to my VTC file',
    'Dossier approuvé': 'File approved',
    'Vérification en cours': 'Under review',
    'Statut KYC : ': 'KYC status: ',
    'Accéder aux demandes': 'Access requests',
    'Demandes disponibles': 'Available requests',
    'Aucune demande ouverte': 'No open requests',
    'Les nouvelles demandes apparaîtront ici.': 'New requests will appear here.',
    'Impossible de charger les demandes': 'Could not load requests',
    'Réessayer': 'Try again',
    'Filtres': 'Filters',
    'Trier les demandes': 'Sort requests',
    'Plus récentes': 'Most recent',
    'Lieu de départ (A → Z)': 'Pickup location (A → Z)',
    'Destination (A → Z)': 'Destination (A → Z)',
    'Minimum passagers': 'Minimum passengers',
    'Lieu de départ contient': 'Pickup location contains',
    'Destination contient': 'Destination contains',
    'Tous': 'All',
    'Appliquer': 'Apply',
    'Réinitialiser': 'Reset',
    'Demande indisponible': 'Request unavailable',
    'Elle a peut-être déjà été fermée.': 'It may have already closed.',
    'Départ': 'Pickup',
    'Date de départ': 'Departure date',
    'Offre privée': 'Private offer',
    'Aucun tri par proximité. Les chauffeurs ne voient jamais les prix concurrents.': 'No proximity ranking. Drivers never see competing prices.',
    'Les offres des autres chauffeurs et le meilleur prix ne sont jamais affichés.': 'Other drivers\' offers and the best price are never shown.',
    'Votre prix net (€)': 'Your net price (€)',
    'Saisissez un prix valide.': 'Enter a valid price.',
    'Proposer un prix': 'Propose a price',
    'Envoyer mon offre': 'Send my offer',
    'Envoi…': 'Sending…',
    'L’offre n’a pas pu être envoyée ou la demande est déjà fermée.': 'The offer could not be sent, or the request is already closed.',
    'Mes courses à venir': 'My upcoming rides',
    'Aucune course confirmée.': 'No confirmed rides.',
    'Course': 'Ride',
    'Client : ': 'Customer: ',
    'Statut : ': 'Status: ',
    'Je suis en route': 'I\'m on my way',
    'Je suis arrivé': 'I\'ve arrived',
    'La localisation est obligatoire pendant la prise en charge et la course.': 'Location sharing is required during pickup and the ride.',
    'Position GPS momentanément indisponible.': 'GPS position temporarily unavailable.',
    'PIN client (4 chiffres)': 'Customer PIN (4 digits)',
    'Le paiement doit être capturé avant le démarrage de la course.': 'Payment must be captured before the ride can start.',
    'Démarrer la course': 'Start the ride',
    'Terminer la course': 'End the ride',
    'Signaler un no-show': 'Report a no-show',
    'Appeler le client': 'Call the customer',
    'Chat Veyra': 'Veyra chat',
    'Votre message': 'Your message',
    'Aucun message pour le moment.': 'No messages yet.',
    'Annuler ma prise en charge': 'Cancel my pickup',
    'Annuler cette course ?': 'Cancel this ride?',
    'La réservation sera republiée en priorité si le délai le permet. Cette annulation impactera votre qualité chauffeur.': 'The booking will be republished with priority if time allows. This cancellation will affect your driver quality rating.',
    'Garder la course': 'Keep the ride',
    'Confirmer l’annulation': 'Confirm cancellation',
    'Course annulée et demande republiée.': 'Ride cancelled and request republished.',
    'Course annulée. Le support Veyra a été alerté.': 'Ride cancelled. Veyra support has been notified.',
    'Action impossible dans l’état actuel.': 'Action not possible in the current state.',
    'Annulation impossible dans l’état actuel.': 'Cancellation not possible in the current state.',
    'Noter le client': 'Rate the customer',
    'Merci pour votre avis !': 'Thanks for your feedback!',
    'Envoyer la note': 'Send rating',
    'Impossible d’envoyer la note pour le moment.': 'Could not send the rating right now.',
    'Portefeuille': 'Wallet',
    'À recevoir (ONLINE)': 'To receive (ONLINE)',
    'Paiement en ligne • Net chauffeur ': 'Online payment • Driver net ',
    'Facturation partenaire • Net chauffeur ': 'Partner invoicing • Driver net ',
    'Le partenaire est facturé par Veyra selon son contrat.': 'The partner is invoiced by Veyra according to their contract.',
    'Dette commission CASH': 'CASH commission debt',
    'C’est le montant exact que vous devez recevoir pour la course.': 'This is the exact amount you should receive for the ride.',
    'Montant à encaisser au client : ': 'Amount to collect from the customer: ',
    'Votre montant net : ': 'Your net amount: ',
    'Seuil de dette atteint': 'Debt threshold reached',
    'Alerte 50 € • restriction CASH 100 € • blocage CASH 150 €': 'Alert at €50 • CASH restricted at €100 • CASH blocked at €150',
    'Notifications': 'Notifications',
    'Aucune notification pour le moment.': 'No notifications yet.',
    'Notifications indisponibles.': 'Notifications unavailable.',
    'Activez la localisation du téléphone.': 'Turn on the phone\'s location.',
    '10 caractères minimum': '10 characters minimum',
  };
}
