# Plan de test MVP

Unitaires: JWT, state machine, stockage fichier, commission 10%/6%, calcul annulation, PIN crypto.

Intégration backend: register/login/refresh; KYC; publication H-2; offre privée; concurrence sur acceptation; snapshot financier; CASH debt thresholds; ONLINE idempotency; PARTNER_INVOICE credit; chat authorization; GPS sequence replay; PIN H-1/start; no-show H+15.

E2E Client: inscription → réservation → offres → choix → paiement → jour J → PIN → terminé → note.

E2E Chauffeur: KYC → opportunités → offre → confirmation → rappels → en route → arrivé → PIN → course → wallet.

E2E Partenaire: compte → bénéficiaire → réservation → offres → choix → invoice → facture.

Sécurité: IDOR, JWT expiré/falsifié, refresh replay, upload extension/path traversal, SQL injection, WebSocket CONNECT sans JWT, chat avant confirmation, accès cross-partner, brute-force login, secrets absents du repo.

Résilience: Redis indisponible, provider carte indisponible, push indisponible, paiement retry idempotent, reconnexion WebSocket/GPS.
