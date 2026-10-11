# État d'implémentation — source de vérité

## Livré dans feature/client-ux-microservices-v4

- Plan de migration microservices et traçabilité des maquettes.
- Gateway de compatibilité Nginx, config versionnée.
- Overlay Docker Compose opt-in qui démarre le backend monolithique derrière la gateway.
- Documentation de lancement et limites de sécurité.

## Non livré / non prétendu

- Extraction des services Java autonomes (identity, booking, marketplace, payment, etc.).
- Séparation des bases de données et migration de données.
- Nouvelles migrations Flyway pour historique de destinations ou rappels.
- Nouvelles API client pour assistance, reçus et préférences.
- Refonte Flutter des 35 écrans.
- Tests CI, tests d'intégration et validation de démarrage Docker.

## Prochaine tranche livrable

1. Exécuter la stack localement et valider la compatibilité HTTP/WebSocket et l'authentification.
2. Créer les tests de contrat OpenAPI et d'intégration sur booking/offers/payments.
3. Extraire un service sans transaction métier critique, idéalement routage/géocodage.
4. Développer la refonte Flutter et les nouvelles données uniquement après validation des contrats.

Cette note est intentionnellement explicite pour éviter de confondre documentation d'architecture et migration réellement terminée.
