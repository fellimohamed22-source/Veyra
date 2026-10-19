import {CommonModule} from '@angular/common';
import {Component, Input, OnInit} from '@angular/core';
import {RouterLink} from '@angular/router';
import {Api} from '../api';
import {PartnerContext} from './context';
import {dateTime, errorMessage, money, statusLabel, when} from '../formatters';
import {bookingPill} from './pills';

/**
 * Détail d'une réservation partenaire : comparer et choisir une offre
 * (PART-12, même logique que l'écran client, rien n'est choisi
 * automatiquement), puis suivi, lien passager (PART-13) et annulation.
 */
@Component({
  standalone: true,
  imports: [CommonModule, RouterLink],
  template: `
    <p class="sub"><a routerLink="/partner/reservations">← Réservations</a></p>
    <div class="okbox" *ngIf="justPublished">Demande publiée. Les chauffeurs vérifiés de la catégorie vont proposer leur prix.</div>
    <p class="sub" *ngIf="!b && !error">Chargement…</p>
    <div class="errbox" *ngIf="error">{{error}}</div>

    <ng-container *ngIf="b">
      <div class="mhead">
        <div><h1>{{b.beneficiary_name_snapshot || 'Réservation'}}</h1>
          <div class="sub">{{short(b.pickup_address)}} → {{short(b.dropoff_address)}} · {{when(b.scheduled_at)}}<span *ngIf="offerPhase && b.offer_window_ends_at"> · clôture des offres {{when(b.offer_window_ends_at)}}</span></div></div>
        <span class="pill" [ngClass]="pill(b).css">{{pill(b).text}}</span>
      </div>

      <ng-container *ngIf="offerPhase">
        <div class="mhead"><h3>{{offers.length}} offre{{offers.length > 1 ? 's' : ''}} pour {{b.beneficiary_name_snapshot || 'votre client'}}</h3>
          <button class="ghost" (click)="loadOffers()">Actualiser</button></div>
        <p class="empty" *ngIf="!offers.length">Aucune offre pour le moment. Les chauffeurs éligibles ont été prévenus.</p>
        <div class="grid3" *ngIf="offers.length">
          <div class="card" *ngFor="let o of offers; let i = index">
            <div class="offer">
              <div class="av">{{initials(o)}}</div>
              <div><b>{{o.driverFirstName}} {{o.driverLastName}}</b><div class="sub">★ {{rating(o.rating)}} · {{o.vehicleBrand}} {{o.vehicleModel}}</div></div>
              <div class="price">{{money(o.totalMinor)}}<small>TTC</small></div>
            </div>
            <div class="row">
              <span class="pill p-ok" *ngIf="i === 0">Meilleur prix</span>
              <span class="pill p-mute" *ngIf="o.vehicleCategory">{{o.vehicleCategory}}</span>
              <span class="pill p-mute" *ngIf="o.vehicleSeats">{{o.vehicleSeats}} places</span>
            </div>
            <div class="sub" *ngIf="o.driverMessage">« {{o.driverMessage}} »</div>
            <button [class.gold]="i === 0" [class.ghost]="i !== 0" (click)="accept(o)" [disabled]="accepting || !ctx.books">{{accepting === o.offerId ? 'Sélection…' : 'Choisir ce chauffeur'}}</button>
          </div>
        </div>
        <div class="note" *ngIf="offers.length">Prix TTC = prix net du chauffeur + commission de l'établissement{{rateText}}. Exemple : {{money(offers[0].driverPriceMinor)}} + {{money(offers[0].commissionMinor)}} = {{money(offers[0].totalMinor)}}.</div>
      </ng-container>

      <div class="grid2">
        <div class="card">
          <h3>Course</h3>
          <div class="route"><b>{{b.pickup_address}}</b><span class="sub">Départ</span></div>
          <div class="route"><b>{{b.dropoff_address}}</b><span class="sub">Destination</span></div>
          <div class="sub">{{dateTime(b.scheduled_at)}} · {{b.category_name}} · {{b.passenger_count}} passager(s) · {{b.baggage_count}} bagage(s)</div>
          <div class="sub" *ngIf="b.customer_notes">Note : {{b.customer_notes}}</div>
          <div class="sub" *ngIf="b.customer_total_amount_minor">Total : <b>{{money(b.customer_total_amount_minor)}}</b> TTC</div>
        </div>
        <div class="card">
          <h3>Chauffeur</h3>
          <p class="sub" *ngIf="!b.selected_driver_id">Aucun chauffeur choisi pour le moment.</p>
          <ng-container *ngIf="b.selected_driver_id">
            <div class="offer"><div class="av">{{(b.driver_first_name || '?')[0]}}{{(b.driver_last_name || '')[0] || ''}}</div>
              <div><b>{{b.driver_first_name}} {{b.driver_last_name}}</b><div class="sub">★ {{rating(b.driver_rating)}} · {{b.vehicle_brand}} {{b.vehicle_model}} · {{b.plate_number}}</div></div><div></div></div>
            <div class="row">
              <button class="ghost" (click)="locate()">Position du chauffeur</button>
              <a *ngIf="location?.available" [href]="'https://www.google.com/maps?q=' + location.lat + ',' + location.lng" target="_blank" rel="noopener">Ouvrir la carte ({{dateTime(location.recorded_at)}})</a>
              <span class="sub" *ngIf="location && !location.available">Position non disponible pour le moment.</span>
            </div>
          </ng-container>
          <ng-container *ngIf="b.selected_driver_id && active">
            <h3>Lien de suivi du passager</h3>
            <div class="row">
              <button class="ghost" (click)="link(true)" [disabled]="linking || !b.beneficiary_phone_snapshot">Envoyer par SMS</button>
              <button class="ghost" (click)="link(false)" [disabled]="linking">Créer le lien</button>
            </div>
            <div class="okbox" *ngIf="guestUrl">Lien : <span class="mono">{{guestUrl}}</span><span *ngIf="smsSent"> · SMS envoyé</span></div>
          </ng-container>
        </div>
      </div>

      <div class="card">
        <h3>Historique</h3>
        <p class="empty" *ngIf="!timeline.length">Aucun évènement pour le moment.</p>
        <div class="row between" *ngFor="let h of timeline"><span>{{statusLabel(h.to_status)}}</span><span class="sub">{{dateTime(h.created_at)}}</span></div>
      </div>

      <div class="row" *ngIf="cancellable && ctx.books">
        <button class="danger" (click)="cancel()" [disabled]="cancelling">{{cancelling ? 'Annulation…' : 'Annuler cette réservation'}}</button>
      </div>
      <div class="okbox" *ngIf="message">{{message}}</div>
    </ng-container>`
})
export class PartnerBookingDetail implements OnInit {
  money = money; when = when; dateTime = dateTime; statusLabel = statusLabel; pill = bookingPill;
  @Input() id = '';
  @Input() publiee = '';
  b: any = null; offers: any[] = []; timeline: any[] = []; location: any = null;
  error = ''; message = ''; accepting = ''; cancelling = false; linking = false; guestUrl = ''; smsSent = false;

  constructor(public ctx: PartnerContext, private api: Api) {}

  get justPublished() { return !!this.publiee; }
  get offerPhase() { return this.b && ['OPEN_FOR_OFFERS', 'OFFERS_RECEIVED'].includes(this.b.status); }
  get active() { return this.b && ['CONFIRMED', 'DRIVER_EN_ROUTE', 'DRIVER_ARRIVED', 'IN_PROGRESS'].includes(this.b.status); }
  get cancellable() { return this.b && ['OPEN_FOR_OFFERS', 'OFFERS_RECEIVED', 'PENDING_PAYMENT', 'CONFIRMED', 'DRIVER_EN_ROUTE', 'DRIVER_ARRIVED'].includes(this.b.status); }
  get rateText() { const bps = this.offers[0]?.commissionRateBps; return bps ? ` (ici ${(bps / 100).toLocaleString('fr-FR')} %)` : ''; }

  async ngOnInit() { await this.load(); }

  async load() {
    this.error = '';
    try {
      this.b = await this.api.bookingDetail(this.id);
      try { this.timeline = await this.api.bookingTimeline(this.id); } catch { this.timeline = []; }
      if (this.offerPhase) await this.loadOffers();
    } catch (e: any) { this.error = errorMessage(e?.code); }
  }

  async loadOffers() {
    try { this.offers = await this.api.bookingOffers(this.id); } catch { this.offers = []; }
  }

  async accept(o: any) {
    this.accepting = o.offerId; this.error = '';
    try { await this.api.acceptOffer(this.id, o.offerId); this.offers = []; await this.load(); this.message = 'Chauffeur choisi.'; }
    catch (e: any) { this.error = errorMessage(e?.code); }
    finally { this.accepting = ''; }
  }

  async locate() {
    try { this.location = await this.api.bookingLocation(this.id); } catch { this.location = {available: false}; }
  }

  async link(sms: boolean) {
    this.linking = true; this.error = '';
    try { const r = await this.api.guestLink(this.ctx.partnerId, this.id, sms); this.guestUrl = r.url; this.smsSent = !!r.smsSent; }
    catch (e: any) { this.error = errorMessage(e?.code); }
    finally { this.linking = false; }
  }

  async cancel() {
    this.cancelling = true; this.error = '';
    try {
      const r = await this.api.cancelBooking(this.id);
      this.message = r?.cancellationFeeMinor ? 'Réservation annulée. Frais : ' + money(r.cancellationFeeMinor) : 'Réservation annulée.';
      await this.load();
    } catch (e: any) { this.error = errorMessage(e?.code); }
    finally { this.cancelling = false; }
  }

  initials(o: any) { return `${(o.driverFirstName || '?')[0]}${(o.driverLastName || '')[0] || ''}`.toUpperCase(); }
  rating(r: any) { const n = Number(r); return n ? n.toLocaleString('fr-FR', {minimumFractionDigits: 1, maximumFractionDigits: 1}) : 'Nouveau'; }
  short(a: string) { return (a || '').split(',')[0]; }
}
