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
| L13a | **Google Maps côté serveur** (DEC-08) : Places (recherche d'adresse), Geocoding (adresse d'un point), Routes (distance, durée, tracé) dès que `GOOGLE_MAPS_API_KEY` est défini ; sinon OSM actuel inchangé. Cartes Flutter : en attente de la clé (lot L13b) | — | Lecture des réponses Google, décodage polyline, repli sans clé |

### Refonte UI écran par écran (planches 01 à 17, DEC-12)

| Lot | Contenu | Migrations |
|---|---|---|
| UI-1 | Système de design (couleurs relevées sur les maquettes, police Plus Jakarta Sans), parcours de réservation client en 7 étapes (planches 01/09/11/17) | — |
| UI-2 | Client : Accueil, Mes demandes, Mes réservations, Profil (planches 05/15/03/04) | — |
| UI-3 | Client : offres, détail d'offre, confirmation, « Ma réservation » (planches 05/10) ; numéros de téléphone retirés des API (CL-15) | — |
| UI-4 | Client : bienvenue, inscription en 3 étapes, vérification SMS, compte créé (planche 08 A) ; emplacements photo d'accueil (pack TOTAL) | — |
| UI-5 | Chauffeur : inscription indépendant en 7 étapes, recto/verso, dossier repris là où il s'est arrêté, envoi explicite du dossier (planche 08 B) | V047 |
| UI-6 | Chauffeur : accueil, bouton « Disponible », demandes disponibles avec « Offre la plus basse » (planches 02/12/13) | V048 |
| UI-7 | Chauffeur : détail de la demande, créer une offre → récapitulatif → offre envoyée, véhicule et message joints à l'offre (planche 14) | V049 |
| UI-8 | Chauffeur : Mes offres, Mes courses, Revenus du mois, Profil, Mes véhicules ; notifications lu/non lu dans les deux apps (planche 16, CL-18) | V050 |
| UI-9 | Chauffeur : détail de course et course en cours (planche 12 P7/P8) ; détail de notification ; statut du compte | — |
| UI-11 | Portail partenaire et portail admin (Vérifications, Réservations, Commissions avec simulation, Paramètres, Partenaires) selon les maquettes validées DEC-13 | — |
| L15 | **Sociétés VTC et chauffeurs affiliés** (SOC-01..10, DR-AFF-01..07) : société (SIREN contrôlé), documents d'exploitation et de véhicule, flotte, code d'invitation et invitations e-mail, validation du rattachement et attribution de véhicule, échéances, activité du mois ; revue VEYRA de la société et de chaque véhicule. Un véhicule de flotte ne porte d'offres que si la société est approuvée et ses pièces valides ; un document chauffeur expiré bloque les nouvelles offres. Portail web /societe, inscription professionnelle web, parcours chauffeur affilié (planche 08 C) | V053 | Base PostgreSQL (création, code, rattachement, règles de flotte, échéances), parcours affilié complet |
| UI-10 | Tous les écrans à 320 px avec texte agrandi ×1,5 (tests automatiques), montants « 1 250,00 € » | — |

Rollback : chaque migration documente son `DROP` dans son en-tête.

## Actions d'exploitation requises (hors code)

- Sur Render, définir `JWT_SECRET` et `PIN_ENCRYPTION_KEY` (aléatoires, distincts). **Sans eux, le backend refuse désormais de démarrer.**
- Changer ces secrets s'ils ont déjà valu les valeurs par défaut du dépôt.
- Comptes de test : maintenus pour l'instant (DEC-19, 20/10/2026).
- Restreindre les clés API Firebase Android (nom du package et SHA) dans la console GCP.
- Décider de la visibilité du dépôt (actuellement public).
- Sur Render, définir `STRIPE_PUBLISHABLE_KEY` (clé publique `pk_…`, même compte que `STRIPE_SECRET_KEY`) : sans elle, le paiement par carte du portail web et du lien passager reste désactivé.

## Décisions ouvertes (propriétaire produit)

- DEC-01 à DEC-15 : voir le registre du pack V4 (méthode de commission A/B, barème, paiement anticipé, partenaire avant approbation, appels masqués, SMS, cartographie, délais et annulation, seuil GPS et PIN, meilleure offre, design tokens, maquettes manquantes, conformité, rôles partenaires).
- **DEC-16** : valider l'index des maquettes corrigé.
- **DEC-17** : convention de commission affichée (3 variantes dans les maquettes).
- **DEC-18** : prix conseillé, contre-offre, validité d'offre au choix.
- **DEC-21** : capacités bagages par catégorie (valeurs à fournir).

## Lots non démarrés (bloqués) — mise à jour du 19/10/2026

Livrés depuis : moteur de commission (L6), contrôle GPS (L8), Stripe (L10), OTP SMS (L11), refonte UI (UI-1 à UI-10).

| Lot bloqué | Ce qui manque |
|---|---|
| Portails partenaire, société VTC et admin | Livrés (DEC-13 validée le 19/10) |
| Appels masqués (bouton « Appeler » désactivé dans les deux apps) | Identifiants Twilio Proxy (DEC-06) |
| SMS du lien de suivi passager | Identifiants Twilio, `VEYRA_GUEST_BASE_URL` |
| Photos d'accueil client et chauffeur, logo vectoriel | Originaux sans texte ni interface, droits (voir l'audit des images ci-dessous) |
| « Lire les documents » à l'inscription, charte chauffeur | Textes juridiques |
| Connexion Apple (iOS) | Décidée le 20/10 : à activer dans Firebase (fournisseur Apple) et sur le compte Apple Developer |
| Cartes Google dans les apps (L13b) | Clé Google Maps pour mobile |

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
| DEC-13 (19/10) | Maquettes des portails partenaire, société VTC et admin **validées** (navigation, réservation partenaire en 5 étapes avec choix du payeur, offres comme côté client, écrans Commissions et Paramètres) |
| DEC-15 (20/10) | Rôles partenaires conservés : propriétaire (tout), réception (réserver, choisir le chauffeur), comptabilité (factures) |
| DEC-19 (20/10) | Comptes de test maintenus pour l'instant |
| Pièces sociétés VTC (20/10) | Liste proposée retenue : Kbis, attestation REVTC, assurance RC pro ; carte grise, assurance RC circulation, contrôle technique par véhicule ; justificatif de domicile facultatif pour l'affilié |
| Expiration (20/10) | Pour tous les chauffeurs : pas d'offre si la carte VTC expire avant le jour de la course ; un document expiré bloque toutes les offres |
| Apple (20/10) | Connexion Apple ajoutée |
| Client visible du chauffeur (19/10) | **Oui** : prénom + initiale du nom (« Sophie M. ») et note moyenne donnée par les chauffeurs ; nom du passager pour une réservation partenaire ; jamais le nom complet ni le téléphone |
| Comptes (22/10) | Une même adresse e-mail peut porter un compte client et un compte chauffeur ; chaque app refuse le compte de l'autre type (V058) |
| Zone (22/10) | Restriction « Sud de la France » suspendue pour la création de demande (V056), réactivable |
| Factures (22/10) | **Facture de course** par course terminée, émise par VEYRA au nom et pour le compte du chauffeur (ou de sa société VTC) — mandat de facturation —, montant total payé par le client ; TVA 10 % si l'émetteur est assujetti, sinon mention art. 293 B (statut déclaré par le chauffeur dans « Mes factures » ou par la société sur le portail). **Facture de commission** VEYRA mensuelle par chauffeur, mois clos. Émission au premier téléchargement puis figée (V059). Variables Render : `VEYRA_INVOICE_ISSUER_NAME`, `VEYRA_INVOICE_ISSUER_LEGAL_FORM`, `VEYRA_INVOICE_ISSUER_SIREN`, `VEYRA_INVOICE_ISSUER_ADDRESS`, `VEYRA_INVOICE_ISSUER_VAT_NUMBER`, `VEYRA_COMMISSION_VAT_BPS` (défaut 2000 = commission TTC à 20 %, **à confirmer**) |
| Envoi des factures (23/10) | La facture de course est envoyée par e-mail au client (PDF joint) après la course, par une tâche périodique (5 min) : réessais espacés tant qu'elle ne peut pas être émise (statut TVA manquant) ou si le SMTP échoue ; seules les courses terminées depuis moins de 24 h sont envoyées. Expéditeur : `VEYRA_MAIL_FROM` (sinon le compte SMTP) |
| Cartes (23/10) | Toutes les cartes des apps utilisent le **SDK natif Google Maps** (moteur d'Uber et Bolt) : rendu Google, gestes fluides, voiture animée orientée, suivi caméra. Repli flutter_map/OSM seulement sans clé (tests). Clé : secret GitHub `GOOGLE_MAPS_MOBILE_KEY`, injectée au build dans le manifeste Android et l'AppDelegate iOS. Côté Google Cloud (projet 383065284362) : compte de facturation lié ; API **Maps SDK for Android** et **Maps SDK for iOS** activées ; restriction de la clé (une seule clé pour Android et iOS) : « Aucune » restriction d'application et restriction **par API** limitée à Maps SDK for Android, Maps SDK for iOS (et Map Tiles API pour le fond de secours). Pour verrouiller davantage plus tard : deux clés distinctes, l'une restreinte aux applications Android `com.veyra.client` / `com.veyra.driver` avec l'empreinte SHA-1 `AF:F0:50:9C:B2:B7:92:56:F5:BA:BB:8D:26:3B:DD:8E:21:15:44:9A` (keystore de debug du dépôt), l'autre aux applications iOS de mêmes identifiants |

## Audit des images du pack « TOTAL » (18/10/2026)

Hiérarchie appliquée : maquette A/B/C du propriétaire (identique à la planche 08) > 17 planches ; la planche `04_PROPOSITIONS_NON_VALIDEES` (emblème V doré, splash, icône) n'est **pas** utilisée. Palette des écrans d'inscription : bleu nuit `#021C38`, blanc, bleu vif de progression `#0C6CFD`, bleu clair de sélection `#E8F0FE` (tokens `VeyraColors`). Logo d'interface : mot-symbole VEYRA bleu nuit (texte, police Plus Jakarta Sans).

| Écran | Référence | Asset fourni | Résolution native | Destination | Cadrage | Qualité | Statut |
|---|---|---|---|---|---|---|---|
| Client A1 Bienvenue | 08 A1 | `login_client_paris.png` | 232 × 156 | `mobile-client/assets/images/onboarding/welcome_client.jpg` | portrait 9:16, tour Eiffel à droite, ciel en haut | **inutilisable** : barre d'état « 9:41 », logo, slogan et pilules de langue incrustés ; ~5× trop petit | original requis |
| Chauffeur B1 Bienvenue | 08 B1 | `login_chauffeur_paris.png` | 155 × 145 | `mobile-driver/assets/images/onboarding/welcome_driver.jpg` | portrait 9:16, chauffeur à droite, bas sombre | **inutilisable** : barre d'état, logo, « Rejoignez VEYRA / Drive with VEYRA » incrustés | original requis |
| Logos | 08 A1/B1 | `logo_veyra_bleu.png`, `logo_veyra_chauffeur.png` | 90 × 30, 64 × 22 | — | — | trop petits, fond non transparent | mot-symbole rendu en texte ; SVG original souhaité |
| Véhicules (offres, réservation) | 05, 10 | `voiture_berline_noire.png` | 127 × 60 | — | — | fond blanc avec bandeau d'UI, marque visible | **non utilisé** : ne pas présenter un visuel générique comme le véhicule du chauffeur |
| Choix de catégorie (parcours de réservation) | 09 | `voiture_*` | ≤ 138 px | — | — | une seule berline pour toutes les catégories | non utilisé (catégorie et angle non respectés) |

Intégration livrée : emplacement photo prêt dans les deux apps (`VeyraWelcomeHero`, chemins centralisés `VeyraAssets`, `BoxFit.cover` + point focal, texte bleu nuit sur photo comme la maquette, fond marine tant que la photo manque, aucune substitution silencieuse). Déposer les originaux aux chemins ci-dessus suffit ; exigences dans `assets/images/onboarding/README.md`.

À fournir par le propriétaire : photos originales 1080 × 1920 min. sans texte ni UI (client, chauffeur), droits commerciaux (photo, modèles, marque Mercedes visible), logo vectoriel, master d'icône 1024 × 1024 si une nouvelle icône est souhaitée, et décision sur le bouton « Continuer avec Apple » (non implémenté).
