import {Injectable} from '@angular/core';
import {Api} from '../api';

/** The establishment the signed-in partner user is working for. */
@Injectable({providedIn: 'root'})
export class PartnerContext {
  organizations: any[] = [];
  loaded = false;
  partnerId = localStorage.getItem('partnerId') || '';

  constructor(private api: Api) {}

  get current(): any {
    return this.organizations.find(o => o.id === this.partnerId) || null;
  }

  get role(): string {
    return this.current?.partner_role || '';
  }

  get isOwner(): boolean { return this.role === 'PARTNER_OWNER'; }
  /** Invoices and finance: owner and accounting (lot L5). */
  get seesFinance(): boolean { return this.role === 'PARTNER_OWNER' || this.role === 'PARTNER_FINANCE'; }
  /** Booking and choosing drivers: owner and reception. */
  get books(): boolean { return this.role === 'PARTNER_OWNER' || this.role === 'PARTNER_STAFF'; }

  async load(): Promise<void> {
    try { this.organizations = await this.api.partnerOrganizations(); } catch { this.organizations = []; }
    if (!this.organizations.some(o => o.id === this.partnerId)) {
      this.select(this.organizations.length ? this.organizations[0].id : '');
    }
    this.loaded = true;
  }

  select(id: string): void {
    this.partnerId = id;
    if (id) localStorage.setItem('partnerId', id); else localStorage.removeItem('partnerId');
  }
}
