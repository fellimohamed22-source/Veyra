import {CommonModule} from '@angular/common';
import {Component, OnInit} from '@angular/core';
import {FormsModule} from '@angular/forms';
import {Api} from '../api';
import {dateTime, statusLabel} from '../formatters';

const CATEGORY: Record<string, string> = {
  DRIVER_LATE: 'Chauffeur en retard', DRIVER_NOT_FOUND: 'Chauffeur introuvable', SAFETY: 'Sécurité',
  VEHICLE: 'Véhicule', ROUTE: 'Itinéraire', PAYMENT: 'Paiement', OTHER: 'Autre',
};

/** Support: « Signaler un problème » reports to handle, booking lookup. */
@Component({
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="mhead"><div><h1>Support</h1><div class="sub">Signalements envoyés depuis les applications et recherche d'une réservation.</div></div></div>
    <div class="errbox" *ngIf="reportError">{{reportError}}</div>
    <div class="card">
      <div class="mhead"><h3>Signalements à traiter</h3><span class="pill" [ngClass]="reports.length ? 'p-warn' : 'p-ok'">{{reports.length}}</span></div>
      <p class="empty" *ngIf="loaded && !reports.length">Aucun signalement en attente.</p>
      <div class="tablewrap" *ngIf="reports.length">
        <table>
          <thead><tr><th>Reçu</th><th>Motif</th><th>Message</th><th>Signalé par</th><th>Réservation</th><th></th></tr></thead>
          <tbody><tr *ngFor="let r of reports">
            <td>{{dateTime(r.created_at)}}</td>
            <td><span class="pill" [ngClass]="r.category === 'SAFETY' ? 'p-bad' : 'p-warn'">{{category(r.category)}}</span></td>
            <td>{{r.message || '—'}}</td>
            <td>{{r.first_name}} {{r.last_name}}<div class="sub">{{r.email}}</div></td>
            <td><button class="link" (click)="bookingId = r.booking_id; search()">{{statusLabel(r.booking_status)}}</button></td>
            <td><button class="ghost" (click)="resolve(r)">Marquer traité</button></td>
          </tr></tbody>
        </table>
      </div>
    </div>
    <div class="card">
      <h3>Recherche réservation</h3>
      <div class="row"><input [(ngModel)]="bookingId" placeholder="Identifiant de la réservation" style="max-width:420px">
        <button (click)="search()" [disabled]="loading">Rechercher</button></div>
      <div class="errbox" *ngIf="error">{{error}}</div>
    </div>
    <div class="card" *ngIf="result">
      <h3>Détail</h3>
      <pre style="white-space:pre-wrap">{{result | json}}</pre>
    </div>`
})
export class Support implements OnInit {
  dateTime = dateTime; statusLabel = statusLabel;
  bookingId = ''; result: any = null; loading = false; error = '';
  reports: any[] = []; loaded = false; reportError = '';
  constructor(private api: Api) {}
  async ngOnInit() { await this.loadReports(); }
  async loadReports() {
    try { this.reports = await this.api.problemReports(); } catch { this.reportError = 'Signalements indisponibles.'; }
    this.loaded = true;
  }
  category(c: string) { return CATEGORY[c] || c; }
  async resolve(r: any) {
    try { await this.api.resolveProblemReport(r.id); await this.loadReports(); } catch { this.reportError = 'Action impossible pour le moment.'; }
  }
  async search() {
    if (!this.bookingId.trim()) return;
    this.loading = true; this.error = '';
    try { this.result = await this.api.supportTimeline(this.bookingId.trim()); }
    catch { this.result = null; this.error = 'Réservation introuvable ou accès refusé.'; }
    finally { this.loading = false; }
  }
}
