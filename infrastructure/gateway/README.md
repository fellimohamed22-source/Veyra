# API Gateway Veyra — première étape exécutable

Cette gateway Nginx est **réelle**, mais elle route encore tous les endpoints vers le backend monolithique. Ce n'est pas encore une extraction microservices.

## Démarrage local

Depuis la racine du dépôt, fournir des secrets de développement valides (sans les committer):

```sh
export JWT_SECRET='replace-with-a-long-random-dev-secret-of-at-least-32-characters'
export PIN_ENCRYPTION_KEY='replace-with-a-valid-32-byte-dev-pin-key'
docker compose -f docker-compose.yml -f infrastructure/docker-compose.microservices.yml up --build
curl -fsS http://localhost:8088/gateway-health
curl -fsS http://localhost:8088/actuator/health
```

Les apps Flutter peuvent pointer vers `http://<host>:8088` dans un environnement de développement adapté. Ne pas utiliser HTTP non chiffré en production.

## Sécurité / limitations

- La gateway transmet les en-têtes Authorization et les requêtes websocket.
- AuthN/AuthZ restent appliquées par le backend; ne pas exposer des endpoints administratifs sans contrôles réseau supplémentaires.
- Les secrets sont fournis par l'environnement, pas dans Git.
- TLS, rate limiting, circuit breaker, tracing et restriction des routes admin sont nécessaires avant production.
- L'URL /gateway-health prouve uniquement que Nginx répond, pas que le backend est disponible.
- Le démarrage et les tests n'ont pas été exécutés depuis ce connecteur GitHub.

## Étape suivante

Extraire un service à la fois et remplacer des routes spécifiques par upstreams distincts; maintenir `/api/v1` et des tests contractuels.
