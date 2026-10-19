import {Component, OnInit} from '@angular/core';
import {Router, RouterOutlet} from '@angular/router';
import {Api} from '../api';
import {PortalShell, NavItem} from '../portal/shell';

/** Administration portal layout (validated mock-up DEC-13). */
@Component({
  standalone: true,
  imports: [RouterOutlet, PortalShell],
  template: `
    <portal-shell subtitle="Administration" [items]="items" [who]="who" (logout)="logout()">
      <router-outlet></router-outlet>
    </portal-shell>`
})
export class AdminShell implements OnInit {
  who = '';
  roles: string[] = [];
  constructor(private api: Api, private router: Router) {}

  items: NavItem[] = [];

  /** Built once per context change: a getter would recreate the router links on every check. */
  private buildItems(): NavItem[] {
    const admin = this.roles.includes('ADMIN');
    const items: NavItem[] = [];
    if (admin) items.push({label: 'Tableau de bord', link: '/admin', exact: true});
    if (admin || this.roles.includes('FINANCE')) items.push({label: 'Finance', link: '/admin/finance'});
    if (admin || this.roles.includes('SUPPORT')) items.push({label: 'Support', link: '/admin/support'});
    return items;
  }

  async ngOnInit() {
    try {
      const me = await this.api.me();
      this.roles = me.roles || [];
      this.items = this.buildItems();
      this.who = `${me.first_name || ''} ${me.last_name || ''}`.trim() || me.email;
    } catch {}
  }

  logout() { this.api.logout(); this.router.navigateByUrl('/login'); }
}
