import {CommonModule} from '@angular/common';
import {Component, OnInit} from '@angular/core';
import {FormsModule} from '@angular/forms';
import {Api} from '../api';
import {dateTime, errorMessage, money} from '../formatters';

const ACTIONS: Record<string, string> = {
  DRIVER_KYC_APPROVED: 'Chauffeur approuvé', DRIVER_KYC_REJECTED: 'Correction demandée au chauffeur',
  PARTNER_APPROVED: 'Établissement validé', PARTNER_SUSPENDED: 'Établissement suspendu',
  PARTNER_COMMISSION_UPDATED: 'Commission d’établissement modifiée', STANDARD_COMMISSION_UPDATED: 'Commission générale modifiée',
  COMMISSION_RULE_CREATED: 'Règle de commission créée', COMMISSION_RULE_DEACTIVATED: 'Règle de commission désactivée',
  PLATFORM_SETTING_UPDATED: 'Paramètre modifié', CANCELLATION_POLICY_UPDATED: 'Politique d’annulation modifiée',
  OFFER_VISIBILITY_MODE_UPDATED: 'Visibilité des offres modifiée', SUGGESTED_PRICE_GRID_UPDATED: 'Grille de prix conseillés modifiée',
  COMPANY_APPROVED: 'Société VTC approuvée', COMPANY_REJECTED: 'Correction demandée à la société', COMPANY_SUSPENDED: 'Société VTC suspendue',
  COMPANY_VEHICLE_APPROVED: 'Véhicule de flotte approuvé', COMPANY_VEHICLE_REJECTED: 'Véhicule de flotte refusé',
  DRIVER_CASH_DEBT_SETTLED: 'Dette CASH chauffeur réglée', CUSTOMER_CASH_DEBT_SETTLED: 'Créance client réglée',
  DRIVER_PAYABLE_PAID: 'Versement chauffeur effectué', CUSTOMER_NO_SHOW: 'Client absent déclaré', DRIVER_CANCELLED: 'Annulation par le chauffeur',
};

/** Journal d'audit (admin menu of the validated mock-up): who changed what, when. */
@Component({
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="mhead"><div><h1>Journal d'audit</h1><div class="sub">Décisions et modifications sensibles, les plus récentes d'abord.</div></div>
      <input [(ngModel)]="filter" placeholder="Filtrer (action, élément…)" aria-label="Filtrer" style="max-width:280px"></div>
    <div class="errbox" *ngIf="error">{{error}}</div>
    <div class="tablewrap">
      <table>
        <thead><tr><th>Date</th><th>Action</th><th>Élément</th><th>Par</th><th>Détail</th></tr></thead>
        <tbody><tr *ngFor="let l of filtered">
          <td>{{dateTime(l.created_at)}}</td>
          <td><b>{{label(l.action)}}</b></td>
          <td>{{l.entity_type || '—'}}<div class="sub mono" *ngIf="l.entity_id">{{short(l.entity_id)}}</div></td>
          <td>{{l.actor_type || '—'}}</td>
          <td class="sub">{{detail(l.metadata)}}</td>
        </tr></tbody>
      </table>
    </div>
    <p class="empty" *ngIf="loaded && !filtered.length">Aucune entrée.</p>`
})
export class AdminAudit implements OnInit {
  dateTime = dateTime;
  logs: any[] = []; loaded = false; error = ''; filter = '';
  constructor(private api: Api) {}
  async ngOnInit() {
    try { this.logs = await this.api.auditLogs(300); } catch (e: any) { this.error = errorMessage(e?.code); }
    this.loaded = true;
  }
  get filtered() {
    const f = this.filter.trim().toLowerCase();
    return f ? this.logs.filter(l => (this.label(l.action) + ' ' + (l.entity_type || '') + ' ' + JSON.stringify(l.metadata || '')).toLowerCase().includes(f)) : this.logs;
  }
  label(a: string) { return ACTIONS[a] || a; }
  short(id: string) { return String(id).slice(0, 8).toUpperCase(); }
  detail(meta: any) {
    let m = meta;
    if (typeof m === 'string') { try { m = JSON.parse(m); } catch { return m; } }
    if (!m || typeof m !== 'object' || !Object.keys(m).length) return '—';
    if (m.justification) return '« ' + m.justification + ' »';
    return Object.entries(m).filter(([k]) => k !== 'before').map(([k, v]) => k + ' : ' + (typeof v === 'object' ? JSON.stringify(v) : v)).join(' · ').slice(0, 160);
  }
}

/**
 * Prix conseillés (DEC-18): per-category grid in driver net price, empty by
 * default. The driver sees « Prix conseillé (net) » only for a category whose
 * grid is active. Every change needs a justification and is audited.
 */
@Component({
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="mhead"><div><h1>Prix conseillés</h1><div class="sub">Repère affiché au chauffeur, en prix net, par catégorie. Aucun prix n'est imposé ; une catégorie sans grille active n'affiche rien.</div></div></div>
    <div class="errbox" *ngIf="error">{{error}}</div>
    <div class="okbox" *ngIf="message">{{message}}</div>
    <div class="tablewrap">
      <table>
        <thead><tr><th>Catégorie</th><th>Prise en charge (€)</th><th>Par km (€)</th><th>Par minute (€)</th><th>Minimum (€)</th><th>Fourchette ± %</th><th>Active</th><th></th></tr></thead>
        <tbody><tr *ngFor="let r of rows">
          <td><b>{{r.display_name}}</b><div class="sub">{{r.updated_at ? 'modifiée le ' + dateTime(r.updated_at) : 'aucune grille'}}</div></td>
          <td><input type="number" min="0" step="0.01" [(ngModel)]="r.base" style="max-width:90px" [attr.aria-label]="'Prise en charge ' + r.display_name"></td>
          <td><input type="number" min="0" step="0.01" [(ngModel)]="r.perKm" style="max-width:90px" [attr.aria-label]="'Par km ' + r.display_name"></td>
          <td><input type="number" min="0" step="0.01" [(ngModel)]="r.perMinute" style="max-width:90px" [attr.aria-label]="'Par minute ' + r.display_name"></td>
          <td><input type="number" min="0" step="0.01" [(ngModel)]="r.minimum" style="max-width:90px" [attr.aria-label]="'Minimum ' + r.display_name"></td>
          <td><input type="number" min="0" max="50" step="1" [(ngModel)]="r.spread" style="max-width:70px" [attr.aria-label]="'Fourchette ' + r.display_name"></td>
          <td><input type="checkbox" [(ngModel)]="r.activeEdit" style="width:auto;min-height:0" [attr.aria-label]="'Active ' + r.display_name"></td>
          <td><button class="ghost" (click)="editing = r.category_id">Enregistrer…</button></td>
        </tr></tbody>
      </table>
    </div>
    <div class="card" *ngIf="current as r">
      <h3>Enregistrer la grille « {{r.display_name}} »</h3>
      <div class="sub">Exemple pour 20 km et 30 min : {{example(r)}} net chauffeur.</div>
      <div class="field"><label for="g-why">Justification</label><input id="g-why" maxlength="500" [(ngModel)]="justification" placeholder="Ex. relevé des prix pratiqués à Marseille, octobre 2026"></div>
      <div class="row"><button (click)="save(r)" [disabled]="saving || !justification.trim()">{{saving ? 'Enregistrement…' : 'Enregistrer'}}</button>
        <button class="link" (click)="editing = ''">Annuler</button></div>
    </div>`
})
export class AdminPriceGrid implements OnInit {
  dateTime = dateTime;
  rows: any[] = []; error = ''; message = ''; editing = ''; justification = ''; saving = false;
  constructor(private api: Api) {}
  async ngOnInit() { await this.load(); }
  async load() {
    try {
      const raw = await this.api.priceGrid();
      const eur = (v: any) => v === null || v === undefined ? null : Number(v) / 100;
      this.rows = raw.map((r: any) => ({...r, base: eur(r.base_minor), perKm: eur(r.per_km_minor), perMinute: eur(r.per_minute_minor),
        minimum: eur(r.minimum_minor), spread: r.spread_bps === null || r.spread_bps === undefined ? 15 : r.spread_bps / 100, activeEdit: r.active === true}));
    } catch (e: any) { this.error = errorMessage(e?.code); }
  }
  get current() { return this.rows.find(r => r.category_id === this.editing) || null; }
  minor(v: any) { return v === null || v === undefined || v === '' ? null : Math.round(Number(v) * 100); }
  example(r: any) {
    const base = this.minor(r.base) || 0, km = this.minor(r.perKm) || 0, min = this.minor(r.perMinute) || 0, floor = this.minor(r.minimum) || 0;
    return money(Math.max(floor, base + km * 20 + min * 30));
  }
  async save(r: any) {
    this.saving = true; this.error = ''; this.message = '';
    try {
      await this.api.updatePriceGrid(r.category_id, {
        baseMinor: this.minor(r.base) ?? 0, perKmMinor: this.minor(r.perKm) ?? 0, perMinuteMinor: this.minor(r.perMinute) ?? 0,
        minimumMinor: this.minor(r.minimum), spreadBps: Math.round(Number(r.spread || 0) * 100), active: !!r.activeEdit,
        justification: this.justification.trim(),
      });
      this.message = 'Grille « ' + r.display_name + ' » enregistrée.';
      this.editing = ''; this.justification = '';
      await this.load();
    } catch (e: any) { this.error = errorMessage(e?.code); }
    finally { this.saving = false; }
  }
}
