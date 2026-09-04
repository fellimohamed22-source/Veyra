import {CommonModule} from '@angular/common';
import {Component,OnInit} from '@angular/core';
import {FormsModule} from '@angular/forms';
import {Api} from '../api';

@Component({
  standalone:true,
  imports:[CommonModule,FormsModule],
  template:`
    <h1>Finance</h1>
    <div *ngIf="loading" class="card">Chargement…</div>
    <div *ngIf="error" class="card">{{error}} <button (click)="load()">Réessayer</button></div>
    <div class="grid">
      <div class="card">
        <h3>Dettes CASH</h3>
        <p *ngIf="!debts.length">Aucune dette.</p>
        <div *ngFor="let d of debts" style="margin-bottom:14px">
          <div>Chauffeur {{d.driver_id}} — {{d.amount_minor/100}} € — {{d.status}}</div>
          <button (click)="settle(d)">Marquer réglée</button>
        </div>
      </div>
      <div class="card">
        <h3>Payables Chauffeurs</h3>
        <p *ngIf="!payables.length">Aucun payable.</p>
        <div *ngFor="let p of payables">{{p.driver_id}} — {{p.amount_minor/100}} € — {{p.status}}</div>
      </div>
      <div class="card">
        <h3>Règles CASH</h3>
        <p>Alerte 50 € • restriction CASH 100 € • blocage 150 €</p>
      </div>
    </div>`
})
export class Finance implements OnInit{
  debts:any[]=[];payables:any[]=[];loading=false;error='';
  constructor(private api:Api){}
  ngOnInit(){this.load();}
  async load(){
    this.loading=true;this.error='';
    try{this.debts=await this.api.cashDebts();this.payables=await this.api.payables();}
    catch{this.error='Impossible de charger les données finance.';}
    finally{this.loading=false;}
  }
  async settle(d:any){
    const remaining=Math.max(0,(d.amount_minor||0)-(d.paid_amount_minor||0));
    if(remaining>0){await this.api.settleDebt(d.id,remaining);await this.load();}
  }
}
