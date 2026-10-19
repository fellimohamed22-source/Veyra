import {Routes} from '@angular/router';
import {Login} from './views/login';
import {AdminBookings, AdminCommissions, AdminDashboard, AdminDriverReview, AdminPartners, AdminSettings, AdminVerifications} from './admin/pages';
import {Finance} from './views/finance';
import {Support} from './views/support';
import {authGuard} from './auth.guard';
import {Guest} from './views/guest';
import {PartnerShell} from './partner/partner-shell';
import {PartnerDashboard} from './partner/dashboard';
import {PartnerBook} from './partner/book';
import {PartnerBookings} from './partner/bookings';
import {PartnerBookingDetail} from './partner/booking-detail';
import {PartnerEstablishment, PartnerInvoices, PartnerPassengers, PartnerTeam} from './partner/people';
import {AdminShell} from './admin/admin-shell';

export const routes: Routes = [
  {path: 'login', component: Login},
  // Public passenger tracking link (PART-13); authorised by its token only.
  {path: 'suivi/:token', component: Guest},
  // Partner portal (validated mock-up DEC-13).
  {
    path: 'partner', component: PartnerShell, canActivate: [authGuard], children: [
      {path: '', component: PartnerDashboard},
      {path: 'reserver', component: PartnerBook},
      {path: 'reservations', component: PartnerBookings},
      {path: 'reservations/:id', component: PartnerBookingDetail},
      {path: 'passagers', component: PartnerPassengers},
      {path: 'factures', component: PartnerInvoices},
      {path: 'equipe', component: PartnerTeam},
      {path: 'etablissement', component: PartnerEstablishment},
    ]
  },
  // Administration portal.
  {
    path: 'admin', component: AdminShell, canActivate: [authGuard], children: [
      {path: '', component: AdminDashboard},
      {path: 'verifications', component: AdminVerifications},
      {path: 'verifications/:id', component: AdminDriverReview},
      {path: 'reservations', component: AdminBookings},
      {path: 'commissions', component: AdminCommissions},
      {path: 'partenaires', component: AdminPartners},
      {path: 'parametres', component: AdminSettings},
      {path: 'finance', component: Finance},
      {path: 'support', component: Support},
    ]
  },
  // Former addresses kept working.
  {path: 'finance', pathMatch: 'full', redirectTo: 'admin/finance'},
  {path: 'support', pathMatch: 'full', redirectTo: 'admin/support'},
  {path: '', pathMatch: 'full', redirectTo: 'login'}
];
