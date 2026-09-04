import {CommonModule} from '@angular/common';
import {Component,OnInit} from '@angular/core';
import {Api} from '../api';

@Component({
  standalone:true,
  imports:[CommonModule],
  template:`
    <h1>Administration Veyra</h1>
    <div *ngIf="loading" class="card">Chargement…</div>
    <div *ngIf="error" class="card">{{error}} <button (click)="load()">Réessayer</button></div>
    <div class="grid" *ngIf="dashboard">
      <div class="card"><h3>Réservations</h3><strong>{{dashboard.bookings}}</strong></div>
      <div class="card"><h3>KYC Chauffeurs en attente</h3><strong>{{dashboard.pendingDrivers||dashboard.driversPendingKyc}}</strong></div>
      <div class="card"><h3>Partenaires en attente</h3><strong>{{dashboard.pendingPartners||dashboard.partnersPending}}</strong></div>
    </div>
    <div class="card">
      <h3>Réservations récentes</h3>
      <p *ngIf="!loading && bookings.length===0">Aucune réservation.</p>
      <table *ngIf="bookings.length" style="width:100%;border-collapse:collapse">
        <thead><tr><th>ID</th><th>Date</th><th>Statut</th><th>Paiement</th></tr></thead>
        <tbody><tr *ngFor="let b of bookings">
          <td>{{b.id}}</td><td>{{b.scheduled_at}}</td><td>{{b.status}}</td><td>{{b.payment_method}}</td>
        </tr></tbody>
      </table>
    </div>`
})
export class Admin implements OnInit{
  dashboard:any=null;bookings:any[]=[];loading=false;error='';
  constructor(private api:Api){}
  ngOnInit(){this.load();}
  async load(){
    this.loading=true;this.error='';
    try{
      this.dashboard=await this.api.adminDashboard();
      this.bookings=await this.api.adminBookings();
    }catch{this.error='Impossible de charger le back-office.';}
    finally{this.loading=false;}
  }
}
