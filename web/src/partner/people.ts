import {CommonModule} from '@angular/common';
import {Component, OnInit} from '@angular/core';
import {FormsModule} from '@angular/forms';
import {Api} from '../api';
import {PartnerContext} from './context';
import {dateTime, errorMessage, invoiceStatusLabel, money, partnerOrgStatusLabel} from '../formatters';

/** Passagers enregistrés (facultatif : une réservation n'en exige pas). */
@Component({
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="mhead"><div><h1>Passagers</h1><div class="sub">Vos clients habituels, pour réserver plus vite. Une réservation n'exige pas de passager enregistré.</div></div></div>
    <div class="grid2">
      <div class="card">
        <h3>Ajouter un passager</h3>
        <div class="field"><label for="p-name">Nom complet</label><input id="p-name" [(ngModel)]="name"></div>
        <div class="field"><label for="p-phone">Téléphone</label><input id="p-phone" [(ngModel)]="phone" placeholder="+33 6 12 34 56 78"></div>
        <div class="field"><label for="p-mail">E-mail (facultatif)</label><input id="p-mail" type="email" [(ngModel)]="email"></div>
        <div class="errbox" *ngIf="error">{{error}}</div>
        <button (click)="add()" [disabled]="saving || !name.trim()">{{saving ? 'Enregistrement…' : 'Ajouter'}}</button>
      </div>
      <div class="card">
        <h3>{{people.length}} passager{{people.length > 1 ? 's' : ''}}</h3>
        <p class="empty" *ngIf="loaded && !people.length">Aucun passager enregistré.</p>
        <div class="row between" *ngFor="let p of people" style="border-top:1px solid #EEF1F6;padding-top:8px">
          <div class="route"><b>{{p.full_name}}</b><span class="sub">{{p.phone || '—'}}<span *ngIf="p.email"> · {{p.email}}</span></span></div>
        </div>
      </div>
    </div>`
})
export class PartnerPassengers implements OnInit {
  people: any[] = []; loaded = false;
  name = ''; phone = ''; email = ''; saving = false; error = '';
  constructor(private api: Api, private ctx: PartnerContext) {}
  async ngOnInit() { await this.load(); }
  async load() {
    try { this.people = await this.api.partnerBeneficiaries(this.ctx.partnerId); } catch { this.people = []; }
    this.loaded = true;
  }
  async add() {
    this.saving = true; this.error = '';
    try {
      await this.api.createPartnerBeneficiary(this.ctx.partnerId, {fullName: this.name.trim(), phone: this.phone.trim() || null, email: this.email.trim() || null, externalReference: null});
      this.name = ''; this.phone = ''; this.email = '';
      await this.load();
    } catch (e: any) { this.error = errorMessage(e?.code); }
    finally { this.saving = false; }
  }
}

/** Factures et conditions commerciales (propriétaire, comptabilité). */
@Component({
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="mhead"><div><h1>Factures</h1><div class="sub">Facturation mensuelle et conditions commerciales de l'établissement.</div></div></div>
    <div class="grid4" *ngIf="finance">
      <div class="card kpi"><div class="n">{{finance.credit_status === 'APPROVED' ? money(finance.credit_limit_minor) : '—'}}</div><div class="l">Crédit accordé</div></div>
      <div class="card kpi"><div class="n">{{money(finance.outstanding_minor)}}</div><div class="l">Encours</div></div>
      <div class="card kpi"><div class="n">{{money(finance.overdue_minor)}}</div><div class="l">En retard</div></div>
      <div class="card kpi"><div class="n">{{rate}}</div><div class="l">Commission appliquée</div></div>
    </div>
    <div class="note" *ngIf="finance && finance.credit_status !== 'APPROVED'">La facturation mensuelle s'ouvre quand VEYRA accorde un crédit à l'établissement. En attendant, les courses sont réglées en ligne.</div>
    <div class="errbox" *ngIf="error">{{error}}</div>
    <p class="empty" *ngIf="loaded && !invoices.length">Aucune facture pour le moment.</p>
    <div class="tablewrap" *ngIf="invoices.length">
      <table>
        <thead><tr><th>Période</th><th>Courses</th><th>Montant</th><th>Échéance</th><th>Statut</th></tr></thead>
        <tbody><tr *ngFor="let i of invoices">
          <td>{{day(i.period_start)}} → {{day(i.period_end)}}</td><td>{{i.items_count}}</td><td><b>{{money(i.total_minor, i.currency)}}</b></td>
          <td>{{i.due_at ? day(i.due_at) : '—'}}</td><td><span class="pill" [ngClass]="i.status === 'PAID' ? 'p-ok' : i.status === 'OVERDUE' ? 'p-bad' : 'p-info'">{{invoiceStatusLabel(i.status)}}</span></td>
        </tr></tbody>
      </table>
    </div>`
})
export class PartnerInvoices implements OnInit {
  money = money; invoiceStatusLabel = invoiceStatusLabel;
  invoices: any[] = []; finance: any = null; loaded = false; error = '';
  constructor(private api: Api, private ctx: PartnerContext) {}
  async ngOnInit() {
    try { this.finance = await this.api.partnerFinance(this.ctx.partnerId); } catch (e: any) { this.error = errorMessage(e?.code); }
    try { this.invoices = await this.api.partnerInvoices(this.ctx.partnerId); } catch { this.invoices = []; }
    this.loaded = true;
  }
  get rate() {
    if (!this.finance) return '—';
    const pct = (this.finance.commission_bps || 0) / 100;
    const fixed = this.finance.commission_fixed_minor ? ' + ' + money(this.finance.commission_fixed_minor) : '';
    return pct.toLocaleString('fr-FR') + ' %' + fixed;
  }
  day(raw: string) { return dateTime(raw).split(' ')[0]; }
}

/** Équipe et permissions (PART-16). Propriétaire uniquement. */
@Component({
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="mhead"><div><h1>Équipe</h1><div class="sub">Les factures sont réservées au propriétaire et à la comptabilité.</div></div></div>
    <div class="card">
      <h3>Inviter un membre</h3>
      <div class="row">
        <input style="max-width:320px" type="email" [(ngModel)]="email" placeholder="adresse@etablissement.fr" aria-label="E-mail">
        <select style="max-width:200px" [(ngModel)]="role" aria-label="Rôle">
          <option value="PARTNER_STAFF">Réception</option><option value="PARTNER_FINANCE">Comptabilité</option><option value="PARTNER_OWNER">Propriétaire</option>
        </select>
        <button (click)="invite()" [disabled]="inviting || !email.trim()">{{inviting ? 'Envoi…' : 'Inviter'}}</button>
      </div>
      <div class="sub">Une personne sans compte reçoit un e-mail ; l'invitation s'applique à sa première connexion avec cette adresse.</div>
      <div class="okbox" *ngIf="message">{{message}}</div>
      <div class="errbox" *ngIf="error">{{error}}</div>
    </div>
    <div class="tablewrap">
      <table>
        <thead><tr><th>Membre</th><th>Rôle</th><th>Réserver</th><th>Choisir le chauffeur</th><th>Factures</th><th>Statut</th><th></th></tr></thead>
        <tbody><tr *ngFor="let m of team">
          <td><b>{{name(m)}}</b><div class="sub">{{m.email}}</div></td>
          <td>
            <select *ngIf="!m.invitation; else invitedRole" [ngModel]="m.partner_role" (ngModelChange)="changeRole(m, $event)" aria-label="Rôle">
              <option value="PARTNER_STAFF">Réception</option><option value="PARTNER_FINANCE">Comptabilité</option><option value="PARTNER_OWNER">Propriétaire</option>
            </select>
            <ng-template #invitedRole>{{roleLabel(m.partner_role)}}</ng-template>
          </td>
          <td>{{m.partner_role !== 'PARTNER_FINANCE' ? 'Oui' : 'Non'}}</td>
          <td>{{m.partner_role !== 'PARTNER_FINANCE' ? 'Oui' : 'Non'}}</td>
          <td>{{m.partner_role !== 'PARTNER_STAFF' ? 'Oui' : 'Non'}}</td>
          <td><span class="pill" [ngClass]="m.invitation ? 'p-info' : m.status === 'ACTIVE' ? 'p-ok' : 'p-mute'">{{m.invitation ? 'Invitation envoyée' : m.status === 'ACTIVE' ? 'Actif' : 'Désactivé'}}</span></td>
          <td><button class="link" *ngIf="m.invitation || m.status === 'ACTIVE'" (click)="remove(m)">{{m.invitation ? 'Annuler' : 'Désactiver'}}</button></td>
        </tr></tbody>
      </table>
    </div>`
})
export class PartnerTeam implements OnInit {
  team: any[] = []; email = ''; role = 'PARTNER_STAFF'; inviting = false; message = ''; error = '';
  constructor(private api: Api, private ctx: PartnerContext) {}
  async ngOnInit() { await this.load(); }
  async load() { try { this.team = await this.api.partnerTeam(this.ctx.partnerId); } catch (e: any) { this.error = errorMessage(e?.code); } }
  async invite() {
    this.inviting = true; this.error = ''; this.message = '';
    try {
      const r = await this.api.invitePartnerMember(this.ctx.partnerId, this.email.trim(), this.role);
      this.message = r.status === 'ACTIVE' ? 'Membre ajouté à l’équipe.' : 'Invitation envoyée.';
      this.email = '';
      await this.load();
    } catch (e: any) { this.error = errorMessage(e?.code); }
    finally { this.inviting = false; }
  }
  async changeRole(m: any, role: string) {
    this.error = '';
    try { await this.api.changePartnerMemberRole(this.ctx.partnerId, m.id, role); await this.load(); } catch (e: any) { this.error = errorMessage(e?.code); await this.load(); }
  }
  async remove(m: any) {
    this.error = '';
    try { await this.api.removePartnerMember(this.ctx.partnerId, m.id); await this.load(); } catch (e: any) { this.error = errorMessage(e?.code); }
  }
  name(m: any) { return m.invitation ? 'Invitation en attente' : `${m.first_name || ''} ${m.last_name || ''}`.trim() || m.email; }
  roleLabel(r: string) { return {PARTNER_OWNER: 'Propriétaire', PARTNER_STAFF: 'Réception', PARTNER_FINANCE: 'Comptabilité'}[r] || r; }
}

/** Établissement : identité, statut de vérification, conditions. */
@Component({
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="mhead"><div><h1>Établissement</h1><div class="sub">Informations de votre organisation chez VEYRA.</div></div></div>
    <div class="grid2" *ngIf="ctx.current as o">
      <div class="card">
        <h3>{{o.name}}</h3>
        <div class="row between"><span class="sub">Type</span><b>{{typeLabel(o.partner_type)}}</b></div>
        <div class="row between"><span class="sub">Statut</span><span class="pill" [ngClass]="o.status === 'APPROVED' ? 'p-ok' : o.status === 'SUSPENDED' ? 'p-bad' : 'p-warn'">{{partnerOrgStatusLabel(o.status)}}</span></div>
        <div class="row between"><span class="sub">E-mail de facturation</span><b>{{o.billing_email || '—'}}</b></div>
        <div class="row between"><span class="sub">Votre rôle</span><b>{{roleLabel(o.partner_role)}}</b></div>
      </div>
      <div class="card">
        <h3>Facturation mensuelle</h3>
        <div class="row between"><span class="sub">Crédit</span><span class="pill" [ngClass]="o.credit_status === 'APPROVED' ? 'p-ok' : 'p-mute'">{{o.credit_status === 'APPROVED' ? 'Accordé' : o.credit_status === 'ON_HOLD' ? 'Suspendu' : 'Non accordé'}}</span></div>
        <div class="row between" *ngIf="o.credit_status === 'APPROVED'"><span class="sub">Plafond</span><b>{{money(o.credit_limit_minor, o.currency || 'EUR')}}</b></div>
        <div class="note">Pour modifier ces informations ou demander un crédit, contactez VEYRA.</div>
      </div>
    </div>`
})
export class PartnerEstablishment {
  money = money; partnerOrgStatusLabel = partnerOrgStatusLabel;
  constructor(public ctx: PartnerContext) {}
  typeLabel(t: string) { return {HOTEL: 'Hôtel', RESTAURANT: 'Restaurant', BAR: 'Bar', CONCIERGE: 'Conciergerie', COMPANY: 'Entreprise'}[t] || t; }
  roleLabel(r: string) { return {PARTNER_OWNER: 'Propriétaire', PARTNER_STAFF: 'Réception', PARTNER_FINANCE: 'Comptabilité'}[r] || r; }
}
