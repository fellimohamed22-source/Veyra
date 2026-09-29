import {inject} from '@angular/core';
import {CanActivateFn, Router} from '@angular/router';

// Bug réel trouvé en lisant routes.ts : aucune des routes /admin,
// /finance, /partner, /support n'a jamais eu de canActivate. Le backend
// reste bien la seule autorité réelle (401 sur chaque appel sans token
// valide -- rien n'est exposé), mais côté UX la page atterrissait dans
// un cul-de-sac : "Impossible de charger…" avec un bouton "Réessayer"
// qui échoue indéfiniment, sans aucun moyen de revenir à /login. Un
// simple contrôle de présence du token avant d'entrer sur la route,
// pas une revalidation serveur ici (le clic sur "Réessayer" déclenchait
// déjà des appels API qui font foi) : ce garde ne fait qu'éviter le
// cul-de-sac, il ne remplace pas le contrôle serveur.
export const authGuard: CanActivateFn = () => {
  if (localStorage.getItem('accessToken')) return true;
  inject(Router).navigateByUrl('/login');
  return false;
};
