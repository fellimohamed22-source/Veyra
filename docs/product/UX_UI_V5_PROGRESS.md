# Veyra UX/UI V5 — état réel

## Périmètre

Branche `feature/client-ux-ui-v5` issue directement de `feature/product-marketplace-v3`. Aucun composant microservices ni gateway ajouté.

## Livré dans cette tranche

- Flyway V037 : historique de destinations récentes, clé utilisateur, unicité et index.
- API REST propriétaire `/api/v1/me/recent-destinations` (GET/POST/DELETE).
- Méthodes correspondantes dans `mobile-client/lib/api.dart`.
- Widget Flutter réutilisable `RecentDestinationsSection` : chargement, erreur, liste, sélection, suppression.
- Tests de widget Flutter écrits (non exécutés).

## Non livré / prochaines étapes

- Brancher le widget sur le formulaire de recherche existant et appeler l'API après confirmation explicite d'une destination.
- Ajouter un job de purge des destinations âgées de plus de 90 jours, et des tests d'isolation utilisateurs.
- Refonte visuelle complète du parcours réservation selon les maquettes : carte, choix du trajet, récapitulatif, offres, suivi, paiement.
- Rappels, calendrier, assistance, reçus.
- Exécuter Maven/Flyway et Flutter analyse/tests en CI avant merge.

Les modifications ne sont pas certifiées fonctionnelles tant que les tests d'intégration ne sont pas exécutés.
