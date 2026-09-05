import {Component} from '@angular/core';
import {FormsModule} from '@angular/forms';
import {CommonModule} from '@angular/common';
import {Router} from '@angular/router';
import {Api} from '../api';

@Component({
  standalone:true,
  imports:[FormsModule,CommonModule],
  template:`
    <div class="card" style="max-width:460px;margin:40px auto">
      <h1>Connexion Veyra</h1>
      <label>Email</label>
      <input [(ngModel)]="email" type="email" autocomplete="username">
      <label>Mot de passe</label>
      <input [(ngModel)]="password" type="password" autocomplete="current-password">
      <p *ngIf="error" style="color:#b91c1c">{{error}}</p>
      <button (click)="login()" [disabled]="loading">{{loading?'Connexion…':'Se connecter'}}</button>
    </div>`
})
export class Login{
  email='';password='';loading=false;error='';
  constructor(private api:Api,private router:Router){}
  async login(){
    this.loading=true;this.error='';
    try{
      await this.api.login(this.email,this.password);
      const me=await this.api.me();
      const roles=(me.roles||[]) as string[];
      if(roles.includes('ADMIN'))await this.router.navigateByUrl('/admin');
      else if(roles.includes('FINANCE'))await this.router.navigateByUrl('/finance');
      else if(roles.includes('SUPPORT'))await this.router.navigateByUrl('/support');
      else if(roles.some(r=>r.startsWith('PARTNER_')))await this.router.navigateByUrl('/partner');
      else this.error='Ce compte n’a pas accès au portail web.';
    }
    catch{this.error='Identifiants invalides ou service indisponible.';}
    finally{this.loading=false;}
  }
}
