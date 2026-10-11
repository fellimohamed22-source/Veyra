# Revue architecte — Veyra v4

Date: 2026-10-11. Périmètre: fichiers inspectés dans `feature/client-ux-microservices-v4`. Revue statique uniquement.

## Verdict

**NO-GO production.** Les configurations de gateway et les API de destinations récentes ont été committées, mais aucune preuve de build, démarrage, migration Flyway ou test bout en bout n'est disponible. Aucun microservice Java autonome n'est extrait.

## Constatations par sévérité

| Sévérité | Constat | Correctif / vérification |
|---|---|---|
| CRITIQUE | Backend toujours monolithique derrière Nginx | Ne pas annoncer la migration comme terminée; définir et extraire un premier service indépendant |
| HAUTE | Aucun build Maven, Flutter ou Docker validé dans cette session | Exécuter CI et tests de régression, puis environnement de staging |
| HAUTE | Gateway HTTP uniquement, sans TLS, limitation de débit ni politique réseau production | Terminaison TLS, restrictions admin, limites et observabilité avant déploiement |
| HAUTE | Nginx envoyait `Connection: upgrade` sur toutes les requêtes | Corrigé dans cette branche via `map $http_upgrade $connection_upgrade`; valider HTTP et WebSocket |
| MOYENNE | La nouvelle API des destinations est ajoutée au client, mais aucun écran ne l'appelle | Connecter le parcours recherche, loading/empty/error, suppression et opt-in |
| MOYENNE | Conservation 90 jours appliquée à la lecture et lors de nouvelles écritures; pas de purge globale | Ajouter job de purge si effacement physique à 90 jours est requis |
| MOYENNE | Aucune contrainte d'unicité DB sur adresse + coordonnées | Le verrou applicatif par utilisateur réduit les doublons; documenter la normalisation et ajouter test concurrent |
| MOYENNE | `depends_on` Docker ne garantit pas la disponibilité PostgreSQL/Flyway | Healthchecks et retry readiness à tester |
| MOYENNE | Migration SQL V037 dépend de l'ordre et du contenu des migrations précédentes | Exécuter Flyway sur base vide et base migrée; tester rollback |
| MOYENNE | Contrats d'API / schémas de données inter-services non stabilisés | Versionner OpenAPI et événements avant extraction Booking/Payment |

## Vérifications de code effectuées

- `CustomerRecentDestinationsController`: toutes les opérations utilisent `CurrentUser.id()` et filtrent par `user_id`; validations latitude/longitude et longueur adresse présentes.
- `V037__customer_recent_destinations.sql`: FK `users(id)`, index sur user/date, bornes GPS; ne modifie pas les tables historiques.
- `mobile-client/lib/api.dart`: méthodes `recentDestinations`, `recordRecentDestination`, `deleteRecentDestination`, `clearRecentDestinations` ajoutées.
- `SecurityConfig`: routes hors auth/webhook/health exigent authentification; les nouvelles routes restent protégées.
- `nginx.conf`: la configuration reste une gateway de compatibilité, non un découpage microservices.

## Plan de validation obligatoire

1. `docker compose -f docker-compose.yml -f infrastructure/docker-compose.microservices.yml config`
2. `nginx -t -c /path/to/nginx.conf` (sur configuration matérialisée) et tests GET, POST, WebSocket.
3. `cd backend && mvn -B verify`, Flyway sur PostgreSQL/PostGIS frais puis base migrée.
4. `cd mobile-client && flutter analyze && flutter test`.
5. Tests HTTP authentifié: liste vide, POST valide, validation 400, isolation client A/B, suppression, concurrence, 20 entrées, 90 jours.
6. Tests de non-régression réservation/offres/acceptation/PIN/annulation/Stripe; validation des webhooks.
7. Scan sécurité et test d'accès admin via gateway; TLS en staging.
8. Feu vert uniquement après rapports de CI et tests de staging.

## Décision

Conserver la branche de travail. Ne pas merger sur la branche de référence ni déployer en production tant que les contrôles ci-dessus ne sont pas verts.
