import {CommonModule} from '@angular/common';
import {Component, OnInit} from '@angular/core';
import {FormsModule} from '@angular/forms';
import {RouterLink} from '@angular/router';
import {Api} from '../api';
import {dateTime, documentTypeLabel, errorMessage, kycStatusLabel, money, when} from '../formatters';
import {CompanyContext, companyPill} from './shell';

const day = (raw: any) => raw ? dateTime(raw).split(' ')[0] : '—';
const DAY_MS = 86400000;

/** « dans 6 jours » / « expirée depuis 2 jours » (mock-up wording). */
export function dueLabel(raw: string): string {
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const d = Math.round((new Date(raw + 'T00:00:00').getTime() - today.getTime()) / DAY_MS);
  if (d < 0) return `expiré depuis ${-d} jour${d < -1 ? 's' : ''}`;
  if (d === 0) return 'expire aujourd’hui';
  return `dans ${d} jour${d > 1 ? 's' : ''}`;
}

/** Effect of an expiry on the marketplace (SOC-09). */
export function expiryEffect(x: any): {text: string; css: string} {
  const expired = new Date(x.expires_at + 'T23:59:59').getTime() < Date.now();
  if (x.scope === 'VEHICLE') return expired ? {text: 'Véhicule bloqué', css: 'p-bad'} : {text: 'Véhicule bientôt bloqué', css: 'p-warn'};
  if (x.scope === 'DRIVER') return expired ? {text: 'Offres bloquées', css: 'p-bad'} : {text: 'Offres bientôt bloquées', css: 'p-warn'};
  return expired ? {text: 'Expiré', css: 'p-bad'} : {text: 'À renouveler', css: 'p-warn'};
}

const MISSING_FR: Record<string, string> = {
  REVTC_NUMBER: 'Numéro d’inscription au registre VTC', ADDRESS: 'Adresse du siège', VEHICLE: 'Au moins un véhicule',
};

/** SOC-07 / SOC-09 / SOC-10: fleet dashboard. */
@Component({
  standalone: true,
  imports: [CommonModule, RouterLink],
  template: `
    <div class="errbox" *ngIf="error">{{error}}</div>
    <ng-container *ngIf="o">
      <div class="mhead">
        <div><h1>{{o.legal_name}}</h1><div class="sub">SIREN {{siren(o.siren)}}<span *ngIf="o.revtc_number"> · REVTC n° {{o.revtc_number}}</span></div></div>
        <span class="pill" [ngClass]="pill.css">{{pill.text}}</span>
      </div>

      <div class="card" *ngIf="o.status === 'DRAFT' || o.status === 'REJECTED'">
        <h3>{{o.status === 'REJECTED' ? 'Dossier à corriger' : 'Dossier à envoyer à VEYRA'}}</h3>
        <div class="warnbox" *ngIf="o.status === 'REJECTED'">VEYRA a demandé une correction : {{reason(o.rejection_reason_code)}}.</div>
        <div *ngIf="o.missing?.length" class="stack">
          <div class="sub">Il manque encore :</div>
          <div class="row"><span class="pill p-warn" *ngFor="let m of o.missing">{{missingLabel(m)}}</span></div>
          <div class="row"><a routerLink="/societe/documents">Téléverser les documents</a><a routerLink="/societe/vehicules">Ajouter un véhicule</a></div>
        </div>
        <div class="row"><button class="gold" (click)="submit()" [disabled]="busy || o.missing?.length">Envoyer le dossier à VEYRA</button></div>
      </div>
      <div class="note" *ngIf="o.status === 'SUBMITTED'">Votre dossier est en cours de vérification par VEYRA. Vous pouvez déjà inviter vos chauffeurs.</div>
      <div class="okbox" *ngIf="message">{{message}}</div>

      <div class="grid4">
        <a class="card kpi" routerLink="/societe/vehicules" style="text-decoration:none;color:inherit"><div class="n">{{o.approvedVehicles}}</div><div class="l">Véhicules approuvés<span *ngIf="o.vehicles > o.approvedVehicles"> · {{o.vehicles - o.approvedVehicles}} en attente</span></div></a>
        <a class="card kpi" routerLink="/societe/chauffeurs" style="text-decoration:none;color:inherit"><div class="n">{{o.activeDrivers}}</div><div class="l">Chauffeurs affiliés<span *ngIf="o.pendingDrivers"> · {{o.pendingDrivers}} à valider</span></div></a>
        <a class="card kpi" routerLink="/societe/documents" style="text-decoration:none;color:inherit"><div class="n">{{o.documentsToRenew}}</div><div class="l">Documents à renouveler</div></a>
        <a class="card kpi" routerLink="/societe/activite" style="text-decoration:none;color:inherit"><div class="n">{{o.ridesThisMonth}}</div><div class="l">Courses ce mois</div></a>
      </div>

      <div class="card">
        <h3>Échéances</h3>
        <p class="empty" *ngIf="!expiries.length">Aucun document n'arrive à échéance dans les 30 prochains jours.</p>
        <div class="tablewrap" *ngIf="expiries.length">
          <table>
            <thead><tr><th>Document</th><th>Concerne</th><th>Échéance</th><th>Effet</th><th></th></tr></thead>
            <tbody><tr *ngFor="let x of expiries">
              <td>{{documentTypeLabel(x.type)}}</td>
              <td>{{x.scope === 'COMPANY' ? 'Société' : x.subject}}</td>
              <td>{{dueLabel(x.expires_at)}}</td>
              <td><span class="pill" [ngClass]="expiryEffect(x).css">{{expiryEffect(x).text}}</span></td>
              <td><button *ngIf="x.scope !== 'DRIVER'" routerLink="/societe/documents" [queryParams]="{vehicle: x.vehicle_id || null, type: x.type}">Téléverser</button>
                <span class="sub" *ngIf="x.scope === 'DRIVER'">à renouveler par le chauffeur dans son application</span></td>
            </tr></tbody>
          </table>
        </div>
      </div>
    </ng-container>`
})
export class CompanyDashboard implements OnInit {
  documentTypeLabel = documentTypeLabel; dueLabel = dueLabel; expiryEffect = expiryEffect;
  o: any = null; expiries: any[] = []; error = ''; message = ''; busy = false;
  constructor(private api: Api, private ctx: CompanyContext) {}
  get pill() { return companyPill(this.o?.status); }
  async ngOnInit() { await this.load(); }
  async load() {
    try {
      [this.o, this.expiries] = await Promise.all([this.api.companyOverview(this.ctx.id), this.api.companyExpiries(this.ctx.id)]);
    } catch (e: any) { this.error = errorMessage(e?.code); }
  }
  async submit() {
    this.busy = true; this.error = ''; this.message = '';
    try { await this.api.submitCompany(this.ctx.id); this.message = 'Dossier envoyé : VEYRA vous répond après vérification.'; await this.load(); await this.ctx.load(); }
    catch (e: any) { this.error = e?.missing ? 'Le dossier est incomplet.' : errorMessage(e?.code); }
    finally { this.busy = false; }
  }
  missingLabel(m: string) { return MISSING_FR[m] || documentTypeLabel(m); }
  siren(s: string) { return (s || '').replace(/(\d{3})(\d{3})(\d{3})/, '$1 $2 $3'); }
  reason(code: string) {
    return ({DOCUMENT_INVALID: 'document illisible ou invalide', DOCUMENT_EXPIRED: 'document expiré', DOCUMENT_MISSING: 'document manquant',
      IDENTITY_MISMATCH: 'identité incohérente', VEHICLE_NOT_COMPLIANT: 'véhicule non conforme'} as any)[code] || 'voir avec le support';
  }
}

/** SOC-04 / SOC-08: fleet and vehicle assignment. */
@Component({
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink],
  template: `
    <div class="mhead"><div><h1>Véhicules</h1><div class="sub">Chaque véhicule est vérifié par VEYRA. Un document expiré le retire des demandes.</div></div>
      <button (click)="adding = !adding">{{adding ? 'Fermer' : 'Ajouter un véhicule'}}</button></div>
    <div class="errbox" *ngIf="error">{{error}}</div>
    <div class="okbox" *ngIf="message">{{message}}</div>

    <div class="card" *ngIf="adding">
      <h3>Nouveau véhicule</h3>
      <div class="grid3">
        <div class="field"><label for="v-brand">Marque</label><input id="v-brand" [(ngModel)]="v.brand" maxlength="80"></div>
        <div class="field"><label for="v-model">Modèle</label><input id="v-model" [(ngModel)]="v.model" maxlength="80"></div>
        <div class="field"><label for="v-year">Année</label><input id="v-year" type="number" [(ngModel)]="v.year"></div>
        <div class="field"><label for="v-plate">Immatriculation</label><input id="v-plate" [(ngModel)]="v.plateNumber" maxlength="16" placeholder="AB-123-CD"></div>
        <div class="field"><label for="v-color">Couleur</label><input id="v-color" [(ngModel)]="v.color" maxlength="40"></div>
        <div class="field"><label for="v-cat">Catégorie</label>
          <select id="v-cat" [(ngModel)]="v.categoryId"><option value="">Choisir</option><option *ngFor="let c of categories" [value]="c.id">{{c.display_name}}</option></select></div>
        <div class="field"><label for="v-seats">Places passagers</label><input id="v-seats" type="number" min="1" max="9" [(ngModel)]="v.seats"></div>
        <div class="field"><label for="v-bags">Bagages</label><input id="v-bags" type="number" min="0" max="20" [(ngModel)]="v.baggageCapacity"></div>
      </div>
      <div class="row"><button (click)="add()" [disabled]="busy || !v.categoryId || !v.brand.trim() || !v.model.trim() || !v.plateNumber.trim()">Ajouter</button></div>
    </div>

    <div class="tablewrap">
      <table>
        <thead><tr><th>Véhicule</th><th>Catégorie</th><th>Documents</th><th>Chauffeur attribué</th><th>VEYRA</th></tr></thead>
        <tbody><tr *ngFor="let x of vehicles">
          <td><b>{{x.brand}} {{x.model}}</b><div class="sub">{{x.year}} · {{x.plate_number}}</div></td>
          <td>{{x.category_name}}<div class="sub"><span *ngIf="x.seats">{{x.seats}} places</span><span *ngIf="x.baggage_capacity !== null"> · {{x.baggage_capacity}} bagages</span></div></td>
          <td>
            <div class="row"><span class="pill" *ngFor="let t of vehicleDocs" [ngClass]="hasDoc(x, t) ? 'p-ok' : 'p-mute'">{{short(t)}}</span></div>
            <div class="sub" *ngIf="x.next_expiry">prochaine échéance {{day(x.next_expiry)}}</div>
            <a [routerLink]="['/societe/documents']" [queryParams]="{vehicle: x.id}">Téléverser</a>
          </td>
          <td>
            <select [ngModel]="x.driver_id || ''" (ngModelChange)="assign(x, $event)" [attr.aria-label]="'Chauffeur de ' + x.plate_number" style="min-width:180px">
              <option value="">Aucun</option>
              <option *ngFor="let d of activeDrivers" [value]="d.driver_id">{{d.first_name}} {{d.last_name}}</option>
            </select>
          </td>
          <td><span class="pill" [ngClass]="x.status === 'APPROVED' ? 'p-ok' : x.status === 'REJECTED' ? 'p-bad' : 'p-warn'">{{x.status === 'APPROVED' ? 'Approuvé' : x.status === 'REJECTED' ? 'Refusé' : 'En attente'}}</span></td>
        </tr></tbody>
      </table>
    </div>
    <p class="empty" *ngIf="loaded && !vehicles.length">Aucun véhicule. Ajoutez votre premier véhicule pour le soumettre à VEYRA.</p>`
})
export class CompanyVehicles implements OnInit {
  day = day;
  vehicleDocs = ['REGISTRATION', 'VEHICLE_INSURANCE', 'TECHNICAL_INSPECTION'];
  vehicles: any[] = []; activeDrivers: any[] = []; categories: any[] = []; loaded = false; adding = false; busy = false; error = ''; message = '';
  v: any = this.blank();
  constructor(private api: Api, private ctx: CompanyContext) {}
  blank() { return {brand: '', model: '', year: new Date().getFullYear(), plateNumber: '', color: '', categoryId: '', seats: 4, baggageCapacity: 3}; }
  async ngOnInit() {
    await this.load();
    try { this.categories = await this.api.vehicleCategories(); } catch {}
  }
  async load() {
    try {
      const [vehicles, drivers] = await Promise.all([this.api.companyVehicles(this.ctx.id), this.api.companyDrivers(this.ctx.id)]);
      this.vehicles = vehicles; this.activeDrivers = drivers.filter((d: any) => d.status === 'ACTIVE');
    } catch (e: any) { this.error = errorMessage(e?.code); }
    this.loaded = true;
  }
  hasDoc(x: any, t: string) { return (x.document_types || []).includes(t); }
  short(t: string) { return ({REGISTRATION: 'Carte grise', VEHICLE_INSURANCE: 'Assurance', TECHNICAL_INSPECTION: 'Contrôle technique'} as any)[t]; }
  async add() {
    this.busy = true; this.error = ''; this.message = '';
    try {
      await this.api.addCompanyVehicle(this.ctx.id, {...this.v, year: Number(this.v.year), seats: Number(this.v.seats), baggageCapacity: Number(this.v.baggageCapacity), color: this.v.color.trim() || null});
      this.message = 'Véhicule ajouté : téléversez sa carte grise et son assurance pour la vérification VEYRA.';
      this.v = this.blank(); this.adding = false; await this.load();
    } catch (e: any) { this.error = errorMessage(e?.code); }
    finally { this.busy = false; }
  }
  async assign(x: any, driverId: string) {
    this.error = ''; this.message = '';
    try { await this.api.assignCompanyVehicle(this.ctx.id, x.id, driverId || null); this.message = driverId ? 'Véhicule attribué.' : 'Véhicule retiré du chauffeur.'; await this.load(); }
    catch (e: any) { this.error = errorMessage(e?.code); await this.load(); }
  }
}

/** SOC-05 / SOC-06 / SOC-08: affiliated drivers and invitations. */
@Component({
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="mhead"><h1>Chauffeurs</h1>
      <div class="row">
        <span class="mono" style="background:#fff;border:1px solid var(--line);border-radius:10px;padding:9px 12px">Code d'invitation : <b>{{code}}</b></span>
        <button class="ghost" (click)="rotate()" title="L'ancien code ne fonctionnera plus">Nouveau code</button>
        <button (click)="inviting = !inviting">Inviter par e-mail</button>
      </div></div>
    <div class="note">Le chauffeur choisit « Chauffeur affilié » dans l'application VEYRA Chauffeur et saisit ce code. Vous validez ensuite son rattachement ; VEYRA vérifie ses pièces avant tout accès aux demandes.</div>
    <div class="card" *ngIf="inviting">
      <div class="row"><input type="email" [(ngModel)]="email" placeholder="adresse e-mail du chauffeur" aria-label="E-mail du chauffeur" style="max-width:340px">
        <button (click)="invite()" [disabled]="!email.trim()">Envoyer l'invitation</button></div>
    </div>
    <div class="errbox" *ngIf="error">{{error}}</div>
    <div class="okbox" *ngIf="message">{{message}}</div>

    <div class="tablewrap">
      <table>
        <thead><tr><th>Chauffeur</th><th>Véhicule attribué</th><th>Rattachement</th><th>VEYRA</th><th></th></tr></thead>
        <tbody><tr *ngFor="let d of drivers">
          <td><b>{{d.first_name}} {{d.last_name}}</b>
            <div class="sub" *ngIf="d.status === 'ACTIVE'">{{d.vtc_expires_at ? 'Carte VTC valide jusqu’au ' + day(d.vtc_expires_at) : 'Carte VTC non renseignée'}}</div>
            <div class="sub" *ngIf="d.status === 'PENDING'">Demande reçue le {{day(d.requested_at)}}</div></td>
          <td>
            <ng-container *ngIf="d.status === 'ACTIVE'">{{d.vehicles || 'Aucun'}}</ng-container>
            <select *ngIf="d.status === 'PENDING'" [(ngModel)]="choice[d.affiliation_id]" aria-label="Véhicule à attribuer" style="min-width:200px">
              <option value="">Sans véhicule pour l'instant</option>
              <option *ngFor="let v of freeVehicles" [value]="v.id">{{v.brand}} {{v.model}} · {{v.plate_number}}</option>
            </select>
          </td>
          <td><span class="pill" [ngClass]="d.status === 'ACTIVE' ? 'p-ok' : 'p-warn'">{{d.status === 'ACTIVE' ? 'Validé' : 'À valider'}}</span></td>
          <td><span class="pill" [ngClass]="d.kyc_status === 'APPROVED' ? 'p-ok' : d.kyc_status === 'REJECTED' ? 'p-bad' : 'p-mute'">{{d.kyc_status === 'APPROVED' ? 'Approuvé' : d.kyc_status === 'REJECTED' ? 'À corriger' : 'En attente'}}</span></td>
          <td>
            <div class="row" *ngIf="d.status === 'PENDING'">
              <button (click)="approve(d)">{{choice[d.affiliation_id] ? 'Valider et attribuer' : 'Valider'}}</button>
              <button class="danger" (click)="reject(d)">Refuser</button>
            </div>
            <ng-container *ngIf="d.status === 'ACTIVE'">
              <button class="ghost" *ngIf="ending !== d.affiliation_id" (click)="ending = d.affiliation_id">Retirer de la flotte</button>
              <div class="row" *ngIf="ending === d.affiliation_id"><span class="sub">Ses véhicules lui seront retirés.</span>
                <button class="danger" (click)="end(d)">Confirmer</button><button class="link" (click)="ending = ''">Annuler</button></div>
            </ng-container>
          </td>
        </tr></tbody>
      </table>
    </div>
    <p class="empty" *ngIf="loaded && !drivers.length">Aucun chauffeur pour l'instant. Partagez votre code d'invitation.</p>

    <div class="card" *ngIf="invitations.length">
      <h3>Invitations envoyées</h3>
      <div class="row between" *ngFor="let i of invitations" style="border-top:1px solid #EEF1F6;padding-top:8px">
        <span>{{i.email}} <span class="sub">· {{day(i.created_at)}}</span></span>
        <button class="link" (click)="revoke(i)">Annuler l'invitation</button>
      </div>
    </div>`
})
export class CompanyDrivers implements OnInit {
  day = day;
  drivers: any[] = []; invitations: any[] = []; freeVehicles: any[] = []; choice: Record<string, string> = {};
  code = ''; email = ''; inviting = false; ending = ''; loaded = false; error = ''; message = '';
  constructor(private api: Api, private ctx: CompanyContext) {}
  async ngOnInit() { this.code = this.ctx.current?.invite_code || ''; await this.load(); }
  async load() {
    try {
      const [drivers, invitations, vehicles] = await Promise.all([
        this.api.companyDrivers(this.ctx.id), this.api.companyInvitations(this.ctx.id), this.api.companyVehicles(this.ctx.id)]);
      this.drivers = drivers; this.invitations = invitations;
      for (const d of drivers) if (d.status === 'PENDING' && this.choice[d.affiliation_id] === undefined) this.choice[d.affiliation_id] = '';
      this.freeVehicles = vehicles.filter((v: any) => !v.driver_id && v.status !== 'REJECTED');
    } catch (e: any) { this.error = errorMessage(e?.code); }
    this.loaded = true;
  }
  private async act(call: () => Promise<any>, ok: string) {
    this.error = ''; this.message = '';
    try { await call(); this.message = ok; await this.load(); } catch (e: any) { this.error = errorMessage(e?.code); }
  }
  approve(d: any) { return this.act(() => this.api.approveAffiliation(this.ctx.id, d.affiliation_id, this.choice[d.affiliation_id] || null), 'Rattachement validé.'); }
  reject(d: any) { return this.act(() => this.api.rejectAffiliation(this.ctx.id, d.affiliation_id), 'Demande refusée.'); }
  end(d: any) { this.ending = ''; return this.act(() => this.api.endAffiliation(this.ctx.id, d.affiliation_id), 'Chauffeur retiré de la flotte.'); }
  revoke(i: any) { return this.act(() => this.api.revokeCompanyInvitation(this.ctx.id, i.id), 'Invitation annulée.'); }
  async invite() {
    await this.act(() => this.api.inviteCompanyDriver(this.ctx.id, this.email.trim()), 'Invitation envoyée avec votre code.');
    if (!this.error) { this.email = ''; this.inviting = false; }
  }
  async rotate() {
    this.error = '';
    try { this.code = (await this.api.rotateCompanyCode(this.ctx.id)).inviteCode; await this.ctx.load(); this.message = 'Nouveau code créé : l’ancien ne fonctionne plus.'; }
    catch (e: any) { this.error = errorMessage(e?.code); }
  }
}

/** SOC-03 / SOC-04: operating and vehicle documents. */
@Component({
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="mhead"><div><h1>Documents</h1><div class="sub">Documents d'exploitation de la société et pièces de chaque véhicule. Les exigences exactes restent à confirmer juridiquement.</div></div></div>
    <div class="errbox" *ngIf="error">{{error}}</div>
    <div class="okbox" *ngIf="message">{{message}}</div>

    <div class="grid2">
      <div class="card">
        <h3>Société</h3>
        <div class="row between" *ngFor="let t of required" style="border-top:1px solid #EEF1F6;padding-top:8px">
          <span>{{documentTypeLabel(t)}}</span>
          <span class="pill" [ngClass]="docFor(t, null) ? (docFor(t, null).status === 'APPROVED' ? 'p-ok' : 'p-info') : 'p-warn'">{{docFor(t, null) ? (docFor(t, null).status === 'APPROVED' ? 'Conforme' : 'Envoyé') : 'À téléverser'}}</span>
        </div>
      </div>
      <div class="card">
        <h3>Téléverser</h3>
        <div class="field"><label for="d-scope">Concerne</label>
          <select id="d-scope" [(ngModel)]="vehicleId" (ngModelChange)="type = types[0]">
            <option value="">La société</option>
            <option *ngFor="let v of vehicles" [value]="v.id">{{v.brand}} {{v.model}} · {{v.plate_number}}</option>
          </select></div>
        <div class="field"><label for="d-type">Document</label>
          <select id="d-type" [(ngModel)]="type"><option *ngFor="let t of types" [value]="t">{{documentTypeLabel(t)}}</option></select></div>
        <div class="field"><label for="d-exp">Date de fin de validité</label><input id="d-exp" type="date" [(ngModel)]="expiresAt" [min]="today"></div>
        <div class="field"><label for="d-file">Fichier (PDF ou photo)</label><input id="d-file" type="file" accept="application/pdf,image/*" (change)="pick($event)"></div>
        <div class="row"><button (click)="upload()" [disabled]="busy || !file">{{busy ? 'Envoi…' : 'Téléverser'}}</button></div>
      </div>
    </div>

    <div class="tablewrap">
      <table>
        <thead><tr><th>Document</th><th>Concerne</th><th>Fin de validité</th><th>Statut</th><th></th></tr></thead>
        <tbody><tr *ngFor="let d of documents">
          <td>{{documentTypeLabel(d.type)}}</td>
          <td>{{d.vehicle_id ? d.brand + ' ' + d.model + ' · ' + d.plate_number : 'Société'}}</td>
          <td>{{d.expires_at ? day(d.expires_at) : '—'}}</td>
          <td><span class="pill" [ngClass]="d.status === 'APPROVED' ? 'p-ok' : d.status === 'REJECTED' ? 'p-bad' : 'p-info'">{{kycStatusLabel(d.status)}}</span></td>
          <td><button class="ghost" (click)="view(d)">Voir</button></td>
        </tr></tbody>
      </table>
    </div>
    <p class="empty" *ngIf="loaded && !documents.length">Aucun document téléversé.</p>`
})
export class CompanyDocuments implements OnInit {
  documentTypeLabel = documentTypeLabel; kycStatusLabel = kycStatusLabel; day = day;
  required = ['KBIS', 'REVTC_CERTIFICATE', 'RC_INSURANCE'];
  documents: any[] = []; vehicles: any[] = []; loaded = false; busy = false; error = ''; message = '';
  vehicleId = ''; type = 'KBIS'; expiresAt = ''; file: File | null = null;
  today = new Date().toISOString().slice(0, 10);
  constructor(private api: Api, private ctx: CompanyContext) {}
  get types() { return this.vehicleId ? ['REGISTRATION', 'VEHICLE_INSURANCE', 'TECHNICAL_INSPECTION'] : ['KBIS', 'REVTC_CERTIFICATE', 'RC_INSURANCE', 'OTHER']; }
  async ngOnInit() {
    const q = new URLSearchParams(location.search);
    this.vehicleId = q.get('vehicle') || '';
    const t = q.get('type');
    this.type = t && this.types.includes(t) ? t : this.types[0];
    await this.load();
  }
  async load() {
    try {
      [this.documents, this.vehicles] = await Promise.all([this.api.companyDocuments(this.ctx.id), this.api.companyVehicles(this.ctx.id)]);
    } catch (e: any) { this.error = errorMessage(e?.code); }
    this.loaded = true;
  }
  docFor(type: string, vehicle: string | null) { return this.documents.find(d => d.type === type && (d.vehicle_id || null) === vehicle); }
  pick(e: Event) { this.file = (e.target as HTMLInputElement).files?.[0] || null; }
  async upload() {
    if (!this.file) return;
    this.busy = true; this.error = ''; this.message = '';
    try {
      await this.api.uploadCompanyDocument(this.ctx.id, this.type, this.file, this.vehicleId || null, this.expiresAt || null);
      this.message = documentTypeLabel(this.type) + ' téléversé.'; this.file = null; this.expiresAt = '';
      (document.getElementById('d-file') as HTMLInputElement).value = '';
      await this.load();
    } catch (e: any) { this.error = errorMessage(e?.code); }
    finally { this.busy = false; }
  }
  async view(d: any) {
    try { const blob = await this.api.requestBlob('/company/documents/' + d.id + '/content'); window.open(URL.createObjectURL(blob), '_blank'); }
    catch { this.error = 'Document introuvable ou accès refusé.'; }
  }
}

/** SOC-10: rides of the affiliated drivers this month. */
@Component({
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="mhead"><div><h1>Activité</h1><div class="sub">Courses terminées ce mois par vos chauffeurs affiliés, au prix net chauffeur.</div></div></div>
    <div class="errbox" *ngIf="error">{{error}}</div>
    <div class="grid4" *ngIf="data">
      <div class="card kpi"><div class="n">{{data.rides.length}}</div><div class="l">Courses ce mois</div></div>
      <div class="card kpi"><div class="n">{{money(data.driverNetTotalMinor)}}</div><div class="l">Total net chauffeurs</div></div>
    </div>
    <div class="tablewrap" *ngIf="data?.rides.length">
      <table>
        <thead><tr><th>Date</th><th>Chauffeur</th><th>Trajet</th><th>Net chauffeur</th></tr></thead>
        <tbody><tr *ngFor="let r of data.rides">
          <td>{{when(r.scheduled_at)}}</td>
          <td>{{r.first_name}} {{r.last_name}}</td>
          <td><div class="route"><b>{{short(r.pickup_address)}} → {{short(r.dropoff_address)}}</b></div></td>
          <td>{{r.driver_price_minor !== null ? money(r.driver_price_minor) : '—'}}</td>
        </tr></tbody>
      </table>
    </div>
    <p class="empty" *ngIf="data && !data.rides.length">Aucune course terminée ce mois.</p>`
})
export class CompanyActivity implements OnInit {
  money = money; when = when;
  data: any = null; error = '';
  constructor(private api: Api, private ctx: CompanyContext) {}
  async ngOnInit() { try { this.data = await this.api.companyActivity(this.ctx.id); } catch (e: any) { this.error = errorMessage(e?.code); } }
  short(a: string) { return (a || '').split(',')[0]; }
}
