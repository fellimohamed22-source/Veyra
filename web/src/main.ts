import {bootstrapApplication} from '@angular/platform-browser';import {provideRouter,Router,RouterOutlet,RouterLink,NavigationEnd} from '@angular/router';import {Component} from '@angular/core';import {CommonModule} from '@angular/common';import {routes} from './routes';import {Api} from './api';
// Bug réel corrigé ici : le nav affichait les 4 liens (Partenaire,
// Admin, Finance, Support) en permanence, y compris sur /login avant
// toute connexion, et il n'existait aucun moyen de se déconnecter
// nulle part dans l'app -- api.logout() existait déjà (utilisé en
// interne par le refresh-token raté) mais rien ne l'appelait jamais
// depuis l'UI. loggedIn est réévalué à chaque cycle de détection de
// changement (lecture localStorage, pas de state à synchroniser) et
// mis à jour explicitement sur chaque navigation pour rafraîchir la
// vue juste après un login ou un logout.
@Component({selector:'app-root',standalone:true,imports:[RouterOutlet,RouterLink,CommonModule],template:`<div class="shell"><nav class="nav"><h2>Veyra</h2><ng-container *ngIf="loggedIn"><a routerLink="/partner">Partenaire</a><a routerLink="/admin">Admin</a><a routerLink="/finance">Finance</a><a routerLink="/support">Support</a><a (click)="logout()" style="cursor:pointer">Déconnexion</a></ng-container></nav><main class="content"><router-outlet/></main></div>`})
class App{
  loggedIn=!!localStorage.getItem('accessToken');
  constructor(private api:Api,private router:Router){
    this.router.events.subscribe(e=>{if(e instanceof NavigationEnd)this.loggedIn=!!localStorage.getItem('accessToken');});
  }
  logout(){this.api.logout();this.loggedIn=false;this.router.navigateByUrl('/login');}
}
bootstrapApplication(App,{providers:[provideRouter(routes)]});