import {CommonModule} from '@angular/common';
import {Component,OnInit} from '@angular/core';
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
        <h3>Compte partenaire</h3>
        <ng-container *ngIf="!partnerId; else existing">
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

        <select [(ngModel)]="paymentMethod">
          <option value="CASH">Client paie Cash</option>
          <option value="ONLINE">Client/partenaire paie en ligne</option>
          <option value="PARTNER_INVOICE">Facture partenaire</option>
        </select>

        <button (click)="publish()" [disabled]="publishing">{{publishing?'Publication…':'Publier la demande'}}</button>
        <p *ngIf="publishMessage">{{publishMessage}}</p>
      </div>

      <div class="card" *ngIf="partnerId">
        <h3>Mes réservations</h3>
        <button (click)="loadBookings()">Actualiser</button>
        <p *ngIf="bookings.length===0">Aucune réservation.</p>
        <div *ngFor="let b of bookings" style="border-top:1px solid #e5e7eb;padding:12px 0">
          <strong>{{b.pickup_address}} → {{b.dropoff_address}}</strong>
          <div>{{b.scheduled_at}} • {{b.status}} • {{b.payment_method}}</div>
          <button *ngIf="b.status==='OPEN_FOR_OFFERS'||b.status==='OFFERS_RECEIVED'" (click)="loadOffers(b.id)">Voir les offres</button>
        </div>
      </div>

      <div class="card" *ngIf="selectedBookingId">
        <h3>Offres reçues</h3>
        <p>Le partenaire voit toutes les offres ; les chauffeurs ne voient jamais les offres concurrentes.</p>
        <p *ngIf="offers.length===0">Aucune offre active.</p>
        <div *ngFor="let o of offers" style="border-top:1px solid #e5e7eb;padding:12px 0">
          <strong>{{o.totalMinor/100}} € total</strong>
          <div>Prix chauffeur {{o.driverPriceMinor/100}} € • note {{o.rating}}</div>
          <button (click)="accept(o.offerId)">Choisir ce chauffeur</button>
        </div>
      </div>

      <div class="card" *ngIf="partnerId">
        <h3>PARTNER_INVOICE</h3>
        <p>Activé uniquement après validation Veyra et attribution d’un plafond de crédit.</p>
        <button (click)="loadFinance()">Voir l'encours</button>
        <pre *ngIf="finance">{{finance | json}}</pre>
      </div>
    </div>
  `
})
export class Partner implements OnInit{
  name='';type='HOTEL';billingEmail='';
  partnerId=localStorage.getItem('partnerId')||'';
  loading=false;message='';

  guestName='';guestPhone='';
  pickupText='';dropoffText='';
  pickup:any=null;dropoff:any=null;
  pickupSuggestions:any[]=[];dropoffSuggestions:any[]=[];
  scheduledAt='';categoryId='';paymentMethod='CASH';
  categories:any[]=[];bookings:any[]=[];offers:any[]=[];
  selectedBookingId='';
  finance:any=null;
  publishing=false;publishMessage='';

  constructor(private api:Api){}

  async ngOnInit(){
    try{this.categories=await this.api.vehicleCategories();}catch{}
    if(this.partnerId)await this.loadBookings();
  }

  async createPartner(){
    if(!this.name.trim())return;
    this.loading=true;this.message='';
    try{
      const r=await this.api.createPartner({name:this.name,partnerType:this.type,billingEmail:this.billingEmail});
      this.partnerId=r.partnerId;
      localStorage.setItem('partnerId',this.partnerId);
      this.message='Compte partenaire créé. Validation Veyra requise avant PARTNER_INVOICE.';
    }catch{this.message='Création impossible.';}
    finally{this.loading=false;}
  }

  clearPartner(){
    this.partnerId='';localStorage.removeItem('partnerId');this.bookings=[];this.offers=[];
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
        beneficiaryPhone:this.guestPhone
      });
      this.publishMessage='Demande publiée. Les chauffeurs éligibles vont être notifiés.';
      await this.loadBookings();
    }catch(e:any){
      this.publishMessage='Publication impossible : '+(e?.code||'erreur');
    }finally{this.publishing=false;}
  }

  async loadBookings(){
    try{this.bookings=await this.api.myBookings();}catch{this.bookings=[];}
  }

  async loadOffers(id:string){
    this.selectedBookingId=id;
    try{this.offers=await this.api.bookingOffers(id);}catch{this.offers=[];}
  }

  async accept(offerId:string){
    if(!this.selectedBookingId)return;
    await this.api.acceptOffer(this.selectedBookingId,offerId);
    this.offers=[];
    await this.loadBookings();
  }

  async loadFinance(){
    try{this.finance=await this.api.partnerFinance(this.partnerId);}catch{this.finance={error:'indisponible'};}
  }
}
