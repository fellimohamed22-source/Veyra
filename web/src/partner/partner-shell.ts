import {CommonModule} from '@angular/common';
import {Component, OnInit} from '@angular/core';
import {FormsModule} from '@angular/forms';
import {Router, RouterOutlet} from '@angular/router';
import {Api} from '../api';
import {PortalShell, NavItem} from '../portal/shell';
import {PartnerContext} from './context';
import {errorMessage} from '../formatters';

/**
 * Partner portal (hotel, company): validated mock-up DEC-13. Without an
 * establishment yet, the user creates one first.
 */
@Component({
  standalone: true,
  imports: [CommonModule, FormsModule, RouterOutlet, PortalShell],
  template: `
    <portal-shell [subtitle]="ctx.current?.name || 'Espace partenaire'" [items]="items" [who]="who" (logout)="logout()">
      <ng-container side-extra *ngIf="ctx.organizations.length > 1">
        <select class="org" [ngModel]="ctx.partnerId" (ngModelChange)="switchTo($event)" aria-label="Établissement">
          <option *ngFor="let o of ctx.organizations" [value]="o.id">{{o.name}}</option>
        </select>
      </ng-container>

      <p *ngIf="!ctx.loaded" class="sub">Chargement…</p>

      <ng-container *ngIf="ctx.loaded && !ctx.partnerId">
        <div class="mhead"><div><h1>Créez votre établissement</h1>
          <div class="sub">Hôtel, restaurant, entreprise : réservez des courses pour vos clients et suivez-les.</div></div></div>
        <div class="card" style="max-width:520px">
          <div class="field"><label for="org-name">Nom de l'établissement</label><input id="org-name" [(ngModel)]="name" placeholder="Ex. Hôtel Le Marceau"></div>
          <div class="field"><label for="org-type">Type</label>
            <select id="org-type" [(ngModel)]="type">
              <option value="HOTEL">Hôtel</option><option value="RESTAURANT">Restaurant</option>
              <option value="BAR">Bar</option><option value="CONCIERGE">Conciergerie</option><option value="COMPANY">Entreprise</option>
            </select></div>
          <div class="field"><label for="org-mail">E-mail de facturation</label><input id="org-mail" type="email" [(ngModel)]="billingEmail"></div>
          <div class="errbox" *ngIf="error">{{error}}</div>
          <button class="gold" (click)="create()" [disabled]="creating || !name.trim()">{{creating ? 'Création…' : 'Créer l’établissement'}}</button>
          <div class="note">L'établissement est vérifié par VEYRA. La facturation mensuelle s'ouvre après accord d'un crédit.</div>
        </div>
      </ng-container>

      <router-outlet *ngIf="ctx.loaded && ctx.partnerId"></router-outlet>
    </portal-shell>`,
  styles: [`.org{background:rgba(255,255,255,.1);color:#fff;border-color:rgba(255,255,255,.2);margin:6px 0}.org option{color:#0E1A2B}`]
})
export class PartnerShell implements OnInit {
  who = '';
  name = ''; type = 'HOTEL'; billingEmail = ''; creating = false; error = '';

  constructor(public ctx: PartnerContext, private api: Api, private router: Router) {}

  items: NavItem[] = [];

  /** Built once per context change: a getter would recreate the router links on every check. */
  private buildItems(): NavItem[] {
    const items: NavItem[] = [{label: 'Tableau de bord', link: '/partner', exact: true}];
    if (this.ctx.books) items.push({label: 'Réserver', link: '/partner/reserver'});
    items.push({label: 'Réservations', link: '/partner/reservations'}, {label: 'Passagers', link: '/partner/passagers'});
    if (this.ctx.seesFinance) items.push({label: 'Factures', link: '/partner/factures'});
    if (this.ctx.isOwner) items.push({label: 'Équipe', link: '/partner/equipe'});
    items.push({label: 'Établissement', link: '/partner/etablissement'});
    return items;
  }

  async ngOnInit() {
    await this.ctx.load();
    this.items = this.buildItems();
    try { const me = await this.api.me(); this.who = `${me.first_name || ''} ${me.last_name || ''}`.trim() || me.email; } catch {}
  }

  switchTo(id: string) { this.ctx.select(id); this.items = this.buildItems(); this.router.navigateByUrl('/partner'); }

  async create() {
    this.creating = true; this.error = '';
    try {
      const r = await this.api.createPartner({name: this.name.trim(), partnerType: this.type, billingEmail: this.billingEmail.trim() || null});
      await this.ctx.load();
      this.ctx.select(r.partnerId);
      this.items = this.buildItems();
    } catch (e: any) { this.error = errorMessage(e?.code); }
    finally { this.creating = false; }
  }

  logout() { this.api.logout(); this.router.navigateByUrl('/login'); }
}
