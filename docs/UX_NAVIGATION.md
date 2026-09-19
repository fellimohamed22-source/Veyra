# UX navigation

Client: Login → Home → Adresses autocomplete → Date/options → Récapitulatif → Publication → Offres → Choix → Confirmation → Jour J carte → PIN → Course → Note.

Chauffeur: Login → KYC → Demandes → tri date/plus récentes → détail → offre privée → agenda → confirmé → En route → Arrivé → PIN → Course → Terminer → revenus. Aucun tri proximité. Le chauffeur voit le meilleur prix concurrent actif comme repère de marché, sans contrainte sur son propre prix.

Partenaire: Login → Dashboard → bénéficiaire → trajet autocomplete → date/options → paiement → publier → offres → choisir → confirmation → jour J → chat/appel → finance.

Admin: Dashboard → KYC → Partenaires → Réservations → Finance → Commissions → Support.

Chaque écran réseau doit gérer loading, empty, error/retry et offline. Les notifications ouvrent par deep-link la réservation concernée. Chat/appel uniquement après confirmation.
