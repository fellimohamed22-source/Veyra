# VEYRA V4 — Lots livrés et décisions ouvertes

## Lots livrés (branche `product-marketplace-v4`)

| Lot | Contenu | Migrations | Tests |
|---|---|---|---|
| L0-SEC | Connexion Firebase limitée au projet VEYRA (`FIREBASE_PROJECT_ID`) ; liaison de compte seulement si l'email est vérifié par Firebase, ou si le téléphone est vérifié par SMS ; compte suspendu refusé (Firebase et refresh) ; refus de démarrer avec les secrets de développement ; suspension optionnelle des comptes de test (`VEYRA_TEST_ACCOUNTS_ENABLED=false`) | V037 `users.firebase_uid` | AUTH-01, AUTH-02, SecretsGuard |
| L2 | Commission **figée sur chaque offre** à la soumission ; le client confirme le prix affiché, même si le taux a changé entre-temps (COM-03). Formule V3 inchangée | V038 (+ rattrapage des offres existantes) | COM-03, repli pour les anciennes offres |
| L3 | Une offre exige un véhicule APPROUVÉ de la bonne catégorie (soumission et révision) ; un chauffeur suspendu ne peut plus réviser ; la liste ne montre que les demandes compatibles ; badge « Client préféré » basé sur la relation réelle ; capacité bagages par catégorie (non contrôlée tant qu'elle n'est pas renseignée) | V039 `vehicle_categories.baggage_capacity` | BOOK-03, DR-02, bagages |
| L5 | Validation des données à la création d'organisation et de bénéficiaire ; factures et finance partenaire réservées aux rôles propriétaire et comptabilité | — | Accès réceptionniste refusé |
| L7 | Messagerie ouverte de H-30 min avant la prise en charge à H+1 h après la fin (CL-15), contrôlée côté serveur ; historique toujours lisible ; support et admin non limités ; `GET /bookings/{id}/chat/availability` | — | CHAT-01, dérogation support |
| L4 | Consentements à l'inscription : CGU et confidentialité obligatoires, marketing facultatif et non coché, journal append-only avec version des textes ; `GET/POST /me/consents` | V040 `user_consents` | CONSENT_REQUIRED, widget Flutter |
| — | Test sur vraie base : le paiement capturé du jeu de données porte maintenant son PSP (`backend-ci` était déjà rouge sur `b1e3c95`) | — | 41 tests sur PostgreSQL et PostGIS |
| L6 | **Moteur de commission V4** (DEC-01 A, DEC-02, DEC-03) : règles en base par portée USER > PARTNER > PARTNER_CATEGORY > PROFILE > STANDARD, pourcentage + fixe + plancher/plafond, dates d'effet, versions immuables ; API admin `/admin/commission-rules` (liste, création avec contrôle de conflit, désactivation, **simulation**), audit avant/après + justification ; aperçu du prix client pour le chauffeur (`GET /driver/opportunities/{id}/quote`) ; suppression des 600 bps en dur | V041 (barème initial : STANDARD 10 %, PROFILE PARTNER 6 %) | COM-01..04, arrondi, fixe, bornes, priorité vérifiée sur PostgreSQL |
| L8 | **Contrôle GPS** (DEC-10) : « Arrivé » et « Démarrer » refusés à plus de `ride.pickup_radius_meters` (200 m) du point de prise en charge, avant toute tentative de PIN ; position envoyée par l'app, sinon dernière position suivie récente ; **paramètres plateforme en base** (DEC-09) : délai minimum 120 min, fenêtre d'offres, rayon, âge max de position ; API `/admin/settings` auditée | V042 `platform_settings` | RIDE-01, 41 tests sur PostGIS |
| L10 | **Carte enregistrée, débit à la réservation** (DEC-04) : un client Stripe par utilisateur, paiement avec `setup_future_usage` (la carte saisie est enregistrée), clé éphémère transmise à la feuille de paiement (cartes enregistrées proposées), `GET/DELETE /payments/methods`, écran « Mes moyens de paiement » ; aucune donnée de carte stockée chez VEYRA | V043 `payment_customers` | Cartes : création unique du client, réutilisation, suppression limitée au propriétaire |
| L14 | **Prix conseillé** (DEC-18) : grille en base par catégorie (prise en charge, €/km, €/min, minimum, fourchette ± %), en prix net chauffeur, **vide par défaut** ; `GET /driver/opportunities/{id}/suggested-price` (itinéraire OSRM) ; `GET/PUT /admin/suggested-price-grid` audité ; indication « Prix conseillé (net) » dans l'app chauffeur. Pas de contre-offre, validité liée à la fenêtre d'offres | V044 `suggested_price_grid` | Calcul, arrondi, grille absente, itinéraire indisponible |
| L11 | **Vérification du téléphone par OTP** (DEC-07, CL-AUTH-05) : Firebase Phone Auth dans l'app client après l'inscription (écran « Vérifiez votre numéro »), `POST /me/phone/verify` n'accepte qu'un jeton Firebase du projet VEYRA émis par connexion SMS ; un numéro vérifié n'appartient qu'à un compte. **Prérequis console Firebase** : activer le fournisseur « Téléphone » et déclarer les empreintes SHA de l'app Android | V045 `users.phone_verified_at` | Preuve SMS exigée, numéro déjà utilisé, normalisation E.164 |
| L12 | **Lien de suivi passager et SMS** (PART-13, PART-03, DEC-07) : lien à jeton aléatoire (seul le hash est stocké), expiration et révocation, un lien actif par réservation ; vue publique minimale sans téléphone ni prix, 404 identique pour lien inconnu/expiré/révoqué, `noindex`, limitation par IP sur tous les jetons ; envoi SMS via Twilio (inactif sans identifiants) ; page web publique `/suivi/:jeton` | V046 `guest_access_links` | PART-03, isolation inter-organisations, normalisation E.164 |

Rollback : chaque migration documente son `DROP` dans son en-tête.

## Actions d'exploitation requises (hors code)

- Sur Render, définir `JWT_SECRET` et `PIN_ENCRYPTION_KEY` (aléatoires, distincts). **Sans eux, le backend refuse désormais de démarrer.**
- Changer ces secrets s'ils ont déjà valu les valeurs par défaut du dépôt.
- Décider pour `VEYRA_TEST_ACCOUNTS_ENABLED` (DEC-19).
- Restreindre les clés API Firebase Android (nom du package et SHA) dans la console GCP.
- Décider de la visibilité du dépôt (actuellement public).

## Décisions ouvertes (propriétaire produit)

- DEC-01 à DEC-15 : voir le registre du pack V4 (méthode de commission A/B, barème, paiement anticipé, partenaire avant approbation, appels masqués, SMS, cartographie, délais et annulation, seuil GPS et PIN, meilleure offre, design tokens, maquettes manquantes, conformité, rôles partenaires).
- **DEC-16** : valider l'index des maquettes corrigé.
- **DEC-17** : convention de commission affichée (3 variantes dans les maquettes).
- **DEC-18** : prix conseillé, contre-offre, validité d'offre au choix.
- **DEC-19** : suspendre les comptes de test en production ?
- **DEC-21** : capacités bagages par catégorie (valeurs à fournir).

## Lots non démarrés (bloqués par une décision)

Moteur de commission V4 avec portées client, catégorie et profil, et simulation admin (DEC-01 à 03) · contrôle GPS à l'arrivée et au démarrage (DEC-10) · flux Stripe définitif (DEC-04) · OTP SMS et appels masqués (DEC-06, 07) · connexion Apple et refonte UI écran par écran (DEC-12) · portails partenaire, société VTC et admin (DEC-13, 15).

## Décisions prises (17/10/2026)

| Décision | Réponse |
|---|---|
| DEC-01 / 17 | Méthode **A** : prix client = prix net chauffeur + commission |
| DEC-02 | Barème en base (initial : 10 % standard, 6 % partenaires) |
| DEC-03 | Fixe / plancher / plafond configurables en base |
| DEC-04 | Carte enregistrée et **débit à la réservation** (confirmation de l'offre) |
| DEC-06 | Twilio Proxy, France au départ |
| DEC-07 | Firebase Phone Auth (OTP) ; Twilio pour les SMS passager |
| DEC-08 | Passage à **Google Maps** |
| DEC-09 | Délai minimum 120 min, configurable en base ; politique d'annulation V3 conservée |
| DEC-10 | Démarrage : **200 m** du point de prise en charge + PIN 4 chiffres, 5 essais |
| DEC-12 | Couleurs relevées sur les maquettes, à valider |
| DEC-13 | Écrans partenaire / société / admin conçus dans le style des maquettes, validés avant code |
| DEC-16 | Index corrigé des maquettes **validé** |
| DEC-18 | Pas de contre-offre ; prix conseillé via une grille en base (fournie par le propriétaire) ; validité liée à la fenêtre d'offres |
| DEC-21 | Capacité bagages non fixée pour l'instant (évolution ultérieure) |
