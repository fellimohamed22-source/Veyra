import {CommonModule} from '@angular/common';
import {Component,OnInit} from '@angular/core';
import {FormsModule} from '@angular/forms';
import {Api} from '../api';

@Component({
  standalone:true,
  imports:[CommonModule,FormsModule],
  template:`
    <h1>Administration Veyra</h1>

    <div *ngIf="loading" class="card">Chargement…</div>
    <div *ngIf="error" class="card">{{error}} <button (click)="load()">Réessayer</button></div>

    <div class="grid" *ngIf="dashboard">
      <div class="card"><h3>Réservations</h3><strong>{{dashboard.bookings}}</strong></div>
      <div class="card"><h3>KYC Chauffeurs en attente</h3><strong>{{dashboard.pendingDrivers}}</strong></div>
      <div class="card"><h3>Partenaires en attente</h3><strong>{{dashboard.pendingPartners}}</strong></div>
    </div>

    <div class="card">
      <h3>Chauffeurs / KYC</h3>
      <p *ngIf="drivers.length===0">Aucun chauffeur.</p>
      <div *ngFor="let d of drivers" style="border-top:1px solid #e5e7eb;padding:12px 0">
        <strong>{{d.first_name}} {{d.last_name}}</strong>
        <div>{{d.email}} • {{d.phone||'sans téléphone'}} • {{d.kyc_status}}</div>
        <button *ngIf="d.kyc_status!=='APPROVED'" (click)="approveDriver(d.id)">Approuver</button>
        <button *ngIf="d.kyc_status!=='APPROVED'" (click)="rejectDriver(d.id)">Rejeter</button>
      </div>
    </div>

    <div class="card">
      <h3>Partenaires</h3>
      <p *ngIf="partners.length===0">Aucun partenaire.</p>
      <div *ngFor="let p of partners" style="border-top:1px solid #e5e7eb;padding:12px 0">
        <strong>{{p.name}}</strong>
        <div>{{p.partner_type}} • {{p.status}} • crédit {{p.credit_status}}</div>
        <button *ngIf="p.status!=='APPROVED'" (click)="approvePartner(p.id)">Approuver</button>
        <button *ngIf="p.status==='APPROVED'" (click)="suspendPartner(p.id)">Suspendre</button>
        <div *ngIf="p.status==='APPROVED'" style="margin-top:10px">
          <label>Commission partenaire (%)</label>
          <input type="number" min="0" max="30" step="0.1"
            [ngModel]="partnerCommissionPercent[p.id] ?? 6"
            (ngModelChange)="partnerCommissionPercent[p.id]=$event">
          <button (click)="savePartnerCommission(p.id)">Enregistrer commission</button>

          <label>Plafond PARTNER_INVOICE (€)</label>
          <input type="number" min="0" step="100"
            [ngModel]="partnerCreditEuro[p.id] ?? ((p.credit_limit_minor||0)/100)"
            (ngModelChange)="partnerCreditEuro[p.id]=$event">
          <button (click)="savePartnerCredit(p.id)">Enregistrer crédit</button>
        </div>
      </div>
    </div>

    <div class="card">
      <h3>Configuration commerciale</h3>
      <label>Commission Client standard (%)</label>
      <input type="number" min="0" max="30" step="0.1" [(ngModel)]="standardCommissionPercent">
      <button (click)="saveStandardCommission()">Enregistrer</button>
      <p *ngIf="configMessage">{{configMessage}}</p>
    </div>

    <div class="card">
      <h3>Réservations récentes</h3>
      <p *ngIf="bookings.length===0">Aucune réservation.</p>
      <table *ngIf="bookings.length" style="width:100%;border-collapse:collapse">
        <thead><tr><th>Trajet</th><th>Date</th><th>Statut</th><th>Paiement</th></tr></thead>
        <tbody>
          <tr *ngFor="let b of bookings">
            <td>{{b.pickup_address}} → {{b.dropoff_address}}</td>
            <td>{{b.scheduled_at}}</td>
            <td>{{b.status}}</td>
            <td>{{b.payment_method}}</td>
          </tr>
        </tbody>
      </table>
    </div>
  `
})
export class Admin implements OnInit{
  dashboard:any=null;
  bookings:any[]=[];
  drivers:any[]=[];
  partners:any[]=[];
  loading=false;
  error='';
  standardCommissionPercent=10;
  partnerCommissionPercent:Record<string,number>={};
  partnerCreditEuro:Record<string,number>={};
  configMessage='';

  constructor(private api:Api){}

  ngOnInit(){this.load();}

  async load(){
    this.loading=true;this.error='';
    try{
      const [dashboard,bookings,drivers,partners]=await Promise.all([
        this.api.adminDashboard(),
        this.api.adminBookings(),
        this.api.adminDrivers(),
        this.api.adminPartners()
      ]);
      this.dashboard=dashboard;
      this.bookings=bookings;
      this.drivers=drivers;
      this.partners=partners;
    }catch{
      this.error='Impossible de charger le back-office.';
    }finally{
      this.loading=false;
    }
  }

  async approveDriver(id:string){await this.api.approveDriver(id);await this.load();}
  async rejectDriver(id:string){
    const reason=prompt('Motif de rejet KYC')||'DOCUMENT_INVALID';
    await this.api.rejectDriver(id,reason);await this.load();
  }
  async approvePartner(id:string){await this.api.approvePartner(id);await this.load();}
  async suspendPartner(id:string){await this.api.suspendPartner(id);await this.load();}
  async saveStandardCommission(){
    const bps=Math.round(this.standardCommissionPercent*100);
    try{
      await this.api.setStandardCommission(bps);
      this.configMessage='Commission standard mise à jour.';
    }catch{
      this.configMessage='Impossible de modifier la commission.';
    }
  }

  async savePartnerCommission(id:string){
    const value=this.partnerCommissionPercent[id] ?? 6;
    try{
      await this.api.setPartnerCommission(id,Math.round(value*100));
      this.configMessage='Commission partenaire mise à jour.';
    }catch{
      this.configMessage='Impossible de modifier la commission partenaire.';
    }
  }

  async savePartnerCredit(id:string){
    const euro=this.partnerCreditEuro[id] ?? 0;
    try{
      await this.api.setPartnerCredit(id,Math.round(euro*100),30,'MONTHLY');
      this.configMessage='Plafond PARTNER_INVOICE mis à jour.';
      await this.load();
    }catch{
      this.configMessage='Impossible de modifier le crédit partenaire.';
    }
  }
}
