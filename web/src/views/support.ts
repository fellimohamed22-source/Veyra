import {CommonModule} from '@angular/common';
import {Component} from '@angular/core';
import {FormsModule} from '@angular/forms';
import {Api} from '../api';

@Component({
  standalone:true,
  imports:[CommonModule,FormsModule],
  template:`
    <h1>Support</h1>
    <div class="card">
      <h3>Recherche réservation</h3>
      <input [(ngModel)]="bookingId" placeholder="UUID réservation">
      <button (click)="search()" [disabled]="loading">Rechercher</button>
      <p *ngIf="error">{{error}}</p>
    </div>
    <div class="card" *ngIf="result">
      <h3>Détail</h3>
      <pre style="white-space:pre-wrap">{{result | json}}</pre>
    </div>`
})
export class Support{
  bookingId='';result:any=null;loading=false;error='';
  constructor(private api:Api){}
  async search(){
    if(!this.bookingId.trim())return;
    this.loading=true;this.error='';
    try{this.result=await this.api.supportTimeline(this.bookingId.trim());}
    catch{this.result=null;this.error='Réservation introuvable ou accès refusé.';}
    finally{this.loading=false;}
  }
}
