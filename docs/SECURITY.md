# Sécurité MVP

- JWT HMAC secret >= 32 bytes, différent par environnement.
- Access token 15 min, refresh token opaque hashé, rotation.
- BCrypt cost 12.
- RBAC backend; ne jamais faire confiance au rôle envoyé par le frontend.
- Autorisation objet sur Booking/Partner/Driver/Chat.
- Offre concurrente jamais exposée à un chauffeur.
- PIN hashé + chiffré; jamais dans logs.
- Documents non publics, UUID storage key, extension whitelist, limite 10 MB.
- Paramètres SQL: JdbcTemplate placeholders; les seuls ORDER BY dynamiques sont whitelistés.
- Idempotency-Key obligatoire pour paiement.
- WebSocket STOMP: JWT Bearer obligatoire au CONNECT et autorisation par réservation sur les topics chat/location.
- HTTPS obligatoire hors localhost.
- Secrets uniquement via variables d'environnement.
- Les actions privilégiées Admin et Finance sont tracées dans audit_logs.
