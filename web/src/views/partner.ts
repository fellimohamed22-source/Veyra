import {CommonModule} from '@angular/common';
import {Component} from '@angular/core';
import {FormsModule} from '@angular/forms';
import {Api} from '../api';

@Component({
  standalone:true,
  imports:[CommonModule,FormsModule],
  template:`
    <h1>Portail Partenaire</h1>
    <p>Hôtel • Restaurant • Bar • Conciergerie</p>
    <div class="grid">
      <div class="card">
        <h3>Créer mon établissement</h3>
        <input [(ngModel)]="name" placeholder="Nom établissement">
        <select [(ngModel)]="type">
          <option value="HOTEL">Hôtel</option><option value="RESTAURANT">Restaurant</option>
          <option value="BAR">Bar</option><option value="CONCIERGE">Conciergerie</option>
        </select>
        <input [(ngModel)]="billingEmail" placeholder="Email facturation">
        <button (click)="create()" [disabled]="loading">Créer le compte partenaire</button>
        <p *ngIf="message">{{message}}</p>
      </div>
      <div class="card">
        <h3>Réservation pour un client</h3>
        <p>Le partenaire renseigne le bénéficiaire, les adresses, la date et le paiement.</p>
        <p>Les chauffeurs transmettent des offres privées et ne voient jamais les offres concurrentes.</p>
      </div>
      <div class="card">
        <h3>PARTNER_INVOICE</h3>
        <p>Disponible après validation Veyra et activation d’un plafond de crédit.</p>
      </div>
    </div>`
})
export class Partner{
  name='';type='HOTEL';billingEmail='';loading=false;message='';
  constructor(private api:Api){}
  async create(){
    if(!this.name.trim())return;
    this.loading=true;this.message='';
    try{
      const r=await this.api.createPartner({name:this.name,partnerType:this.type,billingEmail:this.billingEmail});
      this.message='Partenaire créé : '+r.partnerId+'. Validation Veyra requise.';
    }catch{this.message='Création impossible.';}
    finally{this.loading=false;}
  }
}
