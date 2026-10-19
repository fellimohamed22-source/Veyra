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
import {AdminCompanies, AdminCompanyReview} from './admin/companies';
import {CompanyShell} from './company/shell';
import {CompanyActivity, CompanyDashboard, CompanyDocuments, CompanyDrivers, CompanyVehicles} from './company/pages';
import {Signup} from './views/signup';

export const routes: Routes = [
  {path: 'login', component: Login},
  {path: 'inscription', component: Signup},
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
  // VTC company portal (validated mock-up DEC-13, SOC-01..10).
  {
    path: 'societe', component: CompanyShell, canActivate: [authGuard], children: [
      {path: '', component: CompanyDashboard},
      {path: 'vehicules', component: CompanyVehicles},
      {path: 'chauffeurs', component: CompanyDrivers},
      {path: 'documents', component: CompanyDocuments},
      {path: 'activite', component: CompanyActivity},
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
      {path: 'societes', component: AdminCompanies},
      {path: 'societes/:id', component: AdminCompanyReview},
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
