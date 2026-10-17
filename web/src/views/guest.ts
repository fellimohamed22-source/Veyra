import {CommonModule} from '@angular/common';
import {Component,OnDestroy,OnInit} from '@angular/core';
import {ActivatedRoute} from '@angular/router';
import {Api} from '../api';

/**
 * PART-13 / PART-03: public tracking page opened from the passenger's SMS.
 * No account, no phone number, no price: only what the passenger needs to
 * find the car. Refreshed every 30 s; an unknown, expired or revoked link
 * shows the same message.
 */
@Component({
  standalone:true,
  imports:[CommonModule],
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
      </ng-container>
    </div>`
})
export class Guest implements OnInit,OnDestroy{
  trip:any=null;loading=true;invalid=false;offline=false;
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
