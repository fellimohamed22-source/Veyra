import {CommonModule} from '@angular/common';
import {Component, EventEmitter, Input, Output} from '@angular/core';
import {RouterLink, RouterLinkActive} from '@angular/router';

export interface NavItem {label: string; link: string; exact?: boolean}

/**
 * Portal layout of the validated mock-ups (DEC-13): navy sidebar with the
 * VEYRA wordmark, the organisation under it, the menu, and sign-out.
 * Pages are projected into the main area.
 */
@Component({
  selector: 'portal-shell',
  standalone: true,
  imports: [CommonModule, RouterLink, RouterLinkActive],
  template: `
    <div class="portal">
      <nav class="side" aria-label="Menu">
        <div class="brand"><img src="assets/branding/veyra_wordmark_white.svg" alt="VEYRA" class="wordmark"><small>{{subtitle}}</small></div>
        <a *ngFor="let item of items" class="nav" [routerLink]="item.link"
           routerLinkActive="on" [routerLinkActiveOptions]="{exact: !!item.exact}">{{item.label}}</a>
        <div class="spacer"></div>
        <ng-content select="[side-extra]"></ng-content>
        <div class="who" *ngIf="who">{{who}}</div>
        <button class="link" type="button" (click)="logout.emit()">Déconnexion</button>
      </nav>
      <main class="main"><ng-content></ng-content></main>
    </div>`
})
export class PortalShell {
  @Input() subtitle = '';
  @Input() items: NavItem[] = [];
  @Input() who = '';
  @Output() logout = new EventEmitter<void>();
}
