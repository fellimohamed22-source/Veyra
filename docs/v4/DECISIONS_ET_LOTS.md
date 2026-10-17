# VEYRA V4 — Lots livrés et décisions ouvertes

## Lots livrés (branche `product-marketplace-v4`)

| Lot | Contenu | Migrations | Tests |
|---|---|---|---|
| L0-SEC | Connexion Firebase limitée au projet VEYRA (`FIREBASE_PROJECT_ID`) ; liaison de compte seulement si l'email est vérifié par Firebase, ou si le téléphone est vérifié par SMS ; compte suspendu refusé (Firebase et refresh) ; refus de démarrer avec les secrets de développement ; suspension optionnelle des comptes de test (`VEYRA_TEST_ACCOUNTS_ENABLED=false`) | V037 `users.firebase_uid` | AUTH-01, AUTH-02, SecretsGuard |
| L2 | Commission **figée sur chaque offre** à la soumission ; le client confirme le prix affiché, même si le taux a changé entre-temps (COM-03). Formule V3 inchangée | V038 (+ rattrapage des offres existantes) | COM-03, repli pour les anciennes offres |
| L3 | Une offre exige un véhicule APPROUVÉ de la bonne catégorie (soumission et révision) ; un chauffeur suspendu ne peut plus réviser ; la liste ne montre que les demandes compatibles ; badge « Client préféré » basé sur la relation réelle ; capacité bagages par catégorie (non contrôlée tant qu'elle n'est pas renseignée) | V039 `vehicle_categories.baggage_capacity` | BOOK-03, DR-02, bagages |
| L5 | Validation des données à la création d'organisation et de bénéficiaire ; factures et finance partenaire réservées aux rôles propriétaire et comptabilité | — | Accès réceptionniste refusé |

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
