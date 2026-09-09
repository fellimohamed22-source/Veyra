import {CommonModule} from '@angular/common';
import {Component,OnInit} from '@angular/core';
import {FormsModule} from '@angular/forms';
import {Api} from '../api';
import {statusLabel,paymentMethodLabel,partnerOrgStatusLabel,money,dateTime,errorMessage,invoiceStatusLabel} from '../formatters';

@Component({
  standalone:true,
  imports:[CommonModule,FormsModule],
  template:`
    <h1>Portail Partenaire</h1>
    <p>Hôtel • Restaurant • Bar • Conciergerie</p>

    <div class="grid">
      <div class="card">
        <h3>Compte partenaire</h3>
        <ng-container *ngIf="!partnerId; else existing">
          <ng-container *ngIf="organizations.length">
            <label>Organisation existante</label>
            <select [(ngModel)]="selectedOrganizationId">
              <option value="">Choisir une organisation</option>
              <option *ngFor="let organization of organizations" [value]="organization.id">
                {{organization.name}} • {{partnerOrgStatusLabel(organization.status)}}
              </option>
            </select>
            <button (click)="useOrganization()" [disabled]="!selectedOrganizationId">Ouvrir</button>
            <hr>
          </ng-container>
          <input [(ngModel)]="name" placeholder="Nom établissement">
          <select [(ngModel)]="type">
            <option value="HOTEL">Hôtel</option>
            <option value="RESTAURANT">Restaurant</option>
            <option value="BAR">Bar</option>
            <option value="CONCIERGE">Conciergerie</option>
          </select>
          <input [(ngModel)]="billingEmail" placeholder="Email facturation">
          <button (click)="createPartner()" [disabled]="loading">Créer</button>
        </ng-container>
        <ng-template #existing>
          <p>Partenaire actif dans cette session : <strong>{{partnerId}}</strong></p>
          <button (click)="clearPartner()">Changer</button>
        </ng-template>
        <p *ngIf="message">{{message}}</p>
      </div>

      <div class="card" *ngIf="partnerId">
        <h3>Nouvelle réservation pour un client</h3>
        <input [(ngModel)]="guestName" placeholder="Nom du client">
        <input [(ngModel)]="guestPhone" placeholder="Téléphone du client">

        <label>Départ</label>
        <input [(ngModel)]="pickupText" (input)="searchAddress(true)" placeholder="Adresse de départ">
        <div *ngIf="pickupSuggestions.length">
          <button *ngFor="let p of pickupSuggestions" type="button" (click)="selectAddress(true,p)"
            style="display:block;width:100%;margin:4px 0;background:#e5e7eb;color:#111827">
            {{p.label}}
          </button>
        </div>

        <label>Destination</label>
        <input [(ngModel)]="dropoffText" (input)="searchAddress(false)" placeholder="Destination">
        <div *ngIf="dropoffSuggestions.length">
          <button *ngFor="let p of dropoffSuggestions" type="button" (click)="selectAddress(false,p)"
            style="display:block;width:100%;margin:4px 0;background:#e5e7eb;color:#111827">
            {{p.label}}
          </button>
        </div>

        <input [(ngModel)]="scheduledAt" type="datetime-local">

        <select [(ngModel)]="categoryId">
          <option value="">Catégorie véhicule</option>
          <option *ngFor="let c of categories" [value]="c.id">{{c.display_name}}</option>
        </select>

        <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px">
          <div><label>Passagers</label><input [(ngModel)]="passengerCount" type="number" min="1" max="9"></div>
          <div><label>Bagages</label><input [(ngModel)]="baggageCount" type="number" min="0" max="12"></div>
        </div>

        <select [(ngModel)]="paymentMethod">
          <option value="CASH">Client paie Cash</option>
          <option value="ONLINE">Client/partenaire paie en ligne</option>
          <option value="PARTNER_INVOICE">Facture partenaire</option>
        </select>

        <div style="margin:12px 0">
          <label style="display:block;margin-bottom:4px">Visibilité des offres pour les chauffeurs</label>
          <label style="font-weight:normal">
            <input type="radio" name="partnerOfferVisibility" value="" [(ngModel)]="offerVisibilityMode"> Réglage plateforme par défaut
          </label><br>
          <label style="font-weight:normal">
            <input type="radio" name="partnerOfferVisibility" value="PRIVATE" [(ngModel)]="offerVisibilityMode"> Offre privée (aucun prix concurrent visible)
          </label><br>
          <label style="font-weight:normal">
            <input type="radio" name="partnerOfferVisibility" value="BEST_VISIBLE" [(ngModel)]="offerVisibilityMode"> Meilleure offre visible (indicatif uniquement, jamais bloquant)
          </label>
        </div>

        <button (click)="publish()" [disabled]="publishing">{{publishing?'Publication…':'Publier la demande'}}</button>
        <p *ngIf="publishMessage">{{publishMessage}}</p>
      </div>

      <div class="card" *ngIf="partnerId">
        <h3>Mes réservations</h3>
        <button (click)="loadBookings()">Actualiser</button>
        <p *ngIf="bookings.length===0">Aucune réservation.</p>
        <div *ngFor="let b of bookings" style="border-top:1px solid #e5e7eb;padding:12px 0">
          <strong>{{b.pickup_address}} → {{b.dropoff_address}}</strong>
          <div>{{dateTime(b.scheduled_at)}} • {{statusLabel(b.status)}} • {{paymentMethodLabel(b.payment_method)}}</div>
          <button *ngIf="b.status==='OPEN_FOR_OFFERS'||b.status==='OFFERS_RECEIVED'" (click)="loadOffers(b.id)">Voir les offres</button>
        </div>
      </div>

      <div class="card" *ngIf="selectedBookingId">
        <h3>Offres reçues</h3>
        <p>Le partenaire voit toutes les offres ; les chauffeurs ne voient jamais les offres concurrentes.</p>
        <p *ngIf="offers.length===0">Aucune offre active.</p>
        <div *ngFor="let o of offers" style="border-top:1px solid #e5e7eb;padding:12px 0">
          <strong>{{money(o.totalMinor)}} total</strong>
          <div>{{o.driverFirstName||'Chauffeur'}} • {{o.vehicleCategory||'VTC'}} • {{o.vehicleBrand||''}} {{o.vehicleModel||''}}</div>
          <div>Prix chauffeur {{money(o.driverPriceMinor)}} • note {{o.rating}}</div>
          <button (click)="accept(o.offerId)" [disabled]="accepting">{{accepting?'Sélection…':'Choisir ce chauffeur'}}</button>
          <p *ngIf="acceptError" style="color:#dc2626">{{acceptError}}</p>
        </div>
      </div>

      <div class="card" *ngIf="partnerId">
        <h3>Facturation partenaire</h3>
        <p>Activé uniquement après validation Veyra et attribution d’un plafond de crédit.</p>
        <button (click)="loadFinance()">Voir l'encours</button>
        <pre *ngIf="finance">{{finance | json}}</pre>
      </div>

      <div class="card" *ngIf="partnerId">
        <h3>Clients enregistrés</h3>
        <p>Optionnel : enregistrez vos clients habituels pour les retrouver rapidement. Une réservation ne nécessite pas un client enregistré.</p>
        <input [(ngModel)]="newBeneficiaryName" placeholder="Nom complet">
        <input [(ngModel)]="newBeneficiaryPhone" placeholder="Téléphone">
        <input [(ngModel)]="newBeneficiaryEmail" placeholder="Email (optionnel)">
        <button (click)="createBeneficiary()" [disabled]="creatingBeneficiary || !newBeneficiaryName.trim()">
          {{creatingBeneficiary?'Enregistrement…':'Ajouter ce client'}}
        </button>
        <p *ngIf="beneficiaryMessage">{{beneficiaryMessage}}</p>
        <hr>
        <button (click)="loadBeneficiaries()">Actualiser la liste</button>
        <p *ngIf="beneficiariesLoaded && beneficiaries.length===0">Aucun client enregistré pour le moment.</p>
        <div *ngFor="let b of beneficiaries" style="border-top:1px solid #e5e7eb;padding:8px 0">
          <strong>{{b.full_name}}</strong>
          <div>{{b.phone}}<span *ngIf="b.email"> • {{b.email}}</span></div>
        </div>
      </div>

      <div class="card" *ngIf="partnerId">
        <h3>Mes factures</h3>
        <button (click)="loadInvoices()">Actualiser</button>
        <p *ngIf="invoicesLoaded && invoices.length===0">Aucune facture pour le moment.</p>
        <div *ngFor="let inv of invoices" style="border-top:1px solid #e5e7eb;padding:8px 0">
          <strong>{{money(inv.total_minor,inv.currency)}}</strong> — {{invoiceStatusLabel(inv.status)}}
          <div>Période : {{dateTime(inv.period_start)}} → {{dateTime(inv.period_end)}}</div>
          <div *ngIf="inv.due_at">Échéance : {{dateTime(inv.due_at)}}</div>
        </div>
      </div>
    </div>
  `
})
export class Partner implements OnInit{
  // Angular templates ne voient que les membres de l'instance -- on
  // expose donc les fonctions importées telles quelles plutôt que
  // d'écrire des wrappers redondants.
  statusLabel=statusLabel;
  paymentMethodLabel=paymentMethodLabel;
  partnerOrgStatusLabel=partnerOrgStatusLabel;
  invoiceStatusLabel=invoiceStatusLabel;
  money=money;
  dateTime=dateTime;

  name='';type='HOTEL';billingEmail='';
  partnerId=localStorage.getItem('partnerId')||'';
  organizations:any[]=[];
  selectedOrganizationId='';
  loading=false;message='';

  guestName='';guestPhone='';
  pickupText='';dropoffText='';
  pickup:any=null;dropoff:any=null;
  pickupSuggestions:any[]=[];dropoffSuggestions:any[]=[];
  scheduledAt='';categoryId='';paymentMethod='CASH';passengerCount=1;baggageCount=0;
  offerVisibilityMode='';
  categories:any[]=[];bookings:any[]=[];offers:any[]=[];
  selectedBookingId='';
  accepting=false;acceptError='';
  finance:any=null;
  publishing=false;publishMessage='';

  newBeneficiaryName='';newBeneficiaryPhone='';newBeneficiaryEmail='';
  creatingBeneficiary=false;beneficiaryMessage='';
  beneficiaries:any[]=[];beneficiariesLoaded=false;

  invoices:any[]=[];invoicesLoaded=false;

  constructor(private api:Api){}

  async ngOnInit(){
    try{this.categories=await this.api.vehicleCategories();}catch{}
    await this.loadOrganizations();
    if(this.partnerId){
      const stillMember=this.organizations.some(o=>o.id===this.partnerId);
      if(!stillMember)this.partnerId='';
    }
    if(!this.partnerId&&this.organizations.length===1){
      this.partnerId=this.organizations[0].id;
      localStorage.setItem('partnerId',this.partnerId);
    }
    if(this.partnerId)await this.loadBookings();
  }

  async loadOrganizations(){
    try{this.organizations=await this.api.partnerOrganizations();}catch{this.organizations=[];}
  }

  async useOrganization(){
    if(!this.selectedOrganizationId)return;
    this.partnerId=this.selectedOrganizationId;
    localStorage.setItem('partnerId',this.partnerId);
    this.selectedOrganizationId='';
    await this.loadBookings();
  }

  async createPartner(){
    if(!this.name.trim())return;
    this.loading=true;this.message='';
    try{
      const r=await this.api.createPartner({name:this.name,partnerType:this.type,billingEmail:this.billingEmail});
      this.partnerId=r.partnerId;
      localStorage.setItem('partnerId',this.partnerId);
      await this.loadOrganizations();
      this.message='Compte partenaire créé. Validation Veyra requise avant PARTNER_INVOICE.';
    }catch{this.message='Création impossible.';}
    finally{this.loading=false;}
  }

  clearPartner(){
    this.partnerId='';localStorage.removeItem('partnerId');this.bookings=[];this.offers=[];this.selectedBookingId='';
  }

  async searchAddress(isPickup:boolean){
    const q=isPickup?this.pickupText:this.dropoffText;
    if(q.trim().length<3){
      if(isPickup)this.pickupSuggestions=[];else this.dropoffSuggestions=[];
      return;
    }
    try{
      const result=await this.api.autocomplete(q);
      if(isPickup)this.pickupSuggestions=result;else this.dropoffSuggestions=result;
    }catch{}
  }

  selectAddress(isPickup:boolean,place:any){
    if(isPickup){
      this.pickup=place;this.pickupText=place.label;this.pickupSuggestions=[];
    }else{
      this.dropoff=place;this.dropoffText=place.label;this.dropoffSuggestions=[];
    }
  }

  async publish(){
    this.publishMessage='';
    if(!this.partnerId||!this.pickup||!this.dropoff||!this.scheduledAt||!this.categoryId||!this.guestName.trim()){
      this.publishMessage='Complétez tous les champs obligatoires.';
      return;
    }
    const date=new Date(this.scheduledAt);
    if(date.getTime()-Date.now()<2*60*60*1000){
      this.publishMessage='Le départ doit être planifié au minimum 2 heures à l’avance.';
      return;
    }
    this.publishing=true;
    try{
      await this.api.createScheduledBooking({
        pickup:{lat:this.pickup.lat,lng:this.pickup.lng,address:this.pickup.label},
        dropoff:{lat:this.dropoff.lat,lng:this.dropoff.lng,address:this.dropoff.label},
        scheduledAt:date.toISOString(),
        categoryId:this.categoryId,
        paymentMethod:this.paymentMethod,
        payerType:this.paymentMethod==='PARTNER_INVOICE'?'PARTNER':'GUEST',
        partnerId:this.partnerId,
        beneficiaryName:this.guestName,
        beneficiaryPhone:this.guestPhone,
        passengerCount:this.passengerCount,
        baggageCount:this.baggageCount,
        ...(this.offerVisibilityMode?{offerVisibilityMode:this.offerVisibilityMode}:{})
      });
      this.publishMessage='Demande publiée. Les chauffeurs éligibles vont être notifiés.';
      await this.loadBookings();
    }catch(e:any){
      this.publishMessage=errorMessage(e?.code);
    }finally{this.publishing=false;}
  }

  async loadBookings(){
    try{this.bookings=await this.api.partnerBookings(this.partnerId);}catch{this.bookings=[];}
  }

  async loadOffers(id:string){
    this.selectedBookingId=id;
    try{this.offers=await this.api.bookingOffers(id);}catch{this.offers=[];}
  }

  async accept(offerId:string){
    if(!this.selectedBookingId||this.accepting)return;
    this.accepting=true;this.acceptError='';
    try{
      await this.api.acceptOffer(this.selectedBookingId,offerId);
      this.offers=[];
      await this.loadBookings();
    }catch(e:any){
      this.acceptError=errorMessage(e?.code);
    }finally{
      this.accepting=false;
    }
  }

  async loadFinance(){
    try{this.finance=await this.api.partnerFinance(this.partnerId);}catch{this.finance={error:'indisponible'};}
  }

  async createBeneficiary(){
    if(!this.partnerId||this.creatingBeneficiary||!this.newBeneficiaryName.trim())return;
    this.creatingBeneficiary=true;this.beneficiaryMessage='';
    try{
      await this.api.createPartnerBeneficiary(this.partnerId,{
        fullName:this.newBeneficiaryName.trim(),
        phone:this.newBeneficiaryPhone.trim()||null,
        email:this.newBeneficiaryEmail.trim()||null,
        externalReference:null,
      });
      this.newBeneficiaryName='';this.newBeneficiaryPhone='';this.newBeneficiaryEmail='';
      this.beneficiaryMessage='Client ajouté.';
      await this.loadBeneficiaries();
    }catch(e:any){
      this.beneficiaryMessage=errorMessage(e?.code);
    }finally{
      this.creatingBeneficiary=false;
    }
  }

  async loadBeneficiaries(){
    if(!this.partnerId)return;
    try{
      this.beneficiaries=await this.api.partnerBeneficiaries(this.partnerId);
    }catch{
      this.beneficiaries=[];
    }finally{
      this.beneficiariesLoaded=true;
    }
  }

  async loadInvoices(){
    if(!this.partnerId)return;
    try{
      this.invoices=await this.api.partnerInvoices(this.partnerId);
    }catch{
      this.invoices=[];
    }finally{
      this.invoicesLoaded=true;
    }
  }
}
