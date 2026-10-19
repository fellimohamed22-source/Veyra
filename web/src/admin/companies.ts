import {CommonModule} from '@angular/common';
import {Component, Input, OnInit} from '@angular/core';
import {FormsModule} from '@angular/forms';
import {RouterLink} from '@angular/router';
import {Api} from '../api';
import {dateTime, documentTypeLabel, errorMessage, kycStatusLabel} from '../formatters';

/** Sociétés VTC (SOC-03/04): VEYRA review of the company and of each fleet vehicle. */
@Component({
  standalone: true,
  imports: [CommonModule, RouterLink],
  template: `
    <div class="mhead"><div><h1>Sociétés VTC</h1><div class="sub">La société valide ses chauffeurs ; VEYRA approuve la société, chaque véhicule et chaque chauffeur.</div></div></div>
    <div class="errbox" *ngIf="error">{{error}}</div>
    <div class="tablewrap">
      <table>
        <thead><tr><th>Société</th><th>SIREN</th><th>Véhicules</th><th>Chauffeurs</th><th>Statut</th><th></th></tr></thead>
        <tbody><tr *ngFor="let c of companies">
          <td><b>{{c.legal_name}}</b><div class="sub">{{c.revtc_number || 'REVTC non renseigné'}}</div></td>
          <td class="mono">{{c.siren}}</td>
          <td>{{c.vehicles}}<span class="sub" *ngIf="c.pending_vehicles"> · {{c.pending_vehicles}} à vérifier</span></td>
          <td>{{c.drivers}}</td>
          <td><span class="pill" [ngClass]="companyCss(c.status)">{{companyLabel(c.status)}}</span></td>
          <td><button [class.ghost]="!toReview(c)" [routerLink]="['/admin/societes', c.id]">{{toReview(c) ? 'Vérifier' : 'Voir'}}</button></td>
        </tr></tbody>
      </table>
    </div>
    <p class="empty" *ngIf="loaded && !companies.length">Aucune société inscrite.</p>`
})
export class AdminCompanies implements OnInit {
  companies: any[] = []; loaded = false; error = '';
  constructor(private api: Api) {}
  async ngOnInit() {
    try { this.companies = await this.api.adminCompanies(); } catch (e: any) { this.error = errorMessage(e?.code); }
    this.loaded = true;
  }
  toReview(c: any) { return c.status === 'SUBMITTED' || Number(c.pending_vehicles) > 0; }
  companyLabel(s: string) { return ({DRAFT: 'Brouillon', SUBMITTED: 'À vérifier', APPROVED: 'Approuvée', REJECTED: 'Correction demandée', SUSPENDED: 'Suspendue'} as any)[s] || s; }
  companyCss(s: string) { return s === 'APPROVED' ? 'p-ok' : s === 'SUBMITTED' ? 'p-warn' : s === 'DRAFT' ? 'p-mute' : 'p-bad'; }
}

/** Review of one company: identity, documents, fleet vehicles. */
@Component({
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink],
  template: `
    <p class="sub"><a routerLink="/admin/societes">← Sociétés VTC</a></p>
    <div class="errbox" *ngIf="error">{{error}}</div>
    <div class="okbox" *ngIf="message">{{message}}</div>
    <ng-container *ngIf="c">
      <div class="mhead">
        <div><h1>{{c.legal_name}}</h1><div class="sub">SIREN {{c.siren}} · REVTC {{c.revtc_number || '—'}} · {{c.owner_email}}</div></div>
        <div class="row">
          <ng-container *ngIf="c.status === 'SUBMITTED'">
            <select [(ngModel)]="reason" aria-label="Motif" style="width:auto">
              <option value="DOCUMENT_INVALID">Document illisible ou invalide</option>
              <option value="DOCUMENT_EXPIRED">Document expiré</option>
              <option value="DOCUMENT_MISSING">Document manquant</option>
              <option value="IDENTITY_MISMATCH">Identité incohérente</option>
            </select>
            <button class="danger" (click)="reject()">Demander une correction</button>
          </ng-container>
          <button *ngIf="c.status === 'SUBMITTED' || c.status === 'SUSPENDED'" (click)="approve()">Approuver la société</button>
          <button class="danger" *ngIf="c.status === 'APPROVED'" (click)="suspend()">Suspendre</button>
        </div>
      </div>
      <div class="grid2">
        <div class="card"><h3>Documents de la société</h3>
          <p class="empty" *ngIf="!companyDocs.length">Aucun document.</p>
          <div class="row between" *ngFor="let d of companyDocs" style="border-top:1px solid #EEF1F6;padding-top:8px">
            <span>{{documentTypeLabel(d.type)}}<span class="sub" *ngIf="d.expires_at"> · fin {{day(d.expires_at)}}</span></span>
            <span class="row"><span class="pill" [ngClass]="d.status === 'APPROVED' ? 'p-ok' : 'p-warn'">{{kycStatusLabel(d.status)}}</span>
              <button class="ghost" (click)="view(d.id)">Voir</button></span>
          </div>
        </div>
        <div class="card"><h3>Véhicules</h3>
          <p class="empty" *ngIf="!c.vehicles.length">Aucun véhicule.</p>
          <div class="stack" *ngFor="let v of c.vehicles" style="border-top:1px solid #EEF1F6;padding-top:8px">
            <div class="row between">
              <span><b>{{v.brand}} {{v.model}} · {{v.year}} · {{v.plate_number}}</b><div class="sub">{{v.category_name}}<span *ngIf="v.seats"> · {{v.seats}} places</span></div></span>
              <span class="pill" [ngClass]="v.status === 'APPROVED' ? 'p-ok' : v.status === 'REJECTED' ? 'p-bad' : 'p-warn'">{{v.status === 'APPROVED' ? 'Approuvé' : v.status === 'REJECTED' ? 'Refusé' : 'À vérifier'}}</span>
            </div>
            <div class="row" *ngFor="let d of docsOf(v.id)"><span class="sub">{{documentTypeLabel(d.type)}}<span *ngIf="d.expires_at"> · fin {{day(d.expires_at)}}</span></span><button class="link" (click)="view(d.id)">Voir</button></div>
            <div class="sub" *ngIf="!docsOf(v.id).length">Aucune pièce téléversée.</div>
            <div class="row" *ngIf="v.status !== 'APPROVED'">
              <button (click)="approveVehicle(v)">Approuver</button>
              <button class="danger" *ngIf="v.status === 'PENDING'" (click)="rejectVehicle(v)">Refuser</button>
            </div>
          </div>
        </div>
      </div>
    </ng-container>`
})
export class AdminCompanyReview implements OnInit {
  documentTypeLabel = documentTypeLabel; kycStatusLabel = kycStatusLabel;
  @Input() id = '';
  c: any = null; error = ''; message = ''; reason = 'DOCUMENT_INVALID';
  constructor(private api: Api) {}
  async ngOnInit() { await this.load(); }
  async load() { try { this.c = await this.api.adminCompany(this.id); } catch (e: any) { this.error = errorMessage(e?.code); } }
  get companyDocs() { return (this.c?.documents || []).filter((d: any) => !d.vehicle_id); }
  docsOf(vehicleId: string) { return (this.c?.documents || []).filter((d: any) => d.vehicle_id === vehicleId); }
  day(raw: string) { return dateTime(raw).split(' ')[0]; }
  approve() { return this.act(() => this.api.approveCompany(this.id), 'Société approuvée.'); }
  reject() { return this.act(() => this.api.rejectCompany(this.id, this.reason), 'Correction demandée.'); }
  suspend() { return this.act(() => this.api.suspendCompany(this.id), 'Société suspendue : sa flotte est retirée des demandes.'); }
  approveVehicle(v: any) { return this.act(() => this.api.approveCompanyVehicle(this.id, v.id), 'Véhicule approuvé.'); }
  rejectVehicle(v: any) { return this.act(() => this.api.rejectCompanyVehicle(this.id, v.id, 'VEHICLE_NOT_COMPLIANT'), 'Véhicule refusé.'); }
  private async act(call: () => Promise<any>, ok: string) {
    this.error = ''; this.message = '';
    try { await call(); this.message = ok; await this.load(); } catch (e: any) { this.error = errorMessage(e?.code); }
  }
  async view(id: string) {
    try { const blob = await this.api.requestBlob('/company/documents/' + id + '/content'); window.open(URL.createObjectURL(blob), '_blank'); }
    catch { this.error = 'Document introuvable ou accès refusé.'; }
  }
}
