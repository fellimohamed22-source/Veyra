import {CommonModule} from '@angular/common';
import {Component,OnDestroy,OnInit} from '@angular/core';
import {ActivatedRoute} from '@angular/router';
import {Api} from '../api';
import {CardPayment} from '../portal/card-payment';
import {errorMessage, money} from '../formatters';

/**
 * PART-13 / PART-03: public tracking page opened from the passenger's SMS.
 * No account, no phone number; the price only when the passenger pays it
 * through this link (PART-10). Otherwise only what the passenger needs to
 * find the car. Refreshed every 30 s; an unknown, expired or revoked link
 * shows the same message.
 */
@Component({
  standalone:true,
  imports:[CommonModule,CardPayment],
  template:`
    <div class="card" style="max-width:520px;margin:24px auto">
      <h1 style="margin-top:0">VEYRA · Votre trajet</h1>
      <p *ngIf="loading && !trip">Chargement…</p>
      <p *ngIf="invalid">Ce lien de suivi n'est plus valide. Contactez l'établissement qui a réservé votre trajet.</p>
      <p *ngIf="offline">Connexion indisponible. Nouvel essai automatique dans quelques secondes.</p>
      <ng-container *ngIf="trip">
        <p *ngIf="trip.passengerFirstName">Bonjour {{trip.passengerFirstName}},</p>
        <p><strong>{{statusLabel(trip.status)}}</strong></p>
        <p>{{when(trip.scheduledAt)}}</p>
        <p>Départ : {{trip.pickupAddress}}<br>Arrivée : {{trip.dropoffAddress}}</p>
        <div *ngIf="trip.driverFirstName">
          <p>Chauffeur : {{trip.driverFirstName}}<br>
          Véhicule : {{trip.vehicle}}<span *ngIf="trip.vehicleColor"> · {{trip.vehicleColor}}</span><br>
          Immatriculation : <strong>{{trip.plate}}</strong></p>
        </div>
        <p *ngIf="trip.driverLocation">
          <a [href]="mapUrl(trip.driverLocation)" target="_blank" rel="noopener">Voir la position du chauffeur</a>
        </p>
        <div class="stack" *ngIf="trip.payment as pay" style="border-top:1px solid var(--line);padding-top:12px">
          <h3>Paiement de votre course</h3>
          <div class="okbox" *ngIf="pay.paid || paidNow">Course réglée : {{money(pay.amountMinor)}}. Merci !</div>
          <ng-container *ngIf="!pay.paid && !paidNow">
            <p class="sub" style="margin:0">L'établissement vous demande de régler {{money(pay.amountMinor)}} TTC par carte.</p>
            <p class="sub" style="margin:0" *ngIf="!pay.payable">Le paiement s'ouvre dès que votre chauffeur est confirmé.</p>
            <button class="gold" *ngIf="pay.payable && !intent" (click)="startPayment()" [disabled]="starting">{{starting ? 'Préparation…' : 'Payer ma course'}}</button>
            <card-payment *ngIf="intent" [publishableKey]="intent.publishableKey" [clientSecret]="intent.clientSecret" [amountMinor]="pay.amountMinor" (paid)="paidNow = true; intent = null"></card-payment>
            <div class="errbox" *ngIf="payError">{{payError}}</div>
          </ng-container>
        </div>
      </ng-container>
    </div>`
})
export class Guest implements OnInit,OnDestroy{
  money=money;
  trip:any=null;loading=true;invalid=false;offline=false;
  intent:any=null;starting=false;paidNow=false;payError='';

  /** PART-10: the passenger pays with this link; the token is the only credential. */
  async startPayment(){
    this.starting=true;this.payError='';
    const token=this.route.snapshot.paramMap.get('token')||'';
    try{
      const r=await this.api.guestPayment(token);
      if(!r?.publishableKey){this.payError='Le paiement en ligne est momentanément indisponible.';return;}
      this.intent=r;
    }catch(e:any){
      if(e?.code==='ALREADY_PAID'){this.paidNow=true;return;}
      this.payError=errorMessage(e?.code);
    }finally{this.starting=false;}
  }
  private timer:any;
  constructor(private route:ActivatedRoute,private api:Api){}

  ngOnInit(){
    this.load();
    this.timer=setInterval(()=>this.load(),30000);
  }

  ngOnDestroy(){clearInterval(this.timer);}

  async load(){
    const token=this.route.snapshot.paramMap.get('token')||'';
    try{
      const response=await fetch(this.api.base+'/guest/bookings/'+encodeURIComponent(token));
      this.offline=false;
      if(response.status===404||response.status===400){this.invalid=true;this.trip=null;clearInterval(this.timer);return;}
      if(!response.ok)throw new Error(String(response.status));
      this.trip=await response.json();
    }catch{
      this.offline=true;
    }finally{
      this.loading=false;
    }
  }

  statusLabel(status:string):string{
    const labels:Record<string,string>={
      OPEN_FOR_OFFERS:'Nous recherchons votre chauffeur.',
      OFFERS_RECEIVED:'Nous recherchons votre chauffeur.',
      CONFIRMED:'Votre chauffeur est confirmé.',
      DRIVER_EN_ROUTE:'Votre chauffeur est en route.',
      DRIVER_ARRIVED:'Votre chauffeur est arrivé au point de départ.',
      IN_PROGRESS:'Course en cours.',
      COMPLETED:'Course terminée. Merci d\'avoir voyagé avec VEYRA.',
      CANCELLED:'Ce trajet a été annulé.'
    };
    return labels[status]||'Suivi de votre trajet.';
  }

  when(value:string):string{
    // Europe/Paris explicitly: the passenger reads local pickup time.
    return new Intl.DateTimeFormat('fr-FR',{weekday:'long',day:'numeric',month:'long',hour:'2-digit',minute:'2-digit',timeZone:'Europe/Paris'}).format(new Date(value));
  }

  mapUrl(loc:{lat:number;lng:number}):string{
    return 'https://www.google.com/maps?q='+loc.lat+','+loc.lng;
  }
}
