import {CommonModule} from '@angular/common';
import {AfterViewInit, Component, ElementRef, EventEmitter, Input, OnDestroy, Output, ViewChild} from '@angular/core';
import {money} from '../formatters';

declare global { interface Window { Stripe?: any } }

let stripeScript: Promise<void> | null = null;

/** Loads Stripe.js once (it must come from js.stripe.com for PCI compliance). */
function loadStripeJs(): Promise<void> {
  if (window.Stripe) return Promise.resolve();
  if (!stripeScript) {
    stripeScript = new Promise<void>((resolve, reject) => {
      const s = document.createElement('script');
      s.src = 'https://js.stripe.com/v3/';
      s.onload = () => resolve();
      s.onerror = () => { stripeScript = null; reject(new Error('STRIPE_JS_UNAVAILABLE')); };
      document.head.appendChild(s);
    });
  }
  return stripeScript;
}

/**
 * Card form of the web portals (DEC-04): Stripe Payment Element mounted
 * on the booking's PaymentIntent. Card data goes straight to Stripe;
 * VEYRA never sees it. The webhook records the capture.
 */
@Component({
  selector: 'card-payment',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="stack">
      <div #host style="min-height:44px"></div>
      <p class="sub" *ngIf="loading">Chargement du formulaire de paiement…</p>
      <div class="errbox" *ngIf="error">{{error}}</div>
      <button class="gold" (click)="pay()" [disabled]="loading || paying || !ready">{{paying ? 'Paiement…' : 'Payer ' + money(amountMinor)}}</button>
      <p class="sub">Paiement sécurisé par Stripe. VEYRA ne reçoit jamais les données de la carte.</p>
    </div>`
})
export class CardPayment implements AfterViewInit, OnDestroy {
  money = money;
  @Input({required: true}) publishableKey = '';
  @Input({required: true}) clientSecret = '';
  @Input() amountMinor = 0;
  @Output() paid = new EventEmitter<void>();
  @ViewChild('host', {static: true}) host!: ElementRef<HTMLDivElement>;
  loading = true; paying = false; ready = false; error = '';
  private stripe: any; private elements: any; private element: any;

  async ngAfterViewInit() {
    try {
      await loadStripeJs();
      this.stripe = window.Stripe!(this.publishableKey, {locale: 'fr'});
      this.elements = this.stripe.elements({clientSecret: this.clientSecret, appearance: {theme: 'stripe', variables: {colorPrimary: '#021C38', borderRadius: '10px'}}});
      this.element = this.elements.create('payment', {layout: 'tabs'});
      this.element.on('ready', () => { this.ready = true; this.loading = false; });
      this.element.mount(this.host.nativeElement);
    } catch {
      this.loading = false;
      this.error = 'Le paiement en ligne est momentanément indisponible. Réessayez plus tard.';
    }
  }

  ngOnDestroy() { try { this.element?.destroy(); } catch {} }

  async pay() {
    this.paying = true; this.error = '';
    try {
      const r = await this.stripe.confirmPayment({elements: this.elements, redirect: 'if_required', confirmParams: {return_url: location.href}});
      if (r.error) this.error = r.error.message || 'Le paiement a été refusé.';
      else if (['succeeded', 'processing'].includes(r.paymentIntent?.status)) this.paid.emit();
      else this.error = 'Le paiement n’a pas abouti. Réessayez.';
    } catch { this.error = 'Le paiement n’a pas abouti. Réessayez.'; }
    finally { this.paying = false; }
  }
}
