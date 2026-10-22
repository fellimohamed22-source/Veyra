import {CommonModule} from '@angular/common';
import {Component, Input, OnInit} from '@angular/core';
import {FormsModule} from '@angular/forms';
import {RouterLink} from '@angular/router';
import {Api} from '../api';
import {dateTime, documentTypeLabel, errorMessage, kycStatusLabel, money, partnerOrgStatusLabel, paymentMethodLabel, statusLabel, when} from '../formatters';

const pct = (bps: number | null | undefined) => bps === null || bps === undefined ? '—' : (bps / 100).toLocaleString('fr-FR', {minimumFractionDigits: 2, maximumFractionDigits: 2}) + ' %';

/** Tableau de bord de l'administration. */
@Component({
  standalone: true,
  imports: [CommonModule, RouterLink],
  template: `
    <div class="mhead"><div><h1>Tableau de bord</h1><div class="sub">Vue d'ensemble de la plateforme</div></div></div>
    <div class="errbox" *ngIf="error">{{error}}</div>
    <div class="grid4" *ngIf="d">
      <a class="card kpi" routerLink="/admin/reservations" style="text-decoration:none;color:inherit"><div class="n">{{d.bookings}}</div><div class="l">Réservations</div></a>
      <a class="card kpi" routerLink="/admin/verifications" style="text-decoration:none;color:inherit"><div class="n">{{d.pendingDrivers}}</div><div class="l">Chauffeurs à vérifier</div></a>
      <a class="card kpi" routerLink="/admin/partenaires" style="text-decoration:none;color:inherit"><div class="n">{{d.pendingPartners}}</div><div class="l">Partenaires à valider</div></a>
      <a class="card kpi" routerLink="/admin/commissions" style="text-decoration:none;color:inherit"><div class="n">{{activeRules}}</div><div class="l">Règles de commission actives</div></a>
    </div>`
})
export class AdminDashboard implements OnInit {
  d: any = null; error = ''; activeRules: number | string = '—';
  constructor(private api: Api) {}
  async ngOnInit() {
    try { this.d = await this.api.adminDashboard(); } catch (e: any) { this.error = errorMessage(e?.code); }
    try { this.activeRules = (await this.api.commissionRules()).filter((r: any) => r.status === 'ACTIVE').length; } catch {}
  }
}

/** Vérifications : chauffeurs à contrôler avant tout accès au marketplace (ADM-02). */
@Component({
  standalone: true,
  imports: [CommonModule, RouterLink],
  template: `
    <div class="mhead"><div><h1>Vérifications</h1><div class="sub">Contrôle humain des pièces avant l'accès aux demandes.</div></div></div>
    <div class="seg"><button *ngFor="let t of tabs" type="button" [class.on]="tab === t.key" (click)="tab = t.key">{{t.label}}</button></div>
    <div class="errbox" *ngIf="error">{{error}}</div>
    <div class="tablewrap">
      <table>
        <thead><tr><th>Chauffeur</th><th>Contact</th><th>Dossier</th><th>Statut</th><th></th></tr></thead>
        <tbody><tr *ngFor="let x of filtered">
          <td><b>{{x.first_name}} {{x.last_name}}</b></td>
          <td>{{x.email}}<div class="sub">{{x.phone || '—'}}</div></td>
          <td><span class="pill" [ngClass]="pill(x.kyc_status)">{{kycStatusLabel(x.kyc_status)}}</span></td>
          <td><span class="pill" [ngClass]="x.marketplace_enabled ? 'p-ok' : 'p-mute'">{{x.marketplace_enabled ? 'Accès aux demandes' : 'Sans accès'}}</span></td>
          <td><button [class.ghost]="x.kyc_status !== 'SUBMITTED'" [routerLink]="['/admin/verifications', x.id]">{{x.kyc_status === 'SUBMITTED' ? 'Vérifier' : 'Voir'}}</button></td>
        </tr></tbody>
      </table>
    </div>
    <p class="empty" *ngIf="loaded && !filtered.length">Aucun chauffeur dans cette liste.</p>`
})
export class AdminVerifications implements OnInit {
  kycStatusLabel = kycStatusLabel;
  tabs = [{key: 'todo', label: 'À vérifier'}, {key: 'all', label: 'Tous'}];
  tab = 'todo'; drivers: any[] = []; loaded = false; error = '';
  constructor(private api: Api) {}
  async ngOnInit() {
    try { this.drivers = await this.api.adminDrivers(); } catch (e: any) { this.error = errorMessage(e?.code); }
    this.loaded = true;
  }
  get filtered() { return this.tab === 'todo' ? this.drivers.filter(d => ['SUBMITTED', 'UNDER_REVIEW'].includes(d.kyc_status)) : this.drivers; }
  pill(s: string) { return s === 'APPROVED' ? 'p-ok' : s === 'REJECTED' ? 'p-bad' : s === 'SUBMITTED' || s === 'UNDER_REVIEW' ? 'p-warn' : 'p-mute'; }
}

/** Vérification d'un chauffeur (ADM-02, ADM-03) : pièces, décision motivée. */
@Component({
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink],
  template: `
    <p class="sub"><a routerLink="/admin/verifications">← Vérifications</a></p>
    <div class="errbox" *ngIf="error">{{error}}</div>
    <ng-container *ngIf="driver">
      <div class="mhead">
        <div><h1>{{driver.first_name}} {{driver.last_name}}</h1><div class="sub">{{driver.email}} · {{driver.phone || 'sans téléphone'}} · {{kycStatusLabel(driver.kyc_status)}}</div></div>
        <div class="row" *ngIf="driver.kyc_status !== 'APPROVED'">
          <button class="danger" (click)="rejecting = !rejecting">Demander une correction</button>
          <button (click)="approve()" [disabled]="busy">Approuver</button>
        </div>
      </div>
      <div class="card" *ngIf="rejecting">
        <h3>Motif de la correction</h3>
        <select [(ngModel)]="reason" aria-label="Motif">
          <option value="DOCUMENT_INVALID">Document illisible ou invalide</option>
          <option value="DOCUMENT_EXPIRED">Document expiré</option>
          <option value="DOCUMENT_MISSING">Document manquant</option>
          <option value="IDENTITY_MISMATCH">Identité incohérente</option>
          <option value="VEHICLE_NOT_COMPLIANT">Véhicule non conforme</option>
        </select>
        <div class="row"><button class="danger" (click)="reject()" [disabled]="busy">Envoyer la demande de correction</button></div>
      </div>
      <div class="card">
        <h3>Pièces</h3>
        <p class="empty" *ngIf="!documents.length">Aucun document soumis.</p>
        <div class="row between" *ngFor="let doc of documents" style="border-top:1px solid #EEF1F6;padding-top:8px">
          <span>{{documentTypeLabel(doc.type)}}<span *ngIf="doc.side"> ({{doc.side === 'BACK' ? 'verso' : 'recto'}})</span><span class="sub" *ngIf="doc.expires_at"> · fin {{day(doc.expires_at)}}</span></span>
          <span class="row"><span class="pill" [ngClass]="doc.status === 'APPROVED' ? 'p-ok' : doc.status === 'REJECTED' ? 'p-bad' : doc.status === 'SUPERSEDED' ? 'p-mute' : 'p-warn'">{{doc.status === 'SUPERSEDED' ? 'Remplacé' : kycStatusLabel(doc.status)}}</span>
            <button class="ghost" (click)="view(doc.id)">Voir</button></span>
        </div>
      </div>
      <div class="card">
        <h3>Véhicule</h3>
        <p class="empty" *ngIf="!vehicles.length">Aucun véhicule enregistré.</p>
        <div class="row between" *ngFor="let v of vehicles" style="border-top:1px solid #EEF1F6;padding-top:8px">
          <span class="route"><b>{{v.brand}} {{v.model}} · {{v.year}} · {{v.plate_number}}</b>
            <span class="sub">{{v.category_name}}<span *ngIf="v.seats"> · {{v.seats}} places</span><span *ngIf="v.baggage_capacity !== null && v.baggage_capacity !== undefined"> · {{v.baggage_capacity}} bagages</span><span *ngIf="v.color"> · {{v.color}}</span></span></span>
          <span class="pill" [ngClass]="v.status === 'APPROVED' ? 'p-ok' : v.status === 'REJECTED' ? 'p-bad' : 'p-warn'">{{v.status === 'APPROVED' ? 'Approuvé' : v.status === 'REJECTED' ? 'Refusé' : 'À vérifier'}}</span>
        </div>
        <div class="sub" *ngIf="vehicles.length">L'approbation du chauffeur approuve aussi ses véhicules en attente.</div>
      </div>
      <div class="okbox" *ngIf="message">{{message}}</div>
    </ng-container>`
})
export class AdminDriverReview implements OnInit {
  kycStatusLabel = kycStatusLabel; documentTypeLabel = documentTypeLabel;
  @Input() id = '';
  driver: any = null; documents: any[] = []; vehicles: any[] = []; error = ''; message = ''; busy = false; rejecting = false; reason = 'DOCUMENT_INVALID';
  constructor(private api: Api) {}
  async ngOnInit() { await this.load(); }
  async load() {
    try {
      this.driver = (await this.api.adminDrivers()).find((d: any) => d.id === this.id) || null;
      this.documents = await this.api.adminDriverDocuments(this.id);
      try { this.vehicles = await this.api.adminDriverVehicles(this.id); } catch { this.vehicles = []; }
      if (!this.driver) this.error = 'Chauffeur introuvable.';
    } catch (e: any) { this.error = errorMessage(e?.code); }
  }
  async approve() { await this.act(() => this.api.approveDriver(this.id), 'Dossier approuvé : le chauffeur a accès aux demandes.'); }
  async reject() { await this.act(() => this.api.rejectDriver(this.id, this.reason), 'Correction demandée au chauffeur.'); this.rejecting = false; }
  private async act(fn: () => Promise<any>, ok: string) {
    this.busy = true; this.error = ''; this.message = '';
    try { await fn(); this.message = ok; await this.load(); } catch (e: any) { this.error = errorMessage(e?.code); }
    finally { this.busy = false; }
  }
  async view(id: string) {
    try { const blob = await this.api.requestBlob('/documents/' + id + '/content'); window.open(URL.createObjectURL(blob), '_blank'); }
    catch { this.error = 'Document introuvable ou accès refusé.'; }
  }
  day(raw: string) { return dateTime(raw).split(' ')[0]; }
}

/** Règles de commission (ADM-COM-01..03) : moteur livré au lot L6. */
@Component({
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="mhead"><div><h1>Règles de commission</h1><div class="sub">Priorité : client > organisation > catégorie > profil > général. Versions datées, justification obligatoire.</div></div>
      <button (click)="creating = !creating">{{creating ? 'Fermer' : 'Nouvelle règle'}}</button></div>
    <div class="errbox" *ngIf="error">{{error}}</div>
    <div class="okbox" *ngIf="message">{{message}}</div>

    <div class="card" *ngIf="creating">
      <h3>Nouvelle règle</h3>
      <div class="grid3">
        <div class="field"><label for="scope">Portée</label>
          <select id="scope" [(ngModel)]="form.scopeType">
            <option value="USER">Client</option><option value="PARTNER">Organisation</option><option value="PARTNER_CATEGORY">Catégorie d'organisation</option>
            <option value="PROFILE">Profil</option><option value="STANDARD">Général</option>
          </select></div>
        <div class="field" *ngIf="form.scopeType === 'USER'"><label for="uid">Identifiant du client</label><input id="uid" [(ngModel)]="form.userId" placeholder="UUID du compte"></div>
        <div class="field" *ngIf="form.scopeType === 'PARTNER'"><label for="pid">Organisation</label>
          <select id="pid" [(ngModel)]="form.partnerId"><option value="">Choisir</option><option *ngFor="let p of partners" [value]="p.id">{{p.name}}</option></select></div>
        <div class="field" *ngIf="form.scopeType === 'PARTNER_CATEGORY'"><label for="cat">Catégorie</label>
          <select id="cat" [(ngModel)]="form.partnerCategory"><option value="HOTEL">Hôtels</option><option value="RESTAURANT">Restaurants</option><option value="BAR">Bars</option><option value="CONCIERGE">Conciergeries</option><option value="COMPANY">Entreprises</option></select></div>
        <div class="field" *ngIf="form.scopeType === 'PROFILE'"><label for="prof">Profil</label>
          <select id="prof" [(ngModel)]="form.profileType"><option value="CLIENT">Clients</option><option value="PARTNER">Partenaires</option></select></div>
        <div class="field"><label for="rate">Taux (%)</label><input id="rate" type="number" min="0" max="100" step="0.01" [(ngModel)]="form.ratePercent"></div>
        <div class="field"><label for="fix">Fixe (€)</label><input id="fix" type="number" min="0" step="0.01" [(ngModel)]="form.fixed"></div>
        <div class="field"><label for="min">Plancher (€)</label><input id="min" type="number" min="0" step="0.01" [(ngModel)]="form.min"></div>
        <div class="field"><label for="max">Plafond (€)</label><input id="max" type="number" min="0" step="0.01" [(ngModel)]="form.max"></div>
        <div class="field"><label for="from">À partir du</label><input id="from" type="datetime-local" [(ngModel)]="form.from"></div>
        <div class="field"><label for="to">Jusqu'au (facultatif)</label><input id="to" type="datetime-local" [(ngModel)]="form.to"></div>
      </div>
      <div class="field"><label for="why">Justification</label><input id="why" maxlength="500" [(ngModel)]="form.justification" placeholder="Ex. accord commercial signé le 17/10/2026"></div>
      <div class="row"><button (click)="create()" [disabled]="saving || !form.justification.trim()">{{saving ? 'Enregistrement…' : 'Créer la règle'}}</button></div>
    </div>

    <div class="tablewrap">
      <table>
        <thead><tr><th>Portée</th><th>Concerne</th><th>Taux</th><th>Fixe</th><th>Plancher / plafond</th><th>Période</th><th>Statut</th><th></th></tr></thead>
        <tbody><tr *ngFor="let r of rules">
          <td><span class="pill" [ngClass]="r.scope_type === 'STANDARD' ? 'p-mute' : 'p-info'">{{scopeLabel(r.scope_type)}}</span></td>
          <td>{{subject(r)}}</td>
          <td>{{pct(r.commission_bps)}}</td>
          <td>{{r.fixed_minor ? money(r.fixed_minor) : '—'}}</td>
          <td>{{r.min_commission_minor ? money(r.min_commission_minor) : '—'}} / {{r.max_commission_minor ? money(r.max_commission_minor) : '—'}}</td>
          <td>{{period(r)}}</td>
          <td><span class="pill" [ngClass]="state(r).css">{{state(r).text}}</span></td>
          <td><button class="link" *ngIf="r.status === 'ACTIVE' && r.scope_type !== 'STANDARD'" (click)="deactivate(r)">Désactiver</button></td>
        </tr></tbody>
      </table>
    </div>

    <div class="card">
      <div class="mhead"><h3>Simulation</h3><span class="sub">ne modifie rien</span></div>
      <div class="grid4">
        <div class="field"><label for="sb">Réservataire</label>
          <select id="sb" [(ngModel)]="sim.target">
            <option value="CLIENT">Client (règle générale ou profil)</option>
            <option *ngFor="let p of partners" [value]="'P:' + p.id">{{p.name}}</option>
          </select></div>
        <div class="field"><label for="sp">Prix net chauffeur (€)</label><input id="sp" type="number" min="1" step="0.01" [(ngModel)]="sim.price"></div>
        <div class="field"><label>Règle appliquée</label><div class="input" style="display:flex;align-items:center;min-height:40px;border:1px solid var(--line);border-radius:10px;padding:0 12px;background:#fff">{{simResult ? scopeLabel(simResult.scopeType) + ' · ' + pct(simResult.rateBps) : '—'}}</div></div>
        <div class="field"><label>Prix client</label><div style="display:flex;align-items:center;min-height:40px;border:1px solid var(--line);border-radius:10px;padding:0 12px;background:#fff"><b>{{simResult ? money(simResult.customerTotalMinor) : '—'}}</b></div></div>
      </div>
      <div class="row"><button class="ghost" (click)="simulate()">Simuler</button></div>
    </div>`
})
export class AdminCommissions implements OnInit {
  money = money; pct = pct;
  rules: any[] = []; partners: any[] = []; error = ''; message = ''; creating = false; saving = false;
  form: any = this.blank();
  sim: any = {target: 'CLIENT', price: 48};
  simResult: any = null;
  constructor(private api: Api) {}
  async ngOnInit() { await this.load(); try { this.partners = await this.api.adminPartners(); } catch {} }
  async load() { try { this.rules = await this.api.commissionRules(); } catch (e: any) { this.error = errorMessage(e?.code); } }
  blank() { return {scopeType: 'PARTNER', userId: '', partnerId: '', partnerCategory: 'HOTEL', profileType: 'PARTNER', ratePercent: 10, fixed: null, min: null, max: null, from: '', to: '', justification: ''}; }
  toMinor(v: any) { return v === null || v === undefined || v === '' ? null : Math.round(Number(v) * 100); }
  async create() {
    const f = this.form; this.saving = true; this.error = ''; this.message = '';
    try {
      await this.api.createCommissionRule({
        scopeType: f.scopeType,
        userId: f.scopeType === 'USER' ? f.userId.trim() || null : null,
        partnerId: f.scopeType === 'PARTNER' ? f.partnerId || null : null,
        partnerCategory: f.scopeType === 'PARTNER_CATEGORY' ? f.partnerCategory : null,
        profileType: f.scopeType === 'PROFILE' ? f.profileType : null,
        rateBps: Math.round(Number(f.ratePercent) * 100),
        fixedMinor: this.toMinor(f.fixed), minCommissionMinor: this.toMinor(f.min), maxCommissionMinor: this.toMinor(f.max),
        effectiveFrom: f.from ? new Date(f.from).toISOString() : null,
        effectiveTo: f.to ? new Date(f.to).toISOString() : null,
        justification: f.justification.trim(),
      });
      this.message = 'Règle créée.'; this.form = this.blank(); this.creating = false;
      await this.load();
    } catch (e: any) { this.error = errorMessage(e?.code); }
    finally { this.saving = false; }
  }
  async deactivate(r: any) {
    const justification = window.prompt('Justification de la désactivation');
    if (!justification || !justification.trim()) return;
    try { await this.api.deactivateCommissionRule(r.id, justification.trim()); this.message = 'Règle désactivée.'; await this.load(); }
    catch (e: any) { this.error = errorMessage(e?.code); }
  }
  async simulate() {
    this.error = '';
    const partner = String(this.sim.target).startsWith('P:') ? String(this.sim.target).slice(2) : null;
    try {
      this.simResult = await this.api.simulateCommission({bookerType: partner ? 'PARTNER' : 'CLIENT', partnerId: partner, userId: null, driverPriceMinor: Math.round(Number(this.sim.price) * 100)});
    } catch (e: any) { this.error = errorMessage(e?.code); }
  }
  scopeLabel(s: string) { return {USER: 'Client', PARTNER: 'Organisation', PARTNER_CATEGORY: 'Catégorie', PROFILE: 'Profil', STANDARD: 'Général'}[s] || s; }
  subject(r: any) {
    switch (r.scope_type) {
      case 'USER': return r.user_email || r.user_id;
      case 'PARTNER': return r.partner_name || r.partner_id;
      case 'PARTNER_CATEGORY': return ({HOTEL: 'Hôtels', RESTAURANT: 'Restaurants', BAR: 'Bars', CONCIERGE: 'Conciergeries', COMPANY: 'Entreprises'} as any)[r.partner_category] || r.partner_category;
      case 'PROFILE': return r.profile_type === 'PARTNER' ? 'Partenaires' : 'Clients';
      default: return 'Toutes réservations';
    }
  }
  period(r: any) {
    const from = r.effective_from ? new Date(r.effective_from) : null;
    const to = r.effective_to ? ' au ' + dateTime(r.effective_to).split(' ')[0] : '';
    if (!from) return 'depuis l’ouverture' + to;
    return (from.getTime() > Date.now() ? 'à partir du ' : 'depuis le ') + dateTime(r.effective_from).split(' ')[0] + to;
  }
  state(r: any) {
    if (r.status !== 'ACTIVE') return {text: 'Inactive', css: 'p-mute'};
    if (r.effective_from && new Date(r.effective_from).getTime() > Date.now()) return {text: 'Programmée', css: 'p-warn'};
    if (r.effective_to && new Date(r.effective_to).getTime() < Date.now()) return {text: 'Expirée', css: 'p-mute'};
    return {text: 'Active', css: 'p-ok'};
  }
}

/** Paramètres de la plateforme (ADM-10) : bornes, justification, journal. */
@Component({
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="mhead"><div><h1>Paramètres</h1><div class="sub">Modifiables dans leurs bornes, avec justification. Chaque changement est journalisé.</div></div></div>
    <div class="errbox" *ngIf="error">{{error}}</div>
    <div class="okbox" *ngIf="message">{{message}}</div>
    <div class="tablewrap">
      <table>
        <thead><tr><th>Paramètre</th><th>Valeur</th><th>Bornes</th><th>Dernière modification</th><th></th></tr></thead>
        <tbody><tr *ngFor="let s of settings">
          <td><b>{{label(s)}}</b><div class="sub mono">{{s.setting_key}}</div></td>
          <td>
            <ng-container *ngIf="editing !== s.setting_key">{{s.value_number}} {{unit(s.setting_key)}}</ng-container>
            <input *ngIf="editing === s.setting_key" type="number" style="max-width:120px" [min]="s.min_value" [max]="s.max_value" [(ngModel)]="value" aria-label="Nouvelle valeur">
          </td>
          <td>{{s.min_value}} – {{s.max_value}}</td>
          <td>{{s.updated_by ? dateTime(s.updated_at) : 'valeur initiale'}}</td>
          <td>
            <button class="ghost" *ngIf="editing !== s.setting_key" (click)="edit(s)">Modifier</button>
            <div class="stack" *ngIf="editing === s.setting_key" style="min-width:240px">
              <input maxlength="500" [(ngModel)]="justification" placeholder="Justification" aria-label="Justification">
              <div class="row"><button (click)="save(s)" [disabled]="!justification.trim()">Enregistrer</button><button class="link" (click)="editing = ''">Annuler</button></div>
            </div>
          </td>
        </tr></tbody>
      </table>
    </div>

    <div class="grid2">
      <div class="card">
        <h3>Visibilité des offres pour les chauffeurs</h3>
        <div class="seg">
          <button type="button" [class.on]="visibility === 'PRIVATE'" (click)="visibility = 'PRIVATE'">Offre privée</button>
          <button type="button" [class.on]="visibility === 'BEST_VISIBLE'" (click)="visibility = 'BEST_VISIBLE'">Meilleure offre visible</button>
        </div>
        <div class="sub">« Meilleure offre visible » : le chauffeur voit seulement le prix le plus bas des autres, jamais leur identité ; cela ne bloque jamais son offre. S'applique aux nouvelles demandes.</div>
        <div class="row"><button class="ghost" (click)="saveVisibility()">Enregistrer</button></div>
      </div>
      <div class="card">
        <h3>Politique d'annulation</h3>
        <div class="grid2" *ngIf="policy">
          <div class="field"><label>Gratuite jusqu'à (minutes avant)</label><input type="number" min="0" [(ngModel)]="policy.freeUntilMinutes"></div>
          <div class="field"><label>Frais intermédiaires dès (minutes avant)</label><input type="number" min="0" [(ngModel)]="policy.midWindowFromMinutes"></div>
          <div class="field"><label>Frais intermédiaires (%)</label><input type="number" min="0" max="100" step="0.01" [(ngModel)]="policy.midPct"></div>
          <div class="field"><label>Frais tardifs (%)</label><input type="number" min="0" max="100" step="0.01" [(ngModel)]="policy.latePct"></div>
          <div class="field"><label>Absence du client (%)</label><input type="number" min="0" max="100" step="0.01" [(ngModel)]="policy.noShowPct"></div>
        </div>
        <div class="row"><button class="ghost" (click)="savePolicy()" [disabled]="!policy">Enregistrer la politique</button></div>
      </div>
    </div>`
})
export class AdminSettings implements OnInit {
  dateTime = dateTime;
  settings: any[] = []; error = ''; message = ''; editing = ''; value = 0; justification = '';
  visibility = 'PRIVATE'; policy: any = null; rawPolicy: any = null;
  constructor(private api: Api) {}
  async ngOnInit() {
    await this.load();
    try { this.visibility = (await this.api.getOfferVisibility()).mode || 'PRIVATE'; } catch {}
    try { this.rawPolicy = await this.api.getCancellationPolicy(); const r = this.rawPolicy; this.policy = {...r, midPct: r.midFeeBps / 100, latePct: r.lateFeeBps / 100, noShowPct: r.noShowFeeBps / 100}; } catch {}
  }
  async load() { try { this.settings = await this.api.platformSettings(); } catch (e: any) { this.error = errorMessage(e?.code); } }
  edit(s: any) { this.editing = s.setting_key; this.value = s.value_number; this.justification = ''; }
  async save(s: any) {
    this.error = ''; this.message = '';
    try { await this.api.updatePlatformSetting(s.setting_key, Number(this.value), this.justification.trim()); this.message = 'Paramètre mis à jour.'; this.editing = ''; await this.load(); }
    catch (e: any) { this.error = errorMessage(e?.code); }
  }
  async saveVisibility() {
    try { await this.api.setOfferVisibility(this.visibility); this.message = 'Visibilité des offres mise à jour.'; } catch (e: any) { this.error = errorMessage(e?.code); }
  }
  async savePolicy() {
    const {midPct, latePct, noShowPct, ...rest} = this.policy;
    const bps = (v: any) => Math.round(Number(v) * 100);
    try { await this.api.setCancellationPolicy({...this.rawPolicy, ...rest, midFeeBps: bps(midPct), lateFeeBps: bps(latePct), noShowFeeBps: bps(noShowPct)}); this.message = 'Politique d’annulation enregistrée.'; } catch (e: any) { this.error = errorMessage(e?.code); }
  }
  label(s: any) {
    return ({
      'booking.min_lead_minutes': 'Délai minimum de réservation',
      'ride.pickup_radius_meters': 'Rayon de prise en charge (« Arrivé », « Démarrer »)',
      'booking.normal_close_before_minutes': 'Clôture des offres avant prise en charge',
      'booking.short_close_before_minutes': 'Clôture des offres (réservation proche)',
      'booking.max_offer_window_hours': 'Fenêtre d’offres maximale',
      'ride.location_max_age_seconds': 'Âge maximal de la position du chauffeur',
    } as any)[s.setting_key] || s.description || s.setting_key;
  }
  unit(k: string) { return k.endsWith('_minutes') ? 'min' : k.endsWith('_hours') ? 'h' : k.endsWith('_meters') ? 'm' : k.endsWith('_seconds') ? 's' : ''; }
}

/** Partenaires : validation, suspension, crédit de facturation mensuelle. */
@Component({
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink],
  template: `
    <div class="mhead"><div><h1>Partenaires</h1><div class="sub">Validation des établissements et crédit de facturation mensuelle. Les commissions se règlent dans <a routerLink="/admin/commissions">Commissions</a>.</div></div></div>
    <div class="errbox" *ngIf="error">{{error}}</div>
    <div class="okbox" *ngIf="message">{{message}}</div>
    <div class="tablewrap">
      <table>
        <thead><tr><th>Établissement</th><th>Type</th><th>Statut</th><th>Crédit (€)</th><th></th></tr></thead>
        <tbody><tr *ngFor="let p of partners">
          <td><b>{{p.name}}</b></td>
          <td>{{p.partner_type}}</td>
          <td><span class="pill" [ngClass]="p.status === 'APPROVED' ? 'p-ok' : p.status === 'SUSPENDED' ? 'p-bad' : 'p-warn'">{{partnerOrgStatusLabel(p.status)}}</span></td>
          <td><div class="row" *ngIf="p.status === 'APPROVED'"><input type="number" min="0" step="100" style="max-width:120px" [(ngModel)]="credit[p.id]" aria-label="Plafond"><button class="ghost" (click)="saveCredit(p)">Enregistrer</button></div></td>
          <td><button *ngIf="p.status !== 'APPROVED'" (click)="act(api.approvePartner(p.id), 'Établissement validé.')">Valider</button>
            <button class="danger" *ngIf="p.status === 'APPROVED'" (click)="act(api.suspendPartner(p.id), 'Établissement suspendu.')">Suspendre</button></td>
        </tr></tbody>
      </table>
    </div>`
})
export class AdminPartners implements OnInit {
  partnerOrgStatusLabel = partnerOrgStatusLabel;
  partners: any[] = []; credit: Record<string, number> = {}; error = ''; message = '';
  constructor(public api: Api) {}
  async ngOnInit() { await this.load(); }
  async load() {
    try {
      this.partners = await this.api.adminPartners();
      for (const p of this.partners) this.credit[p.id] = (p.credit_limit_minor || 0) / 100;
    } catch (e: any) { this.error = errorMessage(e?.code); }
  }
  async act(call: Promise<any>, ok: string) {
    this.error = ''; this.message = '';
    try { await call; this.message = ok; await this.load(); } catch (e: any) { this.error = errorMessage(e?.code); }
  }
  async saveCredit(p: any) { await this.act(this.api.setPartnerCredit(p.id, Math.round((this.credit[p.id] || 0) * 100), 30, 'MONTHLY'), 'Crédit mis à jour.'); }
}

/** Réservations de la plateforme. */
@Component({
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="mhead"><div><h1>Réservations</h1><div class="sub">{{bookings.length}} réservations récentes</div></div></div>
    <div class="errbox" *ngIf="error">{{error}}</div>
    <div class="tablewrap">
      <table>
        <thead><tr><th>Prise en charge</th><th>Trajet</th><th>Paiement</th><th>Statut</th></tr></thead>
        <tbody><tr *ngFor="let b of bookings">
          <td>{{when(b.scheduled_at)}}</td>
          <td><div class="route"><b>{{short(b.pickup_address)}} → {{short(b.dropoff_address)}}</b></div></td>
          <td>{{paymentMethodLabel(b.payment_method)}}</td>
          <td>{{statusLabel(b.status)}}</td>
        </tr></tbody>
      </table>
    </div>`
})
export class AdminBookings implements OnInit {
  when = when; statusLabel = statusLabel; paymentMethodLabel = paymentMethodLabel;
  bookings: any[] = []; error = '';
  constructor(private api: Api) {}
  async ngOnInit() { try { this.bookings = await this.api.adminBookings(); } catch (e: any) { this.error = errorMessage(e?.code); } }
  short(a: string) { return (a || '').split(',')[0]; }
}
