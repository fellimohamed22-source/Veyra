# Configuration à faire (propriétaire)

Liste des réglages hors code que l'application attend. **Aucune valeur secrète ici** : uniquement les noms et où les saisir. À cocher au fur et à mesure.

Légende : **Manquant** = l'application signale son absence ou la fonction est inactive ; **À vérifier** = probablement déjà saisi, à contrôler.

## 1. Render (service `veyra-wr6p`, branche `product-marketplace-v4`) — Environment

| Variable | Statut | Rôle / effet si absent |
|---|---|---|
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD` | Manquant | E-mails (facture envoyée au client, mot de passe oublié, invitations). Sans eux, aucun e-mail ne part |
| `VEYRA_MAIL_FROM` | Manquant | Adresse d'expéditeur des e-mails (ex. `factures@…`). Par défaut : `SMTP_USER` |
| `VEYRA_INVOICE_ISSUER_NAME` | À vérifier | Nom légal de VEYRA sur les factures (défaut `VEYRA`) |
| `VEYRA_INVOICE_ISSUER_LEGAL_FORM` | Manquant | Forme juridique (ex. `SAS au capital de …`) |
| `VEYRA_INVOICE_ISSUER_SIREN` | Manquant | **Obligatoire** pour les factures de commission (sinon refusées) |
| `VEYRA_INVOICE_ISSUER_ADDRESS` | Manquant | **Obligatoire** pour les factures de commission |
| `VEYRA_INVOICE_ISSUER_VAT_NUMBER` | Manquant | N° de TVA intracommunautaire de VEYRA |
| `VEYRA_COMMISSION_VAT_BPS` | À confirmer | TVA de la commission en points de base, montant TTC (défaut `2000` = 20 %). À changer si la commission n'est pas TTC à 20 % |
| `STRIPE_PUBLISHABLE_KEY` | Manquant | Paiement en ligne (portail et apps) : `payment-config` reste `enabled:false` |
| `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` | À vérifier | Paiement en ligne et confirmation des paiements |
| `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM` | Manquant | SMS au passager (lien de suivi partenaire) |
| `VEYRA_TERMS_VERSION`, `VEYRA_PRIVACY_VERSION`, `VEYRA_MARKETING_VERSION` | Manquant | Versions des textes légaux validés (sinon `PENDING_LEGAL_REVIEW`) |
| `VEYRA_TEST_ACCOUNTS_ENABLED` | À décider au lancement | `false` suspend les comptes de test (DEC-19 : conservés pour l'instant) |
| `GOOGLE_MAPS_API_KEY` | À vérifier | Itinéraires et distances côté serveur (Directions / Distance Matrix) |
| `LOCATIONIQ_TOKEN` | À vérifier | Recherche d'adresses |
| `VEYRA_GUEST_BASE_URL` | À vérifier | Adresse publique du site pour les liens de suivi `/suivi/{jeton}` |
| `VEYRA_ALLOWED_ORIGINS` | À vérifier | Domaine(s) du portail web autorisés (CORS) |
| `FIREBASE_ENABLED`, `FIREBASE_PROJECT_ID`, `FIREBASE_CREDENTIALS_PATH` | À vérifier | Connexion Google/Apple/téléphone et notifications |
| `DB_URL`, `DB_USER`, `DB_PASSWORD`, `JWT_SECRET`, `PIN_ENCRYPTION_KEY` | À vérifier (en place) | Base, sessions, chiffrement (PIN, IBAN) — ne jamais les changer sans procédure (`PIN_ENCRYPTION_KEY_PREVIOUS` pour une rotation) |
| `VEYRA_BOOTSTRAP_ADMIN_EMAIL`, `VEYRA_BOOTSTRAP_ADMIN_PASSWORD` | À vérifier | Premier compte administrateur |

## 2. GitHub (dépôt `fellimohamed22-source/Veyra`) — Settings › Secrets and variables › Actions

| Nom | Type | Statut | Rôle |
|---|---|---|---|
| `GOOGLE_MAPS_MOBILE_KEY` | Secret | En place (refusée par Google, voir §3) | Cartes Google natives des apps |
| `STRIPE_PUBLISHABLE_KEY` | Secret | Manquant | Paiement par carte dans les apps |
| `GOOGLE_SERVICES_JSON` | Secret | En place | Firebase Android |
| `GOOGLE_SERVICE_INFO_PLIST_CLIENT` | Secret | Manquant | Firebase iOS, app client (`com.veyra.client`) |
| `GOOGLE_SERVICE_INFO_PLIST_DRIVER` | Secret | Manquant | Firebase iOS, app chauffeur (`com.veyra.driver`) |
| `VEYRA_API_BASE_URL` | Variable | En place | Adresse de l'API dans les apps |

## 3. Comptes externes (hors variables)

- **Google Cloud, projet 383065284362** :
  1. Lier un compte de facturation (cause probable du refus actuel « Requested entity was not found »).
  2. Activer **Maps SDK for Android** et **Maps SDK for iOS** (et Map Tiles API pour le fond de secours).
  3. Clé `GOOGLE_MAPS_MOBILE_KEY` : restriction d'application « Aucune », restriction par API limitée à ces SDK.
  4. Relancer le workflow GitHub « android-apk » (bouton « Run workflow »).
  - Plus tard, pour verrouiller : clé Android restreinte à `com.veyra.client` / `com.veyra.driver`, empreinte SHA-1 `AF:F0:50:9C:B2:B7:92:56:F5:BA:BB:8D:26:3B:DD:8E:21:15:44:9A`.
- **Firebase** : activer le fournisseur **Apple** (Authentication) ; créer les apps iOS `com.veyra.client` et `com.veyra.driver` pour obtenir les `GoogleService-Info.plist`.
- **Apple Developer** : identifiants `com.veyra.client` / `com.veyra.driver` avec « Sign in with Apple » et « Push Notifications », certificats et profils pour TestFlight.
- **Stripe** : récupérer la clé publique (et vérifier le webhook vers `/api/v1/payments/stripe/webhook`).
- **Juridique** : textes CGU, confidentialité, charte chauffeur validés ; confirmation du mandat de facturation dans la charte.
- **Visuels** : photos HD sans texte (accueil client et chauffeur).

Après chaque déploiement Render : vérifier dans les logs que les migrations Flyway jusqu'à **V061** sont appliquées.
