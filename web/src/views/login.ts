import {Component} from '@angular/core';
import {FormsModule} from '@angular/forms';
import {CommonModule} from '@angular/common';
import {Router} from '@angular/router';
import {Api} from '../api';

@Component({
  standalone:true,
  imports:[FormsModule,CommonModule],
  template:`
    <div class="login">
      <div class="card">
        <div class="brand">VEYRA</div>
        <p class="sub" style="text-align:center;margin:0">Portail partenaires et administration</p>
        <div class="field"><label for="email">E-mail</label><input id="email" [(ngModel)]="email" type="email" autocomplete="username"></div>
        <div class="field"><label for="password">Mot de passe</label><input id="password" [(ngModel)]="password" type="password" autocomplete="current-password" (keyup.enter)="login()"></div>
        <div class="errbox" *ngIf="error">{{error}}</div>
        <button (click)="login()" [disabled]="loading">{{loading?'Connexion…':'Se connecter'}}</button>
      </div>
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
      else if(roles.includes('FINANCE'))await this.router.navigateByUrl('/admin/finance');
      else if(roles.includes('SUPPORT'))await this.router.navigateByUrl('/admin/support');
      else if(roles.some(r=>r.startsWith('PARTNER_')))await this.router.navigateByUrl('/partner');
      else{
        // An invited team member (PART-16) joins on this call.
        const orgs=await this.api.partnerOrganizations().catch(()=>[]);
        if(orgs.length)await this.router.navigateByUrl('/partner');
        else this.error='Ce compte n’a pas accès au portail web.';
      }
    }
    catch{this.error='Identifiants invalides ou service indisponible.';}
    finally{this.loading=false;}
  }
}
