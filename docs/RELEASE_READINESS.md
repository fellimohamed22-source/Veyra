# Release readiness

## Fonctionnel
Réservation programmée, offres privées chauffeur, visibilité de toutes les offres côté Client/Partenaire, sélection atomique, commission snapshotée, CASH/ONLINE/PARTNER_INVOICE, PIN obligatoire, chat/appel après confirmation, suivi GPS jour J, KYC manuel VTC, Admin/Support/Finance, notifications et rappels.

## UX
Client et Chauffeur possèdent les parcours principaux, ainsi que les états génériques loading/empty/error/offline documentés. Le web Partner/Admin/Finance/Support est responsive.

## Sécurité
Email/password/JWT, refresh rotation, BCrypt, RBAC, object authorization, WebSocket JWT CONNECT, documents privés, PIN hashé + chiffré, secrets par environnement, paramètres SQL, idempotence paiement, aucune offre concurrente exposée aux chauffeurs.

## Pilote public
Nécessite des credentials réels pour paiement online, push mobile, SMTP production, éventuellement SMS, ainsi qu'une capacité cartographie/routing adaptée au volume. Les CGU, politique de confidentialité, règles VTC et rétention doivent être validées juridiquement avant production.

## Dette technique connue

### SMTP production non configuré
**Statut :** ouvert — ajouté volontairement en dette, à traiter avant le pilote public.

**Contexte :** `spring.mail.*` a été ajouté à `application.yml` (commit `b88ff2a`) uniquement pour que le bean `JavaMailSender` existe et que l'application démarre — `PasswordController` en dépend pour l'email de réinitialisation de mot de passe. Les valeurs par défaut (`SMTP_HOST=localhost`, pas d'auth) permettent le démarrage mais ne permettent PAS l'envoi réel d'emails.

**Impact tant que non traité :** le flux "mot de passe oublié" échoue silencieusement en production (l'appel API ne plante pas côté client mais aucun email ne part réellement).

**À faire avant le pilote public :**
- Choisir un fournisseur SMTP (SendGrid, Mailgun, AWS SES, etc.).
- Renseigner `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD` sur Render avec les vraies valeurs.
- Tester réellement le flux `/api/v1/auth/forgot-password` de bout en bout (réception de l'email).
- Retirer cette section une fois validé.
