# Veyra Client — traçabilité maquettes → code → données

Statuts: **EXISTE** = code + stockage identifiés; **PARTIEL** = fondation existante, UI/API à compléter; **NOUVEAU** = non identifié dans le périmètre audité. Une colonne SQL ne garantit pas qu'un endpoint la retourne.

| Écran / fonction | État | Flutter / API | Source SQL ou dérivation | Travail |
|---|---|---|---|---|
| Connexion / inscription | EXISTE | LoginScreen, RegisterScreen | users, user_sessions | Refonte UI |
| Mot de passe oublié / reset | EXISTE | ForgotPasswordScreen, ResetPasswordScreen | password_reset_tokens | Refonte UI |
| Compte / avatar | EXISTE | AccountScreen, api.updateProfile, uploadAvatar | users.first_name,last_name,email,phone,avatar_storage_key,locale,timezone | Refonte UI |
| Favoris adresses | EXISTE | favorites.dart, api.savedAddresses | customer_saved_addresses.label,address,lat,lng | Refonte UI |
| Chauffeurs favoris | EXISTE | favorites.dart, api.favoriteDrivers | customer_favorite_drivers | Refonte UI |
| Historique automatique de destinations | NOUVEAU | aucun endpoint dédié identifié | table à créer | Définir consentement/rétention, API, Flutter |
| Accueil et prochaine réservation | EXISTE | AccueilScreen, api.bookings | scheduled_bookings.scheduled_at,status,pickup_address,dropoff_address | Carte moderne |
| Recherche adresses | EXISTE | AddressScreen, api.autocomplete | fournisseur externe de géocodage | Recherche unifiée |
| Confirmation départ sur carte | PARTIEL | reverseGeocode et flutter_map présents | scheduled_bookings.pickup,pickup_address | Écran carte |
| Confirmation arrivée sur carte | PARTIEL | reverseGeocode et flutter_map présents | scheduled_bookings.dropoff,dropoff_address | Écran carte |
| Tracé / distance / durée estimée | PARTIEL | api.routeEstimate, GET /api/v1/routes/estimate | API distanceMeters,durationSeconds,points (non persistés) | Carte avant publication |
| Date / heure | EXISTE | AddressScreen | scheduled_bookings.scheduled_at | Calendrier UX |
| Catégorie / capacité | EXISTE | api.vehicleCategories | vehicle_categories.id,display_name,capacity | Illustrations, contrôle |
| Passagers / bagages | EXISTE | AddressScreen | scheduled_bookings.passenger_count,baggage_count | Stepper UX |
| Instructions | EXISTE | customerNotes | scheduled_bookings.customer_notes | Carte dédiée |
| Paiement cash / online | EXISTE | AddressScreen, PaymentScreen | scheduled_bookings.payment_method, payments | UX statuts |
| Demande publiée | EXISTE | api.createBooking | scheduled_bookings.status,offer_window_ends_at | Écran succès |
| Compteur fenêtre d'offres | PARTIEL | bookingDetail retourne offer_window_ends_at | scheduled_bookings.offer_window_ends_at | Compteur serveur, expiration |
| Offres / prix / note / véhicule | EXISTE | OffersScreen, api.offers | driver_offers, drivers.rating, vehicles | Cartes et tri client |
| Détail commission / total | EXISTE | BookingDetailScreen, financial widget | booking_financial_snapshots.driver_proposed_amount_minor,platform_commission_amount_minor,customer_total_amount_minor | Réutiliser snapshots |
| Acceptation offre | EXISTE | api.accept | scheduled_bookings.selected_offer_id,selected_driver_id | Écran confirmation |
| Modification demande | PARTIEL | api.updateBooking; préremplissage AddressScreen | scheduled_bookings + status_history | CTA conditionnel |
| Annulation avec prévisualisation | EXISTE | api.cancellationPreview, api.cancel | cancellation_charges, cancellation_policy_versions | Modal frais réels |
| PIN | EXISTE | api.pin, VeyraPinDisplay | scheduled_bookings.pin_hash,pin_encrypted | Carte et états H−1 |
| Chauffeur en route / GPS | EXISTE | LiveLocationScreen, api.currentLocation | current_driver_locations | Refonte carte |
| Chat | EXISTE | ChatScreen | chat_conversations,chat_messages | Refonte UI |
| Notation | EXISTE | api.rate(score, comment optionnel) | ride_ratings.score,comment | Formulaire note et commentaire après vérification API |
| Réserver à nouveau | EXISTE | BookingDetailScreen → AddressScreen | champs de scheduled_bookings | UX raccourci |
| Favori chauffeur préféré | PARTIEL | preferredDriverId transmis lors de certains flux | scheduled_bookings.preferred_driver_id | Vérifier sélection explicite et dispatch |
| Mes réservations / filtres | EXISTE | HomeScreen | scheduled_bookings.status,scheduled_at | Onglets + filtres |
| Notifications | EXISTE | NotificationsScreen + push | notifications, user_devices | États lus/non lus à valider |
| Timeline réservation | PARTIEL | GET /api/v1/scheduled-bookings/{id}/timeline | booking_status_history | Intégrer Flutter |
| Paiement réussi / échoué | PARTIEL | PaymentScreen, paymentStatusLabel | payments.status | États UX et reprise |
| Remboursements | PARTIEL | refunds SQL | refunds.status,amount_minor | Endpoint client autorisé à vérifier |
| Reçu téléchargeable | NOUVEAU | non identifié dans Flutter | payments, booking_financial_snapshots | Définir document fiscal, génération, autorisation |
| Assistance liée à un trajet | PARTIEL | éléments support backend à auditer | modèle ticket à vérifier | Contrat API client et UI |
| Ajout au calendrier | NOUVEAU | non identifié | données de scheduled_bookings (pas de nouvelle table requise) | Flutter calendrier |
| Rappels personnalisables | NOUVEAU | pas de préférences dédiées identifiées | migration éventuelle | API + opt-in + planification |
| Heure réelle / distance réelle | NOUVEAU / À AUDITER | timeline, GPS partiels | booking_status_history.created_at; pas de champ distance parcourue confirmé | Clarifier source et précision |
| États NO_OFFER/EXPIRED/DRIVER_CANCELLED/NO_SHOW/INCIDENT | PARTIEL | HomeScreen statuts; détails partiels | scheduled_bookings.status, booking_status_history | Écrans d'exception |
| Français / anglais | EXISTE | app_locale.dart, LanguageSwitch | users.locale | Vérifier tous libellés |

## Règles UX et données

1. Ne jamais montrer un prix avant une offre chauffeur; après sélection, utiliser le snapshot financier serveur.
2. Distinguer ETA **estimée** (routage) et temps réel **mesuré**; ne pas inventer d'heures réelles.
3. Aucun délai/frais Bolt ou Uber ne doit remplacer les règles Veyra.
4. Ne pas présenter une action si le backend ne l'autorise pas pour le statut et l'utilisateur.
5. Chaque écran a des états loading, vide, hors-ligne, erreur, expiré, permission refusée.
6. Les données chauffeur, téléphone, chat, PIN et GPS sont visibles seulement aux personnes autorisées.
7. Les visuels précédents sont des **maquettes conceptuelles**, non une preuve de fonctionnalité implémentée.

## Backlog d'exécution

**P0**: tests de non-régression du monolithe; cartes de départ/arrivée et route; récapitulatif; offres; statut et annulation; PIN; contrat gateway.

**P1**: modification guidée; écrans états exceptionnels; paiement et remboursements; timeline; ajout calendrier; historique destinations (rétention et confidentialité).

**P2**: rappels paramétrables; assistance liée au trajet; reçu; temps réel et historique GPS avec règles RGPD.

Aucune migration SQL ne doit être ajoutée avant validation du contrat API, des exigences de rétention et du propriétaire de la donnée dans le service cible.
