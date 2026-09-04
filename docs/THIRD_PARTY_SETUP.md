# Intégrations à fournir avant pilote public

Le code métier ne doit jamais dépendre directement d'un fournisseur.

## Nécessaire plus tard
- Push mobile: projet Firebase, Android `google-services.json`, iOS `GoogleService-Info.plist`.
- Paiement ONLINE réel: compte PSP (Stripe Connect recommandé pour production), clés test/prod et webhook secret.
- Email production: SMTP ou provider transactionnel + domaine d'envoi.
- SMS fallback PIN/alertes: provider choisi + credentials. Le MVP peut fonctionner sans SMS si le bénéficiaire utilise l'app/partenaire.
- Cartographie: le dev utilise Nominatim + OpenStreetMap/OSRM. Pour un trafic public important, prévoir une instance propre ou un fournisseur respectant les quotas.
- KYC: au MVP, revue manuelle Admin des documents. Provider KYC externe facultatif.
- Stockage: filesystem au MVP; S3/MinIO plus tard.

Aucun secret ne doit être commité. Utiliser variables d'environnement / GitHub Secrets.
