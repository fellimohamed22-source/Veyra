# MVP acceptance checklist

## Fonctionnel
- [x] Email + mot de passe + JWT
- [x] Refresh token rotatif et révocable
- [x] Réinitialisation mot de passe par email
- [x] Onboarding Chauffeur VTC + KYC manuel Admin
- [x] Documents stockés sur filesystem backend
- [x] Réservation programmée uniquement
- [x] Lead time minimum H-2
- [x] Fenêtre courte H-2..H-4
- [x] Autocomplete adresse via provider backend
- [x] Routing provider abstrait
- [x] Demandes chauffeur avec tris sans proximité
- [x] Offre privée chauffeur
- [x] Aucune visibilité chauffeur sur les offres concurrentes
- [x] Client/Partenaire voit toutes les offres actives
- [x] Sélection atomique d'une offre
- [x] Snapshot financier immuable
- [x] Commission standard 10% configurable
- [x] Commission partenaire configurable
- [x] CASH avec dette chauffeur
- [x] ONLINE avec Stripe PaymentIntent + webhook signé
- [x] PARTNER_INVOICE activé pour partenaires approuvés
- [x] PIN obligatoire 4 chiffres
- [x] Chat Veyra après confirmation
- [x] Appel téléphonique après confirmation
- [x] GPS live jour J
- [x] Notifications In-App / Push provider
- [x] Deep-links notifications
- [x] Portail Partenaire
- [x] Admin / Support / Finance
- [x] Annulation / no-show
- [x] Rating
- [x] Flutter Client
- [x] Flutter Chauffeur
- [x] Angular Partner/Admin/Support/Finance
- [x] CI backend / web / mobile

## Sécurité
- [x] BCrypt
- [x] JWT court
- [x] Refresh token hashé
- [x] RBAC backend
- [x] Autorisation objet
- [x] WebSocket JWT + autorisation par réservation
- [x] PIN hashé + chiffré
- [x] Documents privés
- [x] Secrets uniquement par variables d'environnement
- [x] Idempotence paiement
- [x] Stripe webhook signature
- [x] Allowed origins configurables

## À fournir pour le pilote public
- [ ] Nouvelle clé Stripe secrète test/prod + webhook secret
- [ ] Clé publique Stripe pour les apps
- [ ] Projet Firebase + credentials mobile/backend
- [ ] SMTP de production
- [ ] Domaine + TLS
- [ ] Optionnel : SMS fallback
- [ ] Capacité cartographie/routing adaptée au volume
- [ ] Validation juridique France : CGU, confidentialité, conservation, VTC, annulation/no-show
- [ ] Signing Android/iOS et comptes stores
- [ ] Tests E2E sur appareils physiques avant publication
