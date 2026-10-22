import {CommonModule} from '@angular/common';
import {Component} from '@angular/core';
import {FormsModule} from '@angular/forms';
import {RouterLink} from '@angular/router';
import {Api} from '../api';

/**
 * « Mot de passe oublié » of the web portals: the server e-mails a one-time
 * code valid 30 minutes; the code and a new password (10 characters
 * minimum) reset the account. Same answer whether the e-mail exists or not.
 */
@Component({
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink],
  template: `
    <div class="login">
      <div class="card">
        <div class="brand"><img src="assets/branding/veyra_wordmark_navy.svg" alt="VEYRA" class="wordmark"></div>
        <p class="sub" style="text-align:center;margin:0">Réinitialiser votre mot de passe</p>
        <ng-container *ngIf="step === 'email'">
          <div class="field"><label for="fp-mail">E-mail du compte</label><input id="fp-mail" type="email" [(ngModel)]="email" autocomplete="username"></div>
          <div class="errbox" *ngIf="error">{{error}}</div>
          <button (click)="request()" [disabled]="loading || !validEmail">{{loading ? 'Envoi…' : 'Recevoir un code'}}</button>
        </ng-container>
        <ng-container *ngIf="step === 'code'">
          <div class="note">Si un compte existe pour {{email}}, un code valable 30 minutes vient d'être envoyé par e-mail.</div>
          <div class="field"><label for="fp-code">Code reçu</label><input id="fp-code" [(ngModel)]="code" autocomplete="one-time-code"></div>
          <div class="field"><label for="fp-pass">Nouveau mot de passe (10 caractères minimum)</label><input id="fp-pass" type="password" [(ngModel)]="password" autocomplete="new-password"></div>
          <div class="errbox" *ngIf="error">{{error}}</div>
          <button (click)="reset()" [disabled]="loading || !code.trim() || password.length < 10">{{loading ? 'Enregistrement…' : 'Changer le mot de passe'}}</button>
          <button class="link" (click)="step = 'email'; error = ''">Renvoyer un code</button>
        </ng-container>
        <div class="okbox" *ngIf="step === 'done'">Mot de passe modifié. Vous pouvez vous connecter.</div>
        <p class="sub" style="text-align:center;margin:0"><a routerLink="/login">Retour à la connexion</a></p>
      </div>
    </div>`
})
export class ForgotPassword {
  step: 'email' | 'code' | 'done' = 'email';
  email = ''; code = ''; password = ''; loading = false; error = '';
  constructor(private api: Api) {}
  get validEmail() { return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(this.email.trim()); }
  async request() {
    this.loading = true; this.error = '';
    try { await this.api.forgotPassword(this.email.trim()); this.step = 'code'; }
    catch { this.error = 'Service momentanément indisponible. Réessayez.'; }
    finally { this.loading = false; }
  }
  async reset() {
    this.loading = true; this.error = '';
    try { await this.api.resetPassword(this.code.trim(), this.password); this.step = 'done'; }
    catch { this.error = 'Code invalide ou expiré, ou mot de passe trop court.'; }
    finally { this.loading = false; }
  }
}
