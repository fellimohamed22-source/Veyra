# Veyra MVP

Marketplace de réservations VTC programmées pour Clients, Chauffeurs et Partenaires, avec Admin/Support/Finance.

## Règles gelées
- Pas de course immédiate.
- Auth: Email + mot de passe + JWT.
- Offres privées: le chauffeur ne voit jamais les offres concurrentes.
- Client/Partenaire voit toutes les offres et choisit librement.
- CASH / ONLINE / PARTNER_INVOICE.
- Commission standard 10%, partenaire 6%, configurables.
- PIN 4 chiffres obligatoire avant démarrage.
- Chat Veyra + appel après confirmation.
- Documents KYC sur filesystem backend au MVP.
- GPS live le jour J uniquement.
- Zone pilote configurable Marseille → Menton.

## Local
```bash
docker compose up -d
cd backend && mvn spring-boot:run
```
