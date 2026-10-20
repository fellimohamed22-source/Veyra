import {CommonModule} from '@angular/common';
import {Component, Input} from '@angular/core';
import {FormsModule} from '@angular/forms';
import {Router, RouterLink} from '@angular/router';
import {Api} from '../api';
import {errorMessage} from '../formatters';

/**
 * Professional account for the web portals: a VTC company manager
 * (?profil=societe) or an establishment (?profil=partenaire). The
 * company or establishment itself is created right after, in its portal.
 */
@Component({
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink],
  template: `
    <div class="login">
      <div class="card">
        <div class="brand"><img src="assets/branding/veyra_wordmark_navy.svg" alt="VEYRA" class="wordmark"></div>
        <p class="sub" style="text-align:center;margin:0">{{company ? 'Créer l’espace de votre société VTC' : 'Créer l’espace de votre établissement'}}</p>
        <div class="seg" style="justify-self:center">
          <button type="button" [class.on]="company" (click)="profil = 'societe'">Société VTC</button>
          <button type="button" [class.on]="!company" (click)="profil = 'partenaire'">Hôtel, entreprise</button>
        </div>
        <div class="grid2">
          <div class="field"><label for="s-first">Prénom</label><input id="s-first" [(ngModel)]="firstName" maxlength="100" autocomplete="given-name"></div>
          <div class="field"><label for="s-last">Nom</label><input id="s-last" [(ngModel)]="lastName" maxlength="100" autocomplete="family-name"></div>
        </div>
        <div class="field"><label for="s-mail">E-mail professionnel</label><input id="s-mail" type="email" [(ngModel)]="email" autocomplete="email"></div>
        <div class="field"><label for="s-pass">Mot de passe (10 caractères minimum)</label><input id="s-pass" type="password" [(ngModel)]="password" autocomplete="new-password"></div>
        <label class="row" style="font-weight:500;color:var(--ink)"><input type="checkbox" [(ngModel)]="terms" style="width:auto;min-height:0"> J'accepte les conditions générales d'utilisation</label>
        <label class="row" style="font-weight:500;color:var(--ink)"><input type="checkbox" [(ngModel)]="privacy" style="width:auto;min-height:0"> J'accepte la politique de confidentialité</label>
        <div class="errbox" *ngIf="error">{{error}}</div>
        <button class="gold" (click)="register()" [disabled]="loading || !valid">{{loading ? 'Création…' : 'Créer mon compte'}}</button>
        <p class="sub" style="text-align:center;margin:0">Déjà un compte ? <a routerLink="/login">Se connecter</a></p>
      </div>
    </div>`
})
export class Signup {
  @Input() profil = 'societe';
  firstName = ''; lastName = ''; email = ''; password = ''; terms = false; privacy = false;
  loading = false; error = '';
  constructor(private api: Api, private router: Router) {}
  get company() { return this.profil !== 'partenaire'; }
  get valid() { return !!this.firstName.trim() && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(this.email.trim()) && this.password.length >= 10 && this.terms && this.privacy; }
  async register() {
    this.loading = true; this.error = '';
    try {
      await this.api.register({firstName: this.firstName.trim(), lastName: this.lastName.trim() || null, email: this.email.trim(), password: this.password,
        acceptTerms: this.terms, acceptPrivacy: this.privacy, marketingOptIn: false});
      await this.router.navigateByUrl(this.company ? '/societe' : '/partner');
    } catch (e: any) { this.error = errorMessage(e?.code); }
    finally { this.loading = false; }
  }
}
