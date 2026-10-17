# VEYRA V4 — Index des maquettes (corrigé)

**Statut : PROPOSÉ — à valider (DEC-16).** L'index préliminaire livré avec le pack V4 ne correspond pas aux fichiers PNG fournis. Cet index décrit ce que montrent **réellement** les 17 planches, vérifiées à pleine résolution. Dimensions mesurées : 1536×1024, sauf MAQUETTE_03 et 04 en 1214×1295.

Les prix, noms, dates et pourcentages des planches sont **illustratifs**. Ils ne valent pas règle métier.

| PNG | Contenu réel (panneaux de gauche à droite, puis de haut en bas) | IDs d'écran |
|---|---|---|
| 01 | Assistant de réservation en 6 étapes : départ, destination, date/passagers/bagages, commentaire, récapitulatif, recherche d'offres | CL-02, 03, 05, 06, 08, 09 |
| 02 | Chauffeur en 5 écrans : accueil, demandes, détail, créer une offre, mes offres | DR-01 à DR-05 |
| 03 | Client en 8 écrans : accueil, offres, détail offre, confirmation avec frais, réservations, suivi, messages, profil | CL-01, 11, 12, 08/13, 16, 14, 15, 17 |
| 04 | Client, variante en 8 écrans : accueil, détails trajet, offres (prix le plus bas), confirmer, réservations, demande en cours, suivi, profil | CL-01, 03, 11, 12, 16, 10, 14, 17 |
| 05 | Client en 5 écrans : mes demandes, liste des offres, détail offre, confirmer et payer, réservation confirmée | CL-10, 11, 12, 07/08, 13 |
| 06 | Notifications client (4) + sélection avec chauffeur indisponible (3) | CL-18, CL-11 (états exceptionnels) |
| 07 | Paiement en 6 écrans (mode, récapitulatif, offres, détail, course terminée, variante cash) + schémas des parcours carte et cash | CL-07, 08, 11, 12, 16 ; DR-10 |
| 08 | Inscription : A client (6), B chauffeur indépendant (9), C chauffeur affilié (8) | CL-AUTH-01 à 06, DR-AUTH-01 à 09, DR-AFF-01 à 07 (8 panneaux pour 7 IDs) |
| 09 | Assistant en 7 étapes avec catégorie de véhicule, erreur de capacité, photos des catégories | CL-02 à CL-09, CL-04 |
| 10 | Confirmer et payer, réservation confirmée (contact désactivé), H-30 (message et appel actifs), course en cours | CL-12, 13, 15, 14 |
| 11 | Assistant en 7 étapes, variante « Van Confort » | comme 09 |
| 12 | Chauffeur complet en 11 écrans + catalogue de véhicules | DR-01 à DR-13 |
| 13 | Chauffeur en 5 écrans avec « Offre la plus basse » et des encadrés explicatifs | DR-01 à DR-05 |
| 14 | Offre chauffeur en 5 écrans : détail, créer (aperçu commission, validité), récapitulatif, envoyée, suivi | DR-03, 04, 05 |
| 15 | Client en 3 écrans : accueil, accueil avec prochain trajet, menu | CL-01, CL-17 |
| 16 | Notifications chauffeur en 3 écrans : badge, liste, détail | DR-14 |
| 17 | Assistant en 6 étapes (sans catégorie) | CL-02, 03, 05/06, 08, 09 |

**Sans maquette** (DEC-13) : PART-01 à 16, SOC-01 à 07, ADM-COM-01 à 04, ADM-01 à 04, soit 31 IDs sur 85.

## Écarts entre les maquettes et les règles métier (à arbitrer avant de coder les écrans)

1. **Trois conventions de commission** :
   - 48 € donne 52 € avec la mention « 8 % », alors que 4/48 = 8,33 % (planches 03, 05, 10) ;
   - 48 € donne 51,84 € TTC (planches 06, 14) ;
   - 48 € donne 48 € avec « frais 0 € » (planche 07).

   Le code applique la méthode A, avec 10 % en standard et 6 % pour les partenaires (DEC-01, DEC-02, DEC-17).
2. **Moment du paiement** : après la course (planche 07), à la sélection (planches 05, 10), ou capture exigée avant démarrage (code actuel). → DEC-04.
3. « Démarrer la course » depuis le détail, sans PIN ni position (planche 12, panneau 7). C'est contraire à DR-08.
4. Contre-offre, prix conseillé, validité d'offre au choix (planches 02, 12, 13, 14) : rien de tout cela n'est prévu. → DEC-18.
5. « Arrivée estimée 12 min » sur une offre de réservation programmée (planche 03).
6. Onglet Messages toujours accessible (planches 03, 04), alors que la règle est H-30 / H+1 (respectée sur la planche 10).
7. Logo Google sur les cartes, alors que V3 utilise flutter_map (DEC-08).
8. Consentement marketing coché par défaut à l'inscription (planche 08-A) : il doit être décoché. Mot de passe de 8 caractères dans la maquette, 10 côté serveur.
9. Données qui n'existent pas dans le modèle : « Client Premium », taux de trajets réalisés, avis textuels, équipements du véhicule.
