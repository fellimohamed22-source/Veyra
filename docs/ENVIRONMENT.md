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

## Garde-fous de sécurité (V4 L0-SEC)

- Le backend **refuse de démarrer** si `JWT_SECRET` ou `PIN_ENCRYPTION_KEY`
  valent les valeurs par défaut publiques d'`application.yml`, ou si les deux
  secrets sont identiques. En développement local uniquement :
  `VEYRA_ALLOW_DEV_SECRETS=true`.
- `FIREBASE_PROJECT_ID` (défaut `veyra-4806a`) : seuls les ID tokens Firebase
  émis pour ce projet sont acceptés par `POST /api/v1/auth/firebase`.
- `VEYRA_TEST_ACCOUNTS_ENABLED` (défaut `true`) : mettre `false` en production
  pour suspendre les comptes de test des migrations V029/V030/V034 (mots de
  passe publics) et révoquer leurs sessions au démarrage.
