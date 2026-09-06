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
      <h3>Visibilité des offres pour les chauffeurs</h3>
      <p>
        <strong>Offre privée</strong> : le chauffeur ne voit aucun prix concurrent, il saisit librement son prix.<br>
        <strong>Meilleure offre visible</strong> : le chauffeur voit uniquement le prix le plus bas actuellement proposé par les autres chauffeurs (jamais leur identité), à titre indicatif — cela ne bloque jamais l'envoi de son offre.
      </p>
      <label>
        <input type="radio" name="offerVisibility" value="PRIVATE" [(ngModel)]="offerVisibilityMode"> Offre privée (par défaut)
      </label>
      <label style="margin-left:16px">
        <input type="radio" name="offerVisibility" value="BEST_VISIBLE" [(ngModel)]="offerVisibilityMode"> Meilleure offre visible
      </label>
      <div style="margin-top:10px">
        <button (click)="saveOfferVisibility()">Enregistrer</button>
      </div>
      <p *ngIf="offerVisibilityMessage">{{offerVisibilityMessage}}</p>
      <p style="color:#6b7280;font-size:13px">
        S'applique à toute nouvelle réservation à partir de l'enregistrement — les réservations déjà en cours d'enchère gardent le mode qui était actif à leur création.
      </p>
    </div>

    <div class="card">
      <h3>Politique annulation / no-show</h3>
      <div class="grid">
        <label>Annulation gratuite jusqu'à H- (heures)
          <input type="number" min="0" [(ngModel)]="cancellationFreeHours">
        </label>
        <label>Fenêtre intermédiaire jusqu'à H- (heures)
          <input type="number" min="0" [(ngModel)]="cancellationMidHours">
        </label>
        <label>Frais H-6 → H-2 (% du prix chauffeur)
          <input type="number" min="0" max="100" [(ngModel)]="cancellationMidPercent">
        </label>
        <label>Minimum frais intermédiaires (€)
          <input type="number" min="0" [(ngModel)]="cancellationMidMinEuro">
        </label>
        <label>Frais &lt; H-2 (%)
          <input type="number" min="0" max="100" [(ngModel)]="cancellationLatePercent">
        </label>
        <label>No-show (%)
          <input type="number" min="0" max="100" [(ngModel)]="noShowPercent">
        </label>
        <label>Plafond no-show (€)
          <input type="number" min="1" [(ngModel)]="noShowCapEuro">
        </label>
      </div>
      <button (click)="saveCancellationPolicy()">Enregistrer la politique</button>
      <p *ngIf="policyMessage">{{policyMessage}}</p>
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
  offerVisibilityMode='PRIVATE';
  offerVisibilityMessage='';
  cancellationFreeHours=6;
  cancellationMidHours=2;
  cancellationMidPercent=10;
  cancellationMidMinEuro=5;
  cancellationLatePercent=25;
  noShowPercent=50;
  noShowCapEuro=100;
  policyMessage='';

  constructor(private api:Api){}

  ngOnInit(){this.load();this.loadCancellationPolicy();this.loadOfferVisibility();}

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

  async loadOfferVisibility(){
    try{
      const p=await this.api.getOfferVisibility();
      this.offerVisibilityMode=p.mode||'PRIVATE';
    }catch{}
  }

  async saveOfferVisibility(){
    this.offerVisibilityMessage='';
    try{
      await this.api.setOfferVisibility(this.offerVisibilityMode);
      this.offerVisibilityMessage='Mode de visibilité des offres mis à jour.';
    }catch{
      this.offerVisibilityMessage='Impossible de modifier ce réglage.';
    }
  }

  async loadCancellationPolicy(){
    try{
      const p=await this.api.getCancellationPolicy();
      this.cancellationFreeHours=(p.free_until_minutes||360)/60;
      this.cancellationMidHours=(p.mid_window_from_minutes||120)/60;
      this.cancellationMidPercent=(p.mid_fee_bps||1000)/100;
      this.cancellationMidMinEuro=(p.mid_fee_min_minor||500)/100;
      this.cancellationLatePercent=(p.late_fee_bps||2500)/100;
      this.noShowPercent=(p.no_show_fee_bps||5000)/100;
      this.noShowCapEuro=(p.no_show_cap_minor||10000)/100;
    }catch{}
  }

  async saveCancellationPolicy(){
    this.policyMessage='';
    try{
      await this.api.setCancellationPolicy({
        freeUntilMinutes:Math.round(this.cancellationFreeHours*60),
        midWindowFromMinutes:Math.round(this.cancellationMidHours*60),
        midFeeBps:Math.round(this.cancellationMidPercent*100),
        lateFeeBps:Math.round(this.cancellationLatePercent*100),
        noShowFeeBps:Math.round(this.noShowPercent*100),
        driverShareMidBps:7000,
        driverShareLateBps:8000,
        driverShareNoShowBps:8000,
        midFeeMinMinor:Math.round(this.cancellationMidMinEuro*100),
        noShowCapMinor:Math.round(this.noShowCapEuro*100),
      });
      this.policyMessage='Politique mise à jour et versionnée.';
      await this.loadCancellationPolicy();
    }catch{
      this.policyMessage='Politique invalide ou mise à jour impossible.';
    }
  }
}
