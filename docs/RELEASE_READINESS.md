# Release readiness

## Fonctionnel
Réservation programmée, offres privées chauffeur, visibilité de toutes les offres côté Client/Partenaire, sélection atomique, commission snapshotée, CASH/ONLINE/PARTNER_INVOICE, PIN obligatoire, chat/appel après confirmation, suivi GPS jour J, KYC manuel VTC, Admin/Support/Finance, notifications et rappels.

## UX
Client et Chauffeur possèdent les parcours principaux, ainsi que les états génériques loading/empty/error/offline documentés. Le web Partner/Admin/Finance/Support est responsive.

## Sécurité
Email/password/JWT, refresh rotation, BCrypt, RBAC, object authorization, WebSocket JWT CONNECT, documents privés, PIN hashé + chiffré, secrets par environnement, paramètres SQL, idempotence paiement, aucune offre concurrente exposée aux chauffeurs.

## Pilote public
Nécessite des credentials réels pour paiement online, push mobile, SMTP production, éventuellement SMS, ainsi qu'une capacité cartographie/routing adaptée au volume. Les CGU, politique de confidentialité, règles VTC et rétention doivent être validées juridiquement avant production.

## Validation finale
Cette branche déclenche la validation CI du dernier état fonctionnel du MVP.
