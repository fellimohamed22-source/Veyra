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
        <h3>Créances Client / annulation CASH</h3>
        <p *ngIf="!customerDebts.length">Aucune créance.</p>
        <div *ngFor="let d of customerDebts" style="margin-bottom:14px">
          <div>{{d.email}} — {{(d.amount_minor-d.paid_amount_minor)/100}} € restant — {{d.status}}</div>
          <button *ngIf="d.status!=='PAID'" (click)="settleCustomer(d)">Marquer réglée</button>
        </div>
      </div>
      <div class="card">
        <h3>Payables Chauffeurs</h3>
        <p *ngIf="!payables.length">Aucun payable.</p>
        <div *ngFor="let p of payables" style="margin-bottom:14px">
          <span>{{p.driver_id}} — {{p.amount_minor/100}} € — {{p.status}}</span>
          <button *ngIf="p.status==='PAYABLE'" (click)="markPaid(p)">Marquer payé</button>
        </div>
      </div>
      <div class="card">
        <h3>Facturation partenaire</h3>
        <input [(ngModel)]="invoicePartnerId" placeholder="UUID partenaire">
        <label>Du</label>
        <input [(ngModel)]="invoiceFrom" type="date">
        <label>Au</label>
        <input [(ngModel)]="invoiceTo" type="date">
        <button (click)="generateInvoice()" [disabled]="invoiceLoading">Générer facture</button>
        <pre *ngIf="invoiceResult">{{invoiceResult | json}}</pre>
      </div>
      <div class="card">
        <h3>Règles CASH</h3>
        <p>Alerte 50 € • restriction CASH 100 € • blocage 150 €</p>
      </div>
    </div>`
})
export class Finance implements OnInit{
  debts:any[]=[];customerDebts:any[]=[];payables:any[]=[];loading=false;error='';
  invoicePartnerId='';invoiceFrom='';invoiceTo='';invoiceLoading=false;invoiceResult:any=null;
  constructor(private api:Api){}
  ngOnInit(){this.load();}
  async load(){
    this.loading=true;this.error='';
    try{this.debts=await this.api.cashDebts();this.customerDebts=await this.api.customerDebts();this.payables=await this.api.payables();}
    catch{this.error='Impossible de charger les données finance.';}
    finally{this.loading=false;}
  }
  async settle(d:any){
    const remaining=Math.max(0,(d.amount_minor||0)-(d.paid_amount_minor||0));
    if(remaining>0){await this.api.settleDebt(d.id,remaining);await this.load();}
  }

  async settleCustomer(d:any){
    const remaining=Math.max(0,(d.amount_minor||0)-(d.paid_amount_minor||0));
    if(remaining>0){await this.api.settleCustomerDebt(d.id,remaining);await this.load();}
  }

  async markPaid(p:any){
    await this.api.markPayablePaid(p.id);
    await this.load();
  }

  async generateInvoice(){
    if(!this.invoicePartnerId.trim()||!this.invoiceFrom||!this.invoiceTo)return;
    this.invoiceLoading=true;this.invoiceResult=null;
    try{
      this.invoiceResult=await this.api.generatePartnerInvoice(
        this.invoicePartnerId.trim(),this.invoiceFrom,this.invoiceTo);
    }catch(e:any){
      this.invoiceResult={error:e?.code||'GENERATION_FAILED'};
    }finally{
      this.invoiceLoading=false;
    }
  }
}
