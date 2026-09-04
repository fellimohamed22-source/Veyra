# Variables d'environnement

Obligatoires en production:
- DB_URL, DB_USER, DB_PASSWORD
- JWT_SECRET (>= 32 octets aléatoires)
- PIN_ENCRYPTION_KEY (secret séparé, rotation contrôlée)
- VEYRA_DOCUMENT_ROOT
- SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD

À fournir quand les adapters production seront activés:
- PSP API key + webhook secret
- Firebase service account / fichiers mobile
- SMS provider credentials si fallback SMS
- éventuelle clé maps/geocoding/routing si remplacement d'OSM/OSRM

Ne jamais réutiliser les valeurs dev en production.
