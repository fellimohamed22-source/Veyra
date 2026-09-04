import {Component} from '@angular/core';
import {FormsModule} from '@angular/forms';
import {Router} from '@angular/router';
import {Api} from '../api';

@Component({
  standalone:true,
  imports:[FormsModule],
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
    try{await this.api.login(this.email,this.password);await this.router.navigateByUrl('/admin');}
    catch{this.error='Identifiants invalides ou service indisponible.';}
    finally{this.loading=false;}
  }
}
