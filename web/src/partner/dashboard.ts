import {CommonModule} from '@angular/common';
import {Component, OnInit} from '@angular/core';
import {RouterLink} from '@angular/router';
import {Api} from '../api';
import {PartnerContext} from './context';
import {money, when} from '../formatters';
import {bookingPill} from './pills';

/** Tableau de bord partenaire (PART-06, maquette validée). */
@Component({
  standalone: true,
  imports: [CommonModule, RouterLink],
  template: `
    <div class="mhead">
      <div><h1>Bonjour {{firstName}}</h1><div class="sub">{{today}} · {{todayCount}} prise{{todayCount > 1 ? 's' : ''}} en charge aujourd'hui</div></div>
      <button class="gold" *ngIf="ctx.books" routerLink="/partner/reserver">+ Réserver pour un client</button>
    </div>
    <div class="grid4">
      <div class="card kpi"><div class="n">{{todayCount}}</div><div class="l">Aujourd'hui</div></div>
      <div class="card kpi"><div class="n">{{toCompare}}</div><div class="l">Offres à comparer</div></div>
      <div class="card kpi"><div class="n">{{nextWeek}}</div><div class="l">À venir (7 jours)</div></div>
      <div class="card kpi"><div class="n">{{money(monthSpend)}}</div><div class="l">Dépenses du mois</div></div>
    </div>
    <div class="card">
      <div class="mhead"><h3>À traiter</h3><span class="sub">les offres se clôturent automatiquement</span></div>
      <p class="empty" *ngIf="loaded && !pending.length">Rien à traiter pour le moment.</p>
      <div class="tablewrap" *ngIf="pending.length">
        <table>
          <thead><tr><th>Prise en charge</th><th>Passager</th><th>Trajet</th><th>Statut</th><th></th></tr></thead>
          <tbody>
            <tr *ngFor="let b of pending">
              <td>{{when(b.scheduled_at)}}</td>
              <td>{{b.beneficiary_name_snapshot || '—'}}</td>
              <td><div class="route"><b>{{short(b.pickup_address)}} → {{short(b.dropoff_address)}}</b>
                <span class="sub">{{b.category_name}} · {{b.passenger_count}} pass. · {{b.baggage_count}} bag.</span></div></td>
              <td><span class="pill" [ngClass]="pill(b).css">{{pill(b).text}}</span></td>
              <td>
                <button *ngIf="b.offer_count > 0; else see" [routerLink]="['/partner/reservations', b.id]">Comparer</button>
                <ng-template #see><button class="ghost" [routerLink]="['/partner/reservations', b.id]">{{b.selected_driver_id ? 'Suivre' : 'Voir'}}</button></ng-template>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>`
})
export class PartnerDashboard implements OnInit {
  money = money; when = when; pill = bookingPill;
  firstName = ''; loaded = false;
  bookings: any[] = [];
  today = new Date().toLocaleDateString('fr-FR', {weekday: 'long', day: 'numeric', month: 'long'});

  constructor(public ctx: PartnerContext, private api: Api) {}

  async ngOnInit() {
    try { this.firstName = (await this.api.me()).first_name || ''; } catch {}
    try { this.bookings = await this.api.partnerBookings(this.ctx.partnerId); } catch { this.bookings = []; }
    this.loaded = true;
  }

  private sameDay(raw: string, offset = 0): boolean {
    const d = new Date(raw), t = new Date(); t.setDate(t.getDate() + offset);
    return d.toDateString() === t.toDateString();
  }
  get todayCount() { return this.bookings.filter(b => this.sameDay(b.scheduled_at) && !String(b.status).includes('CANCEL')).length; }
  get toCompare() { return this.bookings.filter(b => b.offer_count > 0).length; }
  get nextWeek() {
    const now = Date.now(), week = now + 7 * 86400000;
    return this.bookings.filter(b => { const t = new Date(b.scheduled_at).getTime(); return t >= now && t <= week && !String(b.status).includes('CANCEL'); }).length;
  }
  get monthSpend() {
    const n = new Date();
    return this.bookings.filter(b => { const d = new Date(b.scheduled_at); return d.getMonth() === n.getMonth() && d.getFullYear() === n.getFullYear(); })
      .reduce((s, b) => s + (b.customer_total_amount_minor || 0), 0);
  }
  /** Today's and upcoming bookings still needing attention or a ride today. */
  get pending() {
    const now = Date.now() - 3 * 3600000;
    return this.bookings
      .filter(b => new Date(b.scheduled_at).getTime() >= now && ['OPEN_FOR_OFFERS', 'OFFERS_RECEIVED', 'PENDING_PAYMENT', 'CONFIRMED', 'DRIVER_EN_ROUTE', 'DRIVER_ARRIVED', 'IN_PROGRESS'].includes(b.status))
      .sort((a, b) => (b.offer_count > 0 ? 1 : 0) - (a.offer_count > 0 ? 1 : 0) || new Date(a.scheduled_at).getTime() - new Date(b.scheduled_at).getTime())
      .slice(0, 8);
  }
  short(a: string) { return (a || '').split(',')[0]; }
}
