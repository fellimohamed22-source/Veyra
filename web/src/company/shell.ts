import {CommonModule} from '@angular/common';
import {Component, Injectable, OnInit} from '@angular/core';
import {FormsModule} from '@angular/forms';
import {Router, RouterOutlet} from '@angular/router';
import {Api} from '../api';
import {PortalShell, NavItem} from '../portal/shell';
import {errorMessage} from '../formatters';

/** The VTC company the signed-in manager works for. */
@Injectable({providedIn: 'root'})
export class CompanyContext {
  companies: any[] = [];
  loaded = false;
  constructor(private api: Api) {}
  get current(): any { return this.companies[0] || null; }
  get id(): string { return this.current?.id || ''; }
  async load(): Promise<void> {
    try { this.companies = await this.api.myCompanies(); } catch { this.companies = []; }
    this.loaded = true;
  }
}

/** Company status pill of the validated mock-up. */
export function companyPill(status: string): {text: string; css: string} {
  switch (status) {
    case 'APPROVED': return {text: 'Société approuvée', css: 'p-ok'};
    case 'SUBMITTED': return {text: 'En vérification VEYRA', css: 'p-info'};
    case 'REJECTED': return {text: 'Dossier à corriger', css: 'p-bad'};
    case 'SUSPENDED': return {text: 'Société suspendue', css: 'p-bad'};
    default: return {text: 'Dossier à compléter', css: 'p-warn'};
  }
}

/**
 * VTC company portal (validated mock-up DEC-13, SOC-01..10). Without a
 * company yet, the manager registers it first (SOC-01/02).
 */
@Component({
  standalone: true,
  imports: [CommonModule, FormsModule, RouterOutlet, PortalShell],
  template: `
    <portal-shell [subtitle]="ctx.current?.legal_name || 'Société VTC'" [items]="items" [who]="who" (logout)="logout()">
      <p *ngIf="!ctx.loaded" class="sub">Chargement…</p>

      <ng-container *ngIf="ctx.loaded && !ctx.id">
        <div class="mhead"><div><h1>Inscrivez votre société VTC</h1>
          <div class="sub">Gérez votre flotte, vos documents d'exploitation et vos chauffeurs affiliés. VEYRA vérifie la société avant tout accès aux demandes.</div></div></div>
        <div class="card" style="max-width:560px">
          <div class="field"><label for="c-name">Raison sociale</label><input id="c-name" [(ngModel)]="form.legalName" maxlength="180" placeholder="Ex. Transports Prestige"></div>
          <div class="grid2">
            <div class="field"><label for="c-siren">SIREN</label><input id="c-siren" [(ngModel)]="form.siren" inputmode="numeric" maxlength="11" placeholder="9 chiffres"></div>
            <div class="field"><label for="c-revtc">N° d'inscription au registre VTC</label><input id="c-revtc" [(ngModel)]="form.revtcNumber" maxlength="32" placeholder="Ex. EVTC075230145"></div>
          </div>
          <div class="field"><label for="c-addr">Adresse du siège</label><input id="c-addr" [(ngModel)]="form.address" maxlength="255"></div>
          <div class="field"><label for="c-mail">E-mail de contact</label><input id="c-mail" type="email" [(ngModel)]="form.contactEmail" maxlength="254"></div>
          <div class="errbox" *ngIf="error">{{error}}</div>
          <button class="gold" (click)="create()" [disabled]="creating || !form.legalName.trim() || !form.siren.trim()">{{creating ? 'Création…' : 'Créer la société'}}</button>
          <div class="note">Étapes suivantes : téléverser le Kbis, l'attestation REVTC et l'assurance, ajouter vos véhicules, puis envoyer le dossier à VEYRA.</div>
        </div>
      </ng-container>

      <router-outlet *ngIf="ctx.loaded && ctx.id"></router-outlet>
    </portal-shell>`
})
export class CompanyShell implements OnInit {
  who = '';
  items: NavItem[] = [];
  form = {legalName: '', siren: '', revtcNumber: '', address: '', contactEmail: ''};
  creating = false; error = '';

  constructor(public ctx: CompanyContext, private api: Api, private router: Router) {}

  private buildItems(): NavItem[] {
    if (!this.ctx.id) return [];
    return [
      {label: 'Tableau de bord', link: '/societe', exact: true},
      {label: 'Véhicules', link: '/societe/vehicules'},
      {label: 'Chauffeurs', link: '/societe/chauffeurs'},
      {label: 'Documents', link: '/societe/documents'},
      {label: 'Activité', link: '/societe/activite'},
    ];
  }

  async ngOnInit() {
    await this.ctx.load();
    this.items = this.buildItems();
    try { const me = await this.api.me(); this.who = `${me.first_name || ''} ${me.last_name || ''}`.trim() || me.email; } catch {}
  }

  async create() {
    this.creating = true; this.error = '';
    const f = this.form;
    try {
      await this.api.createCompany({legalName: f.legalName.trim(), siren: f.siren.replace(/\s/g, ''), revtcNumber: f.revtcNumber.trim() || null,
        address: f.address.trim() || null, contactEmail: f.contactEmail.trim() || null});
      await this.ctx.load();
      this.items = this.buildItems();
    } catch (e: any) { this.error = errorMessage(e?.code); }
    finally { this.creating = false; }
  }

  logout() { this.api.logout(); this.router.navigateByUrl('/login'); }
}
