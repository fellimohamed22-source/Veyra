import {Routes} from '@angular/router';
import {Login} from './views/login';
import {Partner} from './views/partner';
import {Admin} from './views/admin';
import {Finance} from './views/finance';
import {Support} from './views/support';
import {authGuard} from './auth.guard';

export const routes:Routes=[
  {path:'login',component:Login},
  {path:'partner',component:Partner,canActivate:[authGuard]},
  {path:'admin',component:Admin,canActivate:[authGuard]},
  {path:'finance',component:Finance,canActivate:[authGuard]},
  {path:'support',component:Support,canActivate:[authGuard]},
  {path:'',pathMatch:'full',redirectTo:'login'}
];
