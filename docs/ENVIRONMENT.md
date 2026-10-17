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

## Consentements (V4 L4)

- `VEYRA_TERMS_VERSION`, `VEYRA_PRIVACY_VERSION`, `VEYRA_MARKETING_VERSION`
  (défaut `PENDING_LEGAL_REVIEW`) : version des textes enregistrée avec chaque
  consentement (`user_consents`). À renseigner avec la version validée
  juridiquement (DEC-14).

## Rotation de JWT_SECRET et PIN_ENCRYPTION_KEY

Si Render définit déjà ces deux variables, rien à faire : elles sont
conservées et acceptées par le garde-fou.

Si elles n'étaient pas définies (la production utilisait alors les valeurs
par défaut publiques d'`application.yml`) :

1. `JWT_SECRET` : définir une nouvelle valeur aléatoire (≥ 32 octets). Effet :
   les access tokens en cours (15 min) deviennent invalides, les apps se
   reconnectent automatiquement via leur refresh token (stocké en base).
2. `PIN_ENCRYPTION_KEY` : définir une nouvelle valeur aléatoire, **et**
   `PIN_ENCRYPTION_KEY_PREVIOUS=dev-pin-key-must-be-32-bytes-long` (l'ancienne
   valeur) pour que les PIN des réservations déjà confirmées restent
   affichables. Les nouveaux PIN sont chiffrés avec la nouvelle clé.
3. Une fois les réservations confirmées avant la rotation terminées, supprimer
   `PIN_ENCRYPTION_KEY_PREVIOUS`.

Génération (exemple) : `openssl rand -base64 48`.
