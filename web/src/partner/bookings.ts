import {CommonModule} from '@angular/common';
import {Component, OnInit} from '@angular/core';
import {FormsModule} from '@angular/forms';
import {RouterLink} from '@angular/router';
import {Api} from '../api';
import {PartnerContext} from './context';
import {money, when} from '../formatters';
import {bookingPill} from './pills';

/** Réservations de l'établissement : à venir, à traiter, passées. */
@Component({
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink],
  template: `
    <div class="mhead">
      <div><h1>Réservations</h1><div class="sub">{{filtered.length}} réservation{{filtered.length > 1 ? 's' : ''}}</div></div>
      <button class="gold" *ngIf="ctx.books" routerLink="/partner/reserver">+ Réserver pour un client</button>
    </div>
    <div class="row between">
      <div class="seg" role="tablist">
        <button *ngFor="let t of tabs" type="button" [class.on]="tab === t.key" (click)="tab = t.key">{{t.label}}</button>
      </div>
      <input style="max-width:280px" [(ngModel)]="query" placeholder="Rechercher un passager, une adresse…" aria-label="Rechercher">
    </div>
    <p class="empty" *ngIf="loaded && !filtered.length">Aucune réservation.</p>
    <div class="tablewrap" *ngIf="filtered.length">
      <table>
        <thead><tr><th>Prise en charge</th><th>Passager</th><th>Trajet</th><th>Montant</th><th>Statut</th><th></th></tr></thead>
        <tbody>
          <tr *ngFor="let b of filtered">
            <td>{{when(b.scheduled_at)}}</td>
            <td>{{b.beneficiary_name_snapshot || '—'}}<div class="sub" *ngIf="b.partner_reference">{{b.partner_reference}}</div></td>
            <td><div class="route"><b>{{short(b.pickup_address)}} → {{short(b.dropoff_address)}}</b><span class="sub">{{b.category_name}} · {{b.passenger_count}} pass. · {{b.baggage_count}} bag.</span></div></td>
            <td>{{b.customer_total_amount_minor ? money(b.customer_total_amount_minor) : (b.best_offer_total_minor ? 'dès ' + money(b.best_offer_total_minor) : '—')}}</td>
            <td><span class="pill" [ngClass]="pill(b).css">{{pill(b).text}}</span></td>
            <td><button [class.ghost]="!(b.offer_count > 0)" [routerLink]="['/partner/reservations', b.id]">{{b.offer_count > 0 ? 'Comparer' : 'Voir'}}</button></td>
          </tr>
        </tbody>
      </table>
    </div>`
})
export class PartnerBookings implements OnInit {
  money = money; when = when; pill = bookingPill;
  tabs = [{key: 'upcoming', label: 'À venir'}, {key: 'todo', label: 'À traiter'}, {key: 'past', label: 'Passées'}];
  tab = 'upcoming'; query = ''; loaded = false;
  bookings: any[] = [];

  constructor(public ctx: PartnerContext, private api: Api) {}

  async ngOnInit() {
    try { this.bookings = await this.api.partnerBookings(this.ctx.partnerId); } catch { this.bookings = []; }
    this.loaded = true;
  }

  get filtered() {
    const now = Date.now() - 3 * 3600000;
    const q = this.query.trim().toLowerCase();
    const active = ['OPEN_FOR_OFFERS', 'OFFERS_RECEIVED', 'PENDING_PAYMENT', 'CONFIRMED', 'DRIVER_EN_ROUTE', 'DRIVER_ARRIVED', 'IN_PROGRESS'];
    return this.bookings.filter(b => {
      const t = new Date(b.scheduled_at).getTime();
      const inTab = this.tab === 'todo' ? b.offer_count > 0 || b.status === 'PENDING_PAYMENT'
        : this.tab === 'upcoming' ? t >= now && active.includes(b.status)
        : !active.includes(b.status) || t < now;
      const text = `${b.beneficiary_name_snapshot || ''} ${b.pickup_address} ${b.dropoff_address} ${b.partner_reference || ''}`.toLowerCase();
      return inTab && (!q || text.includes(q));
    }).sort((a, b) => this.tab === 'past'
      ? new Date(b.scheduled_at).getTime() - new Date(a.scheduled_at).getTime()
      : new Date(a.scheduled_at).getTime() - new Date(b.scheduled_at).getTime());
  }

  short(a: string) { return (a || '').split(',')[0]; }
}
