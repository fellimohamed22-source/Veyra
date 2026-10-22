import {CommonModule} from '@angular/common';
import {Component, OnInit} from '@angular/core';
import {FormsModule} from '@angular/forms';
import {Api} from '../api';
import {dateTime, errorMessage, money} from '../formatters';

/** Finance: CASH debts of drivers, customer debts, driver payouts, partner invoicing. */
@Component({
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="mhead"><div><h1>Finance</h1><div class="sub">Dettes CASH, créances clients, versements chauffeurs et facturation des établissements.</div></div>
      <button class="ghost" (click)="load()" [disabled]="loading">Actualiser</button></div>
    <div class="errbox" *ngIf="error">{{error}}</div>
    <div class="okbox" *ngIf="message">{{message}}</div>

    <div class="grid4">
      <div class="card kpi"><div class="n">{{money(open(debts))}}</div><div class="l">Dettes CASH chauffeurs ouvertes</div></div>
      <div class="card kpi"><div class="n">{{money(open(customerDebts))}}</div><div class="l">Créances clients ouvertes</div></div>
      <div class="card kpi"><div class="n">{{money(toPay)}}</div><div class="l">Versements chauffeurs à faire</div></div>
      <div class="card kpi"><div class="n">50 / 100 / 150 €</div><div class="l">Seuils CASH : alerte / restriction / blocage</div></div>
    </div>

    <div class="card">
      <h3>Dettes CASH des chauffeurs</h3>
      <p class="empty" *ngIf="!debts.length">Aucune dette.</p>
      <div class="tablewrap" *ngIf="debts.length">
        <table>
          <thead><tr><th>Chauffeur</th><th>Montant</th><th>Restant</th><th>Statut</th><th></th></tr></thead>
          <tbody><tr *ngFor="let d of debts">
            <td><b>{{d.driver_name || 'Chauffeur'}}</b><div class="sub mono">course {{short(d.booking_id)}}</div></td>
            <td>{{money(d.amount_minor)}}</td>
            <td>{{money(remaining(d))}}</td>
            <td><span class="pill" [ngClass]="remaining(d) > 0 ? 'p-warn' : 'p-ok'">{{remaining(d) > 0 ? 'À régler' : 'Réglée'}}</span></td>
            <td><button class="ghost" *ngIf="remaining(d) > 0" (click)="settle(d)">Marquer réglée</button></td>
          </tr></tbody>
        </table>
      </div>
    </div>

    <div class="card">
      <h3>Créances clients (annulations CASH)</h3>
      <p class="empty" *ngIf="!customerDebts.length">Aucune créance.</p>
      <div class="tablewrap" *ngIf="customerDebts.length">
        <table>
          <thead><tr><th>Client</th><th>Montant</th><th>Restant</th><th>Part chauffeur</th><th>Statut</th><th></th></tr></thead>
          <tbody><tr *ngFor="let d of customerDebts">
            <td><b>{{d.email}}</b><div class="sub mono">course {{short(d.booking_id)}}</div></td>
            <td>{{money(d.amount_minor)}}</td>
            <td>{{money(remaining(d))}}</td>
            <td>{{d.driver_compensation_minor ? money(d.driver_compensation_minor) : '—'}}</td>
            <td><span class="pill" [ngClass]="d.status === 'PAID' ? 'p-ok' : 'p-warn'">{{d.status === 'PAID' ? 'Réglée' : 'À régler'}}</span></td>
            <td><button class="ghost" *ngIf="d.status !== 'PAID' && remaining(d) > 0" (click)="settleCustomer(d)">Marquer réglée</button></td>
          </tr></tbody>
        </table>
      </div>
    </div>

    <div class="card">
      <h3>Versements aux chauffeurs</h3>
      <p class="empty" *ngIf="!payables.length">Aucun versement.</p>
      <div class="tablewrap" *ngIf="payables.length">
        <table>
          <thead><tr><th>Chauffeur</th><th>Montant net</th><th>Depuis</th><th>Statut</th><th></th></tr></thead>
          <tbody><tr *ngFor="let p of payables">
            <td><b>{{p.driver_name || 'Chauffeur'}}</b><div class="sub mono">course {{short(p.booking_id)}}</div></td>
            <td>{{money(p.amount_minor)}}</td>
            <td>{{p.created_at ? dateTime(p.created_at) : '—'}}</td>
            <td><span class="pill" [ngClass]="p.status === 'PAYABLE' ? 'p-warn' : 'p-ok'">{{p.status === 'PAYABLE' ? 'À verser' : 'Versé'}}</span></td>
            <td><button class="ghost" *ngIf="p.status === 'PAYABLE'" (click)="markPaid(p)">Marquer versé</button></td>
          </tr></tbody>
        </table>
      </div>
    </div>

    <div class="card">
      <h3>Facturation d'un établissement</h3>
      <div class="grid3">
        <div class="field"><label for="f-partner">Établissement</label>
          <select *ngIf="partners.length" id="f-partner" [(ngModel)]="invoicePartnerId"><option value="">Choisir</option><option *ngFor="let p of partners" [value]="p.id">{{p.name}}</option></select>
          <input *ngIf="!partners.length" id="f-partner" [(ngModel)]="invoicePartnerId" placeholder="Identifiant de l'établissement"></div>
        <div class="field"><label for="f-from">Du</label><input id="f-from" [(ngModel)]="invoiceFrom" type="date"></div>
        <div class="field"><label for="f-to">Au</label><input id="f-to" [(ngModel)]="invoiceTo" type="date"></div>
      </div>
      <div class="row"><button (click)="generateInvoice()" [disabled]="invoiceLoading || !invoicePartnerId || !invoiceFrom || !invoiceTo">{{invoiceLoading ? 'Génération…' : 'Générer la facture'}}</button></div>
      <div class="okbox" *ngIf="invoiceResult && !invoiceResult.error">Facture générée{{invoiceResult.totalMinor !== undefined ? ' : ' + money(invoiceResult.totalMinor) : ''}}.</div>
      <div class="errbox" *ngIf="invoiceResult?.error">{{errorMessage(invoiceResult.error)}}</div>
    </div>`
})
export class Finance implements OnInit {
  money = money; dateTime = dateTime; errorMessage = errorMessage;
  debts: any[] = []; customerDebts: any[] = []; payables: any[] = []; partners: any[] = [];
  loading = false; error = ''; message = '';
  invoicePartnerId = ''; invoiceFrom = ''; invoiceTo = ''; invoiceLoading = false; invoiceResult: any = null;
  constructor(private api: Api) {}
  async ngOnInit() {
    await this.load();
    try { this.partners = await this.api.adminPartners(); } catch {}
  }
  async load() {
    this.loading = true; this.error = '';
    try {
      [this.debts, this.customerDebts, this.payables] = await Promise.all([this.api.cashDebts(), this.api.customerDebts(), this.api.payables()]);
    } catch { this.error = 'Impossible de charger les données finance.'; }
    finally { this.loading = false; }
  }
  remaining(d: any) { return Math.max(0, (d.amount_minor || 0) - (d.paid_amount_minor || 0)); }
  open(list: any[]) { return list.reduce((s, d) => s + (d.status === 'PAID' ? 0 : this.remaining(d)), 0); }
  get toPay() { return this.payables.filter(p => p.status === 'PAYABLE').reduce((s, p) => s + (p.amount_minor || 0), 0); }
  short(id: any) { return id ? String(id).slice(0, 8).toUpperCase() : '—'; }
  private async act(fn: () => Promise<any>, ok: string) {
    this.error = ''; this.message = '';
    try { await fn(); this.message = ok; await this.load(); } catch (e: any) { this.error = errorMessage(e?.code); }
  }
  settle(d: any) { return this.act(() => this.api.settleDebt(d.id, this.remaining(d)), 'Dette réglée.'); }
  settleCustomer(d: any) { return this.act(() => this.api.settleCustomerDebt(d.id, this.remaining(d)), 'Créance réglée.'); }
  markPaid(p: any) { return this.act(() => this.api.markPayablePaid(p.id), 'Versement enregistré.'); }
  async generateInvoice() {
    this.invoiceLoading = true; this.invoiceResult = null;
    try { this.invoiceResult = await this.api.generatePartnerInvoice(this.invoicePartnerId, this.invoiceFrom, this.invoiceTo) || {}; }
    catch (e: any) { this.invoiceResult = {error: e?.code || 'GENERATION_FAILED'}; }
    finally { this.invoiceLoading = false; }
  }
}
