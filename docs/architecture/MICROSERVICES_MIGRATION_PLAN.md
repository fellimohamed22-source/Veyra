# Veyra — migration progressive vers des microservices

> Branche: `feature/client-ux-microservices-v4`, issue de `feature/product-marketplace-v3`.
> Statut: architecture cible et plan de migration. **Le backend actuel reste un monolithe** tant que les services ne sont pas extraits, déployés et testés.

## Invariants métier à préserver

- Réservations planifiées, départ >= 2 h à l'avance; validation serveur prioritaire.
- Les offres des chauffeurs sont privées selon la politique de visibilité de la réservation; le client sélectionne une offre encore valide.
- Les montants sont en unités mineures; la commission et le total proviennent du backend et des snapshots financiers.
- Le PIN est disponible selon les règles serveur, jamais calculé ni stocké en clair côté mobile.
- Annulation/no-show: montants calculés côté serveur, jamais codés en dur dans Flutter.
- Paiement Stripe: webhooks et idempotence font autorité.
- La position GPS n'est visible que pour les acteurs et phases autorisés.
- Les droits client/chauffeur/partenaire/admin restent strictement séparés.

## Architecture cible

```text
Flutter Client / Flutter Chauffeur / Angular
                    |
         API Gateway / BFF (auth, rate-limit, API versioning)
                    |
    +---------------+----------------+------------------+
    |               |                |                  |
Identity &      Booking          Marketplace        Payments
Profile         Service          & Offers           & Ledger
    |               |                |                  |
    +-------- asynchronous domain events / outbox ------+
                    |                |                  |
              Dispatch &        Notification        Tracking &
              Driver            Service             Geospatial
                    |
              Support / Reviews / Favorites (extraction progressive)
```

### Bounded contexts / ownership

| Service cible | Responsabilité | Tables actuelles à réattribuer progressivement |
|---|---|---|
| Identity/Profile | users, sessions, avatar, preferences | users, user_sessions, user_roles, password_reset_tokens |
| Booking | réservation, statut, modification, annulation, PIN | scheduled_bookings, booking_status_history, cancellation_* |
| Marketplace | offres, sélection, règles de visibilité | driver_offers, offer_visibility_policy_versions |
| Driver/Fleet | chauffeurs, KYC, véhicules, catégories | drivers, vehicles, driver_documents, vehicle_categories |
| Payment/Ledger | paiements, remboursements, commission, dettes, comptabilité | payments, refunds, booking_financial_snapshots, ledger_*, *_debts |
| Tracking/Geo | position chauffeur, routage, géocodage, zones | current_driver_locations, service_zones, service_zone_versions |
| Messaging/Notification | chat, push, modèles, outbox | chat_*, notifications, user_devices, outbox_events |
| Customer Experience | favoris, adresses enregistrées, historique récent | customer_saved_addresses, customer_favorite_drivers, nouvelles tables |
| Partner | organisations, bénéficiaires, facturation | partner_*, partner_invoices |

Ces frontières sont des cibles; éviter de déplacer les tables avant d'avoir défini les contrats et les transactions.

## Stratégie d'extraction: strangler pattern

1. **Baseline**: figer les contrats HTTP et tests d'intégration sur le monolithe, établir métriques et tracing.
2. **Gateway/BFF**: router les endpoints existants sans modifier les contrats mobiles.
3. **Extraire les lectures non transactionnelles**: notifications et géocodage/routage, avec isolation et tests.
4. **Extraire les services métier**: identité puis favoris/profil, tracking, chat.
5. **Extraire booking + marketplace** seulement avec conception de la saga d'acceptation d'offre, verrouillage optimiste et idempotence.
6. **Extraire paiements/ledger en dernier** avec réconciliation, webhooks Stripe, outbox/inbox, déduplication et audit.
7. **Séparer les bases par service** après migration de propriété; pas de jointures inter-services ni de transactions SQL distribuées.

## Exigences transverses

- Spring Boot / Java 21, PostgreSQL + PostGIS, Flyway par service.
- OpenAPI versionné, erreurs stables, correlation-id, JWT et autorisation fine par ressource.
- Outbox transactionnelle + consommateurs idempotents; retry/backoff et dead-letter.
- OpenTelemetry, métriques, logs structurés, health/readiness probes.
- Secrets hors dépôt, chiffrement, politique de rétention GPS/PII, RGPD.
- Contrats testés (consumer-driven), tests de concurrence, paiement, sécurité, rollback.
- Pas de `shared database` permanent; migration progressive avec anti-corruption layers.

## Risques de migration

- Offre acceptée deux fois => contraintes et atomicité dans Marketplace/Booking.
- Booking confirmé sans paiement => états explicites, compensation, webhook autoritaire.
- Notifications en double => event-id et déduplication.
- GPS stale => timestamp et qualité de position.
- Migration Flyway concurrente => ownership clair des schémas.
- Compatibilité Flutter => conserver `/api/v1` via gateway pendant la transition.

## Critères de fin de migration

Services réellement indépendants, bases isolées, API contractuellement compatibles, observabilité et CI/CD par service, tests de bout en bout, rollback vérifié, zéro double facturation et aucune régression des règles VTC.
