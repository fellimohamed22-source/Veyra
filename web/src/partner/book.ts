import {CommonModule} from '@angular/common';
import {Component, OnInit} from '@angular/core';
import {FormsModule} from '@angular/forms';
import {Router} from '@angular/router';
import {Api} from '../api';
import {PartnerContext} from './context';
import {errorMessage, money} from '../formatters';

type Payer = 'ESTABLISHMENT' | 'PASSENGER' | 'INVOICE';

/**
 * Réserver pour un client (PART-07..11, maquette validée) : passager,
 * trajet, véhicule, payeur, récapitulatif. Le passager n'a pas besoin de
 * compte ; la commission de l'établissement s'applique.
 */
@Component({
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="mhead"><div><h1>Réserver pour un client</h1><div class="sub">Le passager n'a pas besoin de compte VEYRA.</div></div></div>
    <div class="steps">
      <span *ngFor="let s of stepNames; let i = index" class="step" [class.on]="i === step" [class.done]="i < step">{{i + 1}} {{s}}</span>
    </div>

    <div class="grid2">
      <div class="card">
        <ng-container [ngSwitch]="step">
          <ng-container *ngSwitchCase="0">
            <h3>Passager</h3>
            <div class="field" *ngIf="saved.length">
              <label for="saved">Passager enregistré (facultatif)</label>
              <select id="saved" [(ngModel)]="savedId" (ngModelChange)="pickSaved()">
                <option value="">— Nouveau passager —</option>
                <option *ngFor="let p of saved" [value]="p.id">{{p.full_name}}</option>
              </select>
            </div>
            <div class="field"><label for="g-name">Nom du passager</label><input id="g-name" [(ngModel)]="guestName" placeholder="Ex. M. Dubois"></div>
            <div class="field"><label for="g-phone">Téléphone du passager</label><input id="g-phone" [(ngModel)]="guestPhone" placeholder="+33 6 12 34 56 78"></div>
            <div class="note">Le passager reçoit par SMS un lien de suivi, sans numéro personnel du chauffeur.</div>
          </ng-container>

          <ng-container *ngSwitchCase="1">
            <h3>Trajet</h3>
            <div class="field"><label for="from">Départ</label>
              <input id="from" [(ngModel)]="pickupText" (input)="search(true)" placeholder="Adresse de départ" autocomplete="off">
              <div class="suggest" *ngIf="pickupSuggestions.length"><button type="button" *ngFor="let p of pickupSuggestions" (click)="choose(true, p)">{{p.label}}</button></div>
            </div>
            <div class="field"><label for="to">Destination</label>
              <input id="to" [(ngModel)]="dropoffText" (input)="search(false)" placeholder="Destination" autocomplete="off">
              <div class="suggest" *ngIf="dropoffSuggestions.length"><button type="button" *ngFor="let p of dropoffSuggestions" (click)="choose(false, p)">{{p.label}}</button></div>
            </div>
            <div class="field"><label for="at">Date et heure de prise en charge</label><input id="at" type="datetime-local" [(ngModel)]="scheduledAt"></div>
          </ng-container>

          <ng-container *ngSwitchCase="2">
            <h3>Véhicule</h3>
            <div class="field"><label for="cat">Catégorie</label>
              <select id="cat" [(ngModel)]="categoryId">
                <option value="">Choisir une catégorie</option>
                <option *ngFor="let c of categories" [value]="c.id">{{c.display_name}}{{c.capacity ? ' · ' + c.capacity + ' places' : ''}}</option>
              </select></div>
            <div class="grid2">
              <div class="field"><label for="pax">Passagers</label><input id="pax" type="number" min="1" max="9" [(ngModel)]="passengerCount"></div>
              <div class="field"><label for="bags">Bagages</label><input id="bags" type="number" min="0" max="12" [(ngModel)]="baggageCount"></div>
            </div>
          </ng-container>

          <ng-container *ngSwitchCase="3">
            <h3>Qui paie la course ?</h3>
            <div class="seg" role="radiogroup" aria-label="Payeur">
              <button type="button" [class.on]="payer === 'ESTABLISHMENT'" (click)="payer = 'ESTABLISHMENT'">L'établissement</button>
              <button type="button" [class.on]="payer === 'PASSENGER'" (click)="payer = 'PASSENGER'">Le passager (lien sécurisé)</button>
              <button type="button" *ngIf="creditOpen" [class.on]="payer === 'INVOICE'" (click)="payer = 'INVOICE'">Facture mensuelle</button>
            </div>
            <div class="note" *ngIf="payer === 'ESTABLISHMENT'">« L'établissement » : la course est réglée en ligne par l'établissement au moment de la réservation (DEC-04).</div>
            <div class="warnbox" *ngIf="payer === 'PASSENGER'">« Le passager » : il reçoit un lien sécurisé pour payer lui-même. La réception ne saisit jamais sa carte.</div>
            <div class="warnbox" *ngIf="creditOpen && payer === 'INVOICE'">« Facture mensuelle » : la course est ajoutée à la facture du mois{{creditLeft !== null ? ' (plafond restant : ' + money(creditLeft) + ')' : ''}}.</div>
            <div class="sub" *ngIf="!creditOpen">« Facture mensuelle » apparaît quand VEYRA a accordé un crédit à l'établissement.</div>
          </ng-container>

          <ng-container *ngSwitchCase="4">
            <h3>Récapitulatif</h3>
            <div class="route"><b>{{guestName}}<span *ngIf="guestPhone"> · {{guestPhone}}</span></b><span class="sub">Passager sans compte VEYRA</span></div>
            <div class="route"><b>{{short(pickupText)}} → {{short(dropoffText)}}</b>
              <span class="sub">{{prettyDate}} · {{categoryName}} · {{passengerCount}} passager{{passengerCount > 1 ? 's' : ''}} · {{baggageCount}} bagage{{baggageCount > 1 ? 's' : ''}}</span></div>
            <div class="route"><b>{{payerLabel}}</b><span class="sub">Payeur</span></div>
            <div class="field"><label for="note">Note pour le chauffeur</label><textarea id="note" rows="2" maxlength="1000" [(ngModel)]="notes" placeholder="Ex. client avec poussette, attendre au lobby."></textarea></div>
            <div class="field"><label for="ref">Référence interne (facultatif)</label><input id="ref" maxlength="100" [(ngModel)]="reference" placeholder="Ex. dossier 2026-1018-214"></div>
          </ng-container>
        </ng-container>

        <div class="errbox" *ngIf="error">{{error}}</div>
        <div class="row between">
          <button class="ghost" type="button" (click)="back()" [disabled]="step === 0 || publishing">Retour</button>
          <button *ngIf="step < 4" type="button" (click)="next()">Continuer</button>
          <button *ngIf="step === 4" class="gold" type="button" (click)="publish()" [disabled]="publishing">{{publishing ? 'Publication…' : 'Publier la demande'}}</button>
        </div>
      </div>

      <div class="card">
        <h3>Comment ça marche</h3>
        <div class="stack sub">
          <div>1. Les chauffeurs vérifiés de la catégorie proposent leur prix.</div>
          <div>2. Vous comparez les offres : le prix affiché est final, commission comprise.</div>
          <div>3. Vous choisissez librement : rien n'est choisi automatiquement.</div>
          <div>4. Le passager reçoit un lien de suivi par SMS.</div>
        </div>
        <div class="note">La réservation appartient à l'établissement : c'est son taux de commission qui s'applique, même si le passager paie.</div>
      </div>
    </div>`
})
export class PartnerBook implements OnInit {
  money = money;
  stepNames = ['Passager', 'Trajet', 'Véhicule', 'Payeur', 'Récapitulatif'];
  step = 0;
  saved: any[] = []; savedId = '';
  guestName = ''; guestPhone = '';
  pickupText = ''; dropoffText = ''; pickup: any = null; dropoff: any = null;
  pickupSuggestions: any[] = []; dropoffSuggestions: any[] = [];
  scheduledAt = '';
  categories: any[] = []; categoryId = ''; passengerCount = 1; baggageCount = 0;
  payer: Payer = 'ESTABLISHMENT';
  creditOpen = false; creditLeft: number | null = null;
  notes = ''; reference = '';
  error = ''; publishing = false;

  constructor(private api: Api, private ctx: PartnerContext, private router: Router) {}

  async ngOnInit() {
    try { this.categories = await this.api.vehicleCategories(); } catch {}
    try { this.saved = await this.api.partnerBeneficiaries(this.ctx.partnerId); } catch {}
    this.creditOpen = this.ctx.current?.credit_status === 'APPROVED';
    if (this.creditOpen && this.ctx.seesFinance) {
      try {
        const f = await this.api.partnerFinance(this.ctx.partnerId);
        this.creditLeft = (f.credit_limit_minor || 0) - (f.outstanding_minor || 0);
      } catch {}
    }
  }

  pickSaved() {
    const p = this.saved.find(s => s.id === this.savedId);
    if (p) { this.guestName = p.full_name; this.guestPhone = p.phone || ''; }
  }

  async search(isPickup: boolean) {
    const q = isPickup ? this.pickupText : this.dropoffText;
    if (isPickup) this.pickup = null; else this.dropoff = null;
    if (q.trim().length < 3) { if (isPickup) this.pickupSuggestions = []; else this.dropoffSuggestions = []; return; }
    try {
      const r = await this.api.autocomplete(q);
      if ((isPickup ? this.pickupText : this.dropoffText) !== q) return;
      if (isPickup) this.pickupSuggestions = r; else this.dropoffSuggestions = r;
    } catch {}
  }

  choose(isPickup: boolean, p: any) {
    if (isPickup) { this.pickup = p; this.pickupText = p.label; this.pickupSuggestions = []; }
    else { this.dropoff = p; this.dropoffText = p.label; this.dropoffSuggestions = []; }
  }

  get categoryName() { return this.categories.find(c => c.id === this.categoryId)?.display_name || ''; }
  get prettyDate() { return this.scheduledAt ? new Date(this.scheduledAt).toLocaleString('fr-FR', {weekday: 'long', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit'}) : ''; }
  get payerLabel() { return {ESTABLISHMENT: 'L’établissement (paiement en ligne)', PASSENGER: 'Le passager (lien sécurisé)', INVOICE: 'Facture mensuelle'}[this.payer]; }
  short(a: string) { return (a || '').split(',')[0]; }

  validate(): string {
    if (this.step === 0 && !this.guestName.trim()) return 'Indiquez le nom du passager.';
    if (this.step === 0 && this.payer === 'PASSENGER' && !this.guestPhone.trim()) return '';
    if (this.step === 1) {
      if (!this.pickup || !this.dropoff) return 'Choisissez le départ et la destination dans les suggestions.';
      if (!this.scheduledAt) return 'Indiquez la date et l’heure de prise en charge.';
      if (new Date(this.scheduledAt).getTime() - Date.now() < 2 * 3600000) return 'La prise en charge doit être prévue au moins 2 heures à l’avance.';
    }
    if (this.step === 2) {
      if (!this.categoryId) return 'Choisissez une catégorie de véhicule.';
      const cap = this.categories.find(c => c.id === this.categoryId)?.capacity;
      if (cap && this.passengerCount > cap) return `Cette catégorie accueille jusqu’à ${cap} passagers.`;
    }
    if (this.step === 3 && this.payer === 'PASSENGER' && !this.guestPhone.trim()) return 'Le paiement par le passager nécessite son téléphone (lien envoyé par SMS).';
    return '';
  }

  next() { this.error = this.validate(); if (!this.error) this.step++; }
  back() { this.error = ''; if (this.step > 0) this.step--; }

  async publish() {
    this.publishing = true; this.error = '';
    const payment = this.payer === 'INVOICE'
      ? {paymentMethod: 'PARTNER_INVOICE', payerType: 'PARTNER'}
      : this.payer === 'PASSENGER' ? {paymentMethod: 'ONLINE', payerType: 'GUEST'} : {paymentMethod: 'ONLINE', payerType: 'PARTNER'};
    try {
      const created = await this.api.createScheduledBooking({
        pickup: {lat: this.pickup.lat, lng: this.pickup.lng, address: this.pickup.label},
        dropoff: {lat: this.dropoff.lat, lng: this.dropoff.lng, address: this.dropoff.label},
        scheduledAt: new Date(this.scheduledAt).toISOString(),
        categoryId: this.categoryId,
        ...payment,
        partnerId: this.ctx.partnerId,
        beneficiaryName: this.guestName.trim(),
        beneficiaryPhone: this.guestPhone.trim() || null,
        passengerCount: this.passengerCount,
        baggageCount: this.baggageCount,
        customerNotes: this.notes.trim() || null,
        partnerReference: this.reference.trim() || null,
      });
      await this.router.navigate(['/partner/reservations', created.id], {queryParams: {publiee: 1}});
    } catch (e: any) { this.error = errorMessage(e?.code); }
    finally { this.publishing = false; }
  }
}
