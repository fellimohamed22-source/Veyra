# Architecture MVP

Monorepo:
- backend: Spring Boot API REST/WebSocket
- mobile-client: Flutter
- mobile-driver: Flutter
- web: Angular Partner/Admin/Finance/Support
- PostgreSQL/PostGIS: source de vérité
- Redis: prévu pour cache/realtime éphémère
- filesystem: documents MVP
- Mailpit local / SMTP production
- Outbox DB: événements métier

Frontends ne contiennent aucune règle financière autoritative. Le backend calcule commission, statut, éligibilité, PIN et autorisations.

Flux offre:
Booking OPEN_FOR_OFFERS → notification → chauffeur soumet prix privé → Client/Partenaire reçoit notification → compare toutes ses offres → sélection atomique → autres offres REJECTED_BY_SELECTION → snapshot financier → CONFIRMED.

Flux jour J:
CONFIRMED → DRIVER_EN_ROUTE (GPS live) → DRIVER_ARRIVED → PIN 4 chiffres → IN_PROGRESS → COMPLETED → dette CASH ou payable ONLINE/PARTNER_INVOICE.

Le PIN est hashé pour validation et chiffré AES-GCM pour restitution autorisée à H-1. La clé de chiffrement est externe au repo.
